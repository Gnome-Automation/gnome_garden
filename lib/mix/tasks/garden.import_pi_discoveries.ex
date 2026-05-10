defmodule Mix.Tasks.Garden.ImportPiDiscoveries do
  @moduledoc """
  Imports pi sidecar markdown discoveries into the Gnome database.

  Pi writes findings to `sidecar/discoveries/{bids,prospects,opportunities}/*.md`
  and sources to `sidecar/sources.json`. This task replays them through the
  same Ash actions the live RPC uses, so existing rows upsert and new ones
  land in the review queue.

  ## Usage

      mix garden.import_pi_discoveries
      mix garden.import_pi_discoveries --dry-run
      mix garden.import_pi_discoveries --family bids
      mix garden.import_pi_discoveries --family prospects --dry-run

  ## Families

  * `bids`          — `discoveries/bids/*.md`         → save_bid
  * `prospects`     — `discoveries/prospects/*.md`    → save_target
  * `opportunities` — `discoveries/opportunities/*.md` → save_opportunity
  * `sources`       — `sidecar/sources.json`          → save_source
  * `all` (default) — all four
  """
  @shortdoc "Backfill pi sidecar discoveries into the database"

  use Mix.Task

  alias GnomeGarden.Acquisition.PiRpcDispatcher
  alias GnomeGarden.Acquisition.PiRpcErrors

  @valid_families ["bids", "prospects", "opportunities", "sources", "all"]

  @impl Mix.Task
  def run(args) do
    {opts, _} =
      OptionParser.parse!(args,
        switches: [dry_run: :boolean, family: :string, sidecar: :string],
        aliases: [d: :dry_run, f: :family]
      )

    Mix.Task.run("app.start")

    family = Keyword.get(opts, :family, "all")
    dry_run? = Keyword.get(opts, :dry_run, false)
    sidecar = Keyword.get(opts, :sidecar, default_sidecar())

    unless family in @valid_families do
      Mix.raise("unknown --family #{inspect(family)}; valid: #{Enum.join(@valid_families, ", ")}")
    end

    Mix.shell().info(
      "Importing pi discoveries from #{sidecar} (family=#{family}, dry_run=#{dry_run?})"
    )

    families = if family == "all", do: ~w(sources bids prospects opportunities), else: [family]

    summary =
      Enum.reduce(families, %{}, fn family, acc ->
        Map.put(acc, family, run_family(family, sidecar, dry_run?))
      end)

    print_summary(summary)
  end

  defp run_family("bids", sidecar, dry_run?) do
    sidecar
    |> Path.join("discoveries/bids")
    |> markdown_files()
    |> import_each(&parse_bid_markdown/1, "save_bid", dry_run?)
  end

  defp run_family("prospects", sidecar, dry_run?) do
    sidecar
    |> Path.join("discoveries/prospects")
    |> markdown_files()
    |> import_each(&parse_prospect_markdown/1, "save_target", dry_run?)
  end

  defp run_family("opportunities", sidecar, dry_run?) do
    sidecar
    |> Path.join("discoveries/opportunities")
    |> markdown_files()
    |> import_each(&parse_prospect_markdown/1, "save_opportunity", dry_run?)
  end

  defp run_family("sources", sidecar, dry_run?) do
    path = Path.join(sidecar, "sources.json")

    case File.read(path) do
      {:ok, contents} ->
        case Jason.decode(contents) do
          {:ok, sources} when is_list(sources) ->
            sources
            |> Enum.map(fn json -> {nil, parse_source_json(json)} end)
            |> dispatch_each("save_source", dry_run?)

          _ ->
            empty_counts() |> Map.put(:errors, [{path, "invalid JSON"}])
        end

      {:error, reason} ->
        empty_counts() |> Map.put(:errors, [{path, "could not read: #{inspect(reason)}"}])
    end
  end

  defp markdown_files(dir) do
    case File.ls(dir) do
      {:ok, entries} ->
        entries
        |> Enum.filter(&String.ends_with?(&1, ".md"))
        |> Enum.reject(&String.starts_with?(&1, "_"))
        |> Enum.map(&Path.join(dir, &1))

      {:error, _} ->
        []
    end
  end

  defp import_each(files, parser, action, dry_run?) do
    files
    |> Enum.map(fn path ->
      case File.read(path) do
        {:ok, contents} -> {path, parser.(contents)}
        {:error, reason} -> {path, {:error, "could not read: #{inspect(reason)}"}}
      end
    end)
    |> dispatch_each(action, dry_run?)
  end

  defp dispatch_each(parsed, action, dry_run?) do
    Enum.reduce(parsed, empty_counts(), fn
      {path, {:ok, input}}, acc ->
        if dry_run? do
          %{acc | parsed: acc.parsed + 1}
        else
          case PiRpcDispatcher.dispatch(action, input) do
            {:ok, _record} ->
              %{acc | parsed: acc.parsed + 1, imported: acc.imported + 1}

            {:error, reason} ->
              errors = PiRpcErrors.format(reason)

              %{
                acc
                | parsed: acc.parsed + 1,
                  failed: acc.failed + 1,
                  errors: [{path || "(inline)", inspect(errors)} | acc.errors]
              }
          end
        end

      {path, {:error, reason}}, acc ->
        %{
          acc
          | skipped: acc.skipped + 1,
            errors: [{path || "(inline)", reason} | acc.errors]
        }
    end)
  end

  # ---------------------------------------------------------------------------
  # Parsers
  # ---------------------------------------------------------------------------

  defp parse_bid_markdown(contents) do
    table = parse_field_table(contents)
    title = parse_h1(contents) || Map.get(table, "title")
    url = Map.get(table, "url")

    if is_binary(title) and is_binary(url) and url != "" do
      input =
        %{
          "title" => title,
          "url" => url,
          "agency" => Map.get(table, "agency"),
          "location" => Map.get(table, "location"),
          "region" => normalize_region(Map.get(table, "location")),
          "estimated_value" => parse_money(Map.get(table, "estimated_value")),
          "due_at" => parse_date(Map.get(table, "due_date")),
          "score_total" => parse_int(Map.get(table, "total_score")),
          "score_tier" => parse_tier(Map.get(table, "tier")),
          "metadata" => %{"imported_from" => "pi_markdown_backfill"}
        }
        |> reject_nil_values()

      {:ok, input}
    else
      {:error, "missing title or url"}
    end
  end

  defp parse_prospect_markdown(contents) do
    table = parse_field_table(contents)
    name = parse_h1(contents) || Map.get(table, "name") || Map.get(table, "company")

    if is_binary(name) and name != "" do
      input =
        %{
          "name" => name,
          "website" => Map.get(table, "website"),
          "location" => Map.get(table, "location"),
          "region" => Map.get(table, "region"),
          "industry" => Map.get(table, "industry"),
          "fit_score" => parse_int(Map.get(table, "fit_score") || Map.get(table, "fit")),
          "intent_score" => parse_int(Map.get(table, "intent_score") || Map.get(table, "intent")),
          "notes" => extract_signal_section(contents),
          "metadata" => %{"imported_from" => "pi_markdown_backfill"}
        }
        |> reject_nil_values()

      {:ok, input}
    else
      {:error, "missing name"}
    end
  end

  defp parse_source_json(%{"name" => name, "url" => url} = json)
       when is_binary(name) and is_binary(url) do
    input =
      %{
        "name" => name,
        "url" => url,
        "source_type" => Map.get(json, "type") || "custom",
        "region" => Map.get(json, "region"),
        "portal_id" => Map.get(json, "portal_id"),
        "notes" => Map.get(json, "notes"),
        "added_by" => "agent",
        "status" => "approved",
        "enabled" => true
      }
      |> reject_nil_values()

    {:ok, input}
  end

  defp parse_source_json(_), do: {:error, "missing name or url"}

  # ---------------------------------------------------------------------------
  # Markdown helpers
  # ---------------------------------------------------------------------------

  # Extracts `| **Field** | Value |` table rows into `%{"field" => "value"}`,
  # field-keyed lowercased with underscores.
  defp parse_field_table(contents) do
    contents
    |> String.split("\n")
    |> Enum.reduce(%{}, fn line, acc ->
      case Regex.run(~r/^\|\s*\*?\*?([^|*]+?)\*?\*?\s*\|\s*(.+?)\s*\|\s*$/, line) do
        [_, field, value] ->
          key = field |> String.trim() |> String.downcase() |> String.replace(~r/\s+/, "_")
          value = value |> String.trim() |> strip_markdown()
          if key in ["field", "---"] or value == "Value", do: acc, else: Map.put(acc, key, value)

        _ ->
          acc
      end
    end)
  end

  defp parse_h1(contents) do
    case Regex.run(~r/^#\s+(.+?)\s*$/m, contents) do
      [_, title] -> String.trim(title)
      _ -> nil
    end
  end

  defp extract_signal_section(contents) do
    case Regex.run(~r/##\s+Signal\s*\n+(.+?)(?=\n##|\z)/s, contents) do
      [_, body] -> String.trim(body)
      _ -> nil
    end
  end

  defp strip_markdown(value) do
    value
    # strip leading/trailing **bold**
    |> String.replace(~r/\*\*(.+?)\*\*/, "\\1")
    # collapse markdown links to bare text
    |> String.replace(~r/\[([^\]]+)\]\([^)]+\)/, "\\1")
    |> String.trim()
  end

  defp parse_int(nil), do: nil

  defp parse_int(value) when is_binary(value) do
    case Regex.run(~r/(-?\d+)/, value) do
      [_, num] -> String.to_integer(num)
      _ -> nil
    end
  end

  defp parse_int(value) when is_integer(value), do: value
  defp parse_int(_), do: nil

  defp parse_money(nil), do: nil
  defp parse_money("Unknown" <> _), do: nil

  defp parse_money(value) when is_binary(value) do
    case Regex.run(~r/\$\s?([\d,]+(?:\.\d+)?)\s*([KkMm]?)/, value) do
      [_, num, ""] ->
        num |> String.replace(",", "") |> Float.parse() |> elem_or_nil() |> trunc_or_nil()

      [_, num, m] when m in ["K", "k"] ->
        case num |> String.replace(",", "") |> Float.parse() do
          {n, _} -> trunc(n * 1_000)
          _ -> nil
        end

      [_, num, m] when m in ["M", "m"] ->
        case num |> String.replace(",", "") |> Float.parse() do
          {n, _} -> trunc(n * 1_000_000)
          _ -> nil
        end

      _ ->
        nil
    end
  end

  defp parse_money(_), do: nil

  defp elem_or_nil({n, _}), do: n
  defp elem_or_nil(_), do: nil
  defp trunc_or_nil(n) when is_number(n), do: trunc(n)
  defp trunc_or_nil(_), do: nil

  defp parse_date(nil), do: nil
  defp parse_date("Unknown" <> _), do: nil

  defp parse_date(value) when is_binary(value) do
    case Regex.run(~r/(\d{4}-\d{2}-\d{2})/, value) do
      [_, iso] -> iso
      _ -> nil
    end
  end

  defp parse_date(_), do: nil

  defp parse_tier(nil), do: nil

  defp parse_tier(value) when is_binary(value) do
    value
    |> String.downcase()
    |> case do
      "hot" -> "hot"
      "warm" -> "warm"
      "prospect" -> "prospect"
      "rejected" -> "rejected"
      _ -> nil
    end
  end

  defp normalize_region(nil), do: nil

  defp normalize_region(value) when is_binary(value) do
    value
    |> String.downcase()
    |> case do
      "orange county" <> _ -> "oc"
      "los angeles" <> _ -> "la"
      "inland empire" <> _ -> "ie"
      "san diego" <> _ -> "sd"
      _ -> nil
    end
  end

  # ---------------------------------------------------------------------------
  # Reporting
  # ---------------------------------------------------------------------------

  defp empty_counts, do: %{parsed: 0, imported: 0, failed: 0, skipped: 0, errors: []}

  defp default_sidecar, do: Path.join(File.cwd!(), "sidecar")

  defp print_summary(summary) do
    Mix.shell().info("\nResults:")

    Enum.each(summary, fn {family, counts} ->
      Mix.shell().info(
        "  #{String.pad_trailing(family, 16)} parsed=#{counts.parsed} imported=#{counts.imported} failed=#{counts.failed} skipped=#{counts.skipped}"
      )

      Enum.each(Enum.take(counts.errors, 5), fn {path, reason} ->
        Mix.shell().info("    ! #{Path.basename(to_string(path))}: #{reason}")
      end)

      if length(counts.errors) > 5 do
        Mix.shell().info("    (#{length(counts.errors) - 5} more errors omitted)")
      end
    end)
  end

  defp reject_nil_values(map) do
    Map.reject(map, fn {_k, v} -> is_nil(v) or v == "" end)
  end
end
