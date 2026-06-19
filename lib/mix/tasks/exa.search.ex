defmodule Mix.Tasks.Exa.Search do
  @shortdoc "Dry-run an Exa lead search (search only, costs ~cents)"

  @moduledoc """
  Preview an Exa lead search — prints candidate pages and the real cost Exa
  reports, without retrieving contents or running any LLM. This is the cheap
  iteration loop for tuning query phrasing and `--category` before building the
  full discovery pipeline.

      mix exa.search "small US manufacturers seeking warehouse automation"
      mix exa.search "..." --num 15 --category company --type neural

  Requires `EXA_API_KEY` in the environment (locally: `source ~/.config/pi/env`).
  """

  use Mix.Task

  @requirements ["app.start"]

  @impl Mix.Task
  def run(argv) do
    {opts, args, _} =
      OptionParser.parse(argv, strict: [num: :integer, category: :string, type: :string])

    query = args |> Enum.join(" ") |> String.trim()

    if query == "" do
      Mix.shell().error(~s(Usage: mix exa.search "your query" [--num N] [--category company] [--type auto|neural|keyword]))
      exit({:shutdown, 1})
    end

    search_opts =
      [num_results: opts[:num] || 10, type: opts[:type] || "auto"]
      |> maybe_put(:category, opts[:category])

    case GnomeGarden.Search.Exa.search(query, search_opts) do
      {:ok, %{cost: cost, results: results}} ->
        Mix.shell().info("\nQuery:   #{query}")
        Mix.shell().info("Results: #{length(results)}    Cost: $#{cost || 0.0}\n")

        results
        |> Enum.with_index(1)
        |> Enum.each(fn {result, index} ->
          Mix.shell().info("#{String.pad_leading(to_string(index), 2)}. #{result.title || "(no title)"}")
          Mix.shell().info("    #{result.url}")
        end)

        Mix.shell().info("")

      {:error, :missing_exa_api_key} ->
        Mix.shell().error("EXA_API_KEY not set. Export it (e.g. `source ~/.config/pi/env`) before running.")

      {:error, reason} ->
        Mix.shell().error("Exa search failed: #{inspect(reason)}")
    end
  end

  defp maybe_put(opts, _key, nil), do: opts
  defp maybe_put(opts, key, value), do: Keyword.put(opts, key, value)
end
