defmodule GnomeGarden.Acquisition.SourceLaunchBatch do
  @moduledoc """
  Launches the next runnable acquisition sources as an operator batch.

  This is an orchestration boundary around existing Ash-backed source records.
  It deliberately delegates individual launches to `Acquisition.launch_source_run/2`
  so procurement-specific routing, run persistence, and source PubSub updates
  stay in the normal source launch path.
  """

  require Logger

  alias GnomeGarden.Acquisition

  @default_limit 5

  @type summary :: %{
          checked: non_neg_integer(),
          eligible: non_neg_integer(),
          launched: non_neg_integer(),
          skipped: non_neg_integer(),
          errors: non_neg_integer(),
          source_ids: [String.t()]
        }

  @spec launch_ready_sources(keyword()) :: summary()
  def launch_ready_sources(opts \\ []) do
    actor = Keyword.get(opts, :actor)
    limit = Keyword.get(opts, :limit, @default_limit)
    launch_fun = Keyword.get(opts, :launch_fun, &Acquisition.launch_source_run/2)

    case Acquisition.list_console_sources(actor: actor) do
      {:ok, sources} ->
        sources
        |> Enum.filter(&ready?/1)
        |> Enum.sort_by(&run_sort_key/1, DateTime)
        |> Enum.take(limit)
        |> launch_sources(empty_summary(length(sources)), actor, launch_fun)

      {:error, error} ->
        Logger.error("Failed to list acquisition sources for batch launch: #{inspect(error)}")
        %{empty_summary(0) | errors: 1}
    end
  end

  defp launch_sources(sources, summary, actor, launch_fun) do
    Enum.reduce(sources, %{summary | eligible: length(sources)}, fn source, acc ->
      case launch_fun.(source, actor: actor) do
        {:ok, %{run: _run}} ->
          %{
            acc
            | launched: acc.launched + 1,
              source_ids: [source.id | acc.source_ids]
          }

        {:ok, _result} ->
          %{
            acc
            | launched: acc.launched + 1,
              source_ids: [source.id | acc.source_ids]
          }

        {:error, :active_run_exists} ->
          %{acc | skipped: acc.skipped + 1}

        {:error, error} ->
          Logger.warning(
            "Failed acquisition source batch launch for #{source.name} (#{source.id}): #{inspect(error)}"
          )

          %{acc | errors: acc.errors + 1}
      end
    end)
    |> Map.update!(:source_ids, &Enum.reverse/1)
  end

  defp ready?(source) do
    source.runnable == true and source.enabled == true and
      source.status in [:active, :candidate] and source.scan_strategy != :manual
  end

  defp run_sort_key(%{last_run_at: nil}), do: DateTime.from_unix!(0)
  defp run_sort_key(%{last_run_at: last_run_at}), do: last_run_at

  defp empty_summary(checked) do
    %{
      checked: checked,
      eligible: 0,
      launched: 0,
      skipped: 0,
      errors: 0,
      source_ids: []
    }
  end
end
