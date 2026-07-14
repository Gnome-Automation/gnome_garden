defmodule GnomeGarden.Procurement.SourcePortfolioPolicy do
  @moduledoc """
  Applies bounded, evidence-based health routing to the governed source portfolio.

  The policy never deletes source history. It routes a fresh blocked episode,
  pauses three consecutive terminal failures, lowers cadence after three
  zero-yield completions, and prioritizes three productive completions. A source
  is changed at most once per newest retrieval-run episode.
  """

  alias GnomeGarden.Procurement
  alias GnomeGarden.Procurement.ProcurementSource

  @recent_run_count 3
  @minimum_frequency_hours 1
  @maximum_frequency_hours 720

  def evaluate_all(opts \\ []) do
    actor = Keyword.get(opts, :actor)

    with {:ok, sources} <-
           Procurement.list_procurement_source_health_routing_candidates(actor: actor) do
      {actions, failures} =
        Enum.reduce(sources, {[], []}, fn source, {actions, failures} ->
          case evaluate(source, actor: actor) do
            {:ok, :unchanged} -> {actions, failures}
            {:ok, action} -> {[action | actions], failures}
            {:error, error} -> {actions, [%{source_id: source.id, error: error} | failures]}
          end
        end)

      {:ok, %{actions: Enum.reverse(actions), failures: Enum.reverse(failures)}}
    end
  end

  def evaluate(%ProcurementSource{} = source, opts \\ []) do
    actor = Keyword.get(opts, :actor)

    with {:ok, runs} <- Procurement.list_recent_source_retrieval_runs(source.id, actor: actor) do
      route(source, runs, actor)
    end
  end

  defp route(_source, [], _actor), do: {:ok, :unchanged}

  defp route(source, [latest | _runs] = runs, actor) do
    cond do
      already_routed?(source, latest) ->
        {:ok, :unchanged}

      persistent_terminal_failure?(runs) ->
        pause(source, runs, actor)

      latest.status == :blocked ->
        route_blocked(source, latest, actor)

      zero_yield_streak?(runs) ->
        adjust_cadence(source, :cadence_lowered, slower_frequency(source), runs, actor)

      productive_streak?(runs) ->
        adjust_cadence(source, :prioritized, faster_frequency(source), runs, actor)

      true ->
        {:ok, :unchanged}
    end
  end

  defp already_routed?(%{health_action_at: nil}, _latest), do: false
  defp already_routed?(_source, %{completed_at: nil}), do: false

  defp already_routed?(source, latest) do
    DateTime.compare(source.health_action_at, latest.completed_at) in [:eq, :gt]
  end

  defp persistent_terminal_failure?(runs) do
    length(runs) == @recent_run_count and
      Enum.all?(runs, &(&1.status in [:failed, :blocked]))
  end

  defp zero_yield_streak?(runs) do
    length(runs) == @recent_run_count and
      Enum.all?(runs, &(&1.status == :completed and run_yield(&1) == 0))
  end

  defp productive_streak?(runs) do
    length(runs) == @recent_run_count and
      Enum.all?(runs, &(&1.status == :completed and run_yield(&1) > 0))
  end

  defp pause(source, runs, actor) do
    reason =
      "Paused after #{@recent_run_count} consecutive retrieval failures; latest: #{latest_reason(runs)}"

    case Procurement.pause_procurement_source_for_health(
           source,
           %{health_action_reason: reason},
           actor: actor
         ) do
      {:ok, updated} -> {:ok, action_summary(updated, :paused, reason)}
      {:error, error} -> {:error, error}
    end
  end

  defp route_blocked(source, run, actor) do
    {action, reason} = blocked_action(run)

    case Procurement.route_procurement_source_health_issue(
           source,
           %{last_health_action: action, health_action_reason: reason},
           actor: actor
         ) do
      {:ok, updated} -> {:ok, action_summary(updated, action, reason)}
      {:error, error} -> {:error, error}
    end
  end

  defp adjust_cadence(source, action, frequency, runs, actor) do
    if frequency == source.scan_frequency_hours do
      {:ok, :unchanged}
    else
      reason = cadence_reason(action, runs, frequency)

      case Procurement.adjust_procurement_source_scan_cadence(
             source,
             %{
               scan_frequency_hours: frequency,
               last_health_action: action,
               health_action_reason: reason
             },
             actor: actor
           ) do
        {:ok, updated} -> {:ok, action_summary(updated, action, reason)}
        {:error, error} -> {:error, error}
      end
    end
  end

  defp blocked_action(run) do
    reason = latest_reason([run])
    normalized = String.downcase(reason)

    cond do
      String.contains?(normalized, ["credential", "login", "401", "403"]) ->
        {:credential_attention, "Credentials or authentication blocked retrieval: #{reason}"}

      String.contains?(normalized, ["schema", "selector", "configuration", "config"]) ->
        {:configuration_attention, "Source configuration blocked retrieval: #{reason}"}

      true ->
        {:operator_attention, "Provider blocked retrieval and needs operator review: #{reason}"}
    end
  end

  defp slower_frequency(source),
    do:
      min(
        max(source.scan_frequency_hours * 2, @minimum_frequency_hours),
        @maximum_frequency_hours
      )

  defp faster_frequency(source),
    do: max(div(source.scan_frequency_hours, 2), @minimum_frequency_hours)

  defp cadence_reason(:cadence_lowered, runs, frequency),
    do:
      "Lowered to every #{frequency} hours after #{length(runs)} consecutive zero-yield retrievals"

  defp cadence_reason(:prioritized, runs, frequency),
    do:
      "Prioritized to every #{frequency} hours after #{length(runs)} consecutive productive retrievals"

  defp latest_reason([latest | _runs]) do
    latest.diagnostics["terminal_reason"] || latest.fallback_reason ||
      Atom.to_string(latest.status)
  end

  defp run_yield(run) do
    diagnostics = run.diagnostics || %{}

    ["saved", "rows", "extracted", "bids_found", "result_count"]
    |> Enum.find_value(0, fn key ->
      case Map.get(diagnostics, key) do
        value when is_integer(value) -> value
        values when is_list(values) -> length(values)
        _other -> nil
      end
    end)
  end

  defp action_summary(source, action, reason) do
    %{
      source_id: source.id,
      source_name: source.name,
      action: action,
      reason: reason,
      scan_frequency_hours: source.scan_frequency_hours,
      enabled: source.enabled
    }
  end
end
