defmodule GnomeGarden.Agents.Workers.PiProcess do
  @moduledoc """
  Direct-runtime worker that runs a pi sidecar via `PiRunner`.

  Plugged into `DeploymentRunner` via the `execute_run/1` interface. Filters
  `ProcurementSource` records by the deployment's `source_scope`, dumps them to
  `sidecar/sources.json`, builds a templated prompt, and starts a `PiRunner`
  under the `PiRunnerSupervisor`. Blocks via `PiRunner.await/2` until the run
  completes, an error is emitted, or the timeout elapses.
  """

  alias GnomeGarden.Agents.PiRunner

  @sources_filename "sources.json"

  def execute_run(%{run: run, deployment: deployment, timeout_ms: timeout_ms}) do
    skill = get_skill(deployment)
    prompt = build_prompt(skill, deployment)
    export_sources_json(deployment)
    run_id = to_string(run.id)

    case start_runner(run_id, skill, prompt) do
      {:ok, _pid} ->
        try do
          case PiRunner.await(run_id, timeout_ms) do
            {:ok, %{summary: summary, tool_count: tools}} ->
              {:ok,
               %{
                 text: summary,
                 usage: %{total_tokens: 0, input_tokens: 0, output_tokens: 0},
                 tool_count: tools
               }}

            {:error, reason} ->
              {:error, reason}
          end
        catch
          :exit, {:timeout, _} ->
            {:error, :timeout}

          :exit, reason ->
            {:error, {:exit, reason}}
        after
          # Always tear down the runner — guards against orphaned pi processes
          # when await throws (timeout, supervisor kill, parent crash, etc.).
          PiRunner.cancel(run_id)
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp start_runner(run_id, skill, prompt) do
    DynamicSupervisor.start_child(
      GnomeGarden.Agents.PiRunnerSupervisor,
      {PiRunner, [run_id: run_id, skill: skill, prompt: prompt]}
    )
  end

  # ---------------------------------------------------------------------------
  # Prompt + skill resolution
  # ---------------------------------------------------------------------------

  defp get_skill(%{config: config}) when is_map(config) do
    Map.get(config, "pi_skill") || Map.get(config, :pi_skill) || "scan-bids"
  end

  defp get_skill(_), do: "scan-bids"

  defp build_prompt(skill, deployment) do
    scope = deployment.source_scope || %{}
    base = default_prompt(skill)

    extras =
      []
      |> append_extra("Focus on regions: ", scope["regions"] || scope[:regions])
      |> append_extra("Target industries: ", scope["industries"] || scope[:industries])
      |> append_extra("Source types: ", scope["source_types"] || scope[:source_types])
      |> append_extra("Match keywords: ", scope["keywords"] || scope[:keywords])

    [base | Enum.reverse(extras)]
    |> Enum.join("\n")
  end

  defp append_extra(extras, _label, nil), do: extras
  defp append_extra(extras, _label, []), do: extras

  defp append_extra(extras, label, values) when is_list(values) do
    ["#{label}#{Enum.join(values, ", ")}." | extras]
  end

  defp append_extra(extras, label, value) when is_binary(value) do
    ["#{label}#{value}." | extras]
  end

  defp default_prompt("scan-bids") do
    "Read sources.json and seen.json. Scan every approved procurement source via " <>
      "browse.mjs. For matching opportunities, fetch detail and call save_bid with " <>
      "scoring fields. Skip URLs already in seen.json."
  end

  defp default_prompt("discover-targets") do
    "Read sources.json and seen.json. Hunt commercial targets through directories, " <>
      "job boards, partner networks, and trade publications. Call save_target for " <>
      "each qualifying company with fit_score and intent_score."
  end

  defp default_prompt("discover-sources") do
    "Read sources.json. Find new procurement portals to monitor. Call save_source " <>
      "for each new portal you confirm."
  end

  defp default_prompt(_), do: "Execute the assigned task."

  # ---------------------------------------------------------------------------
  # Source export
  # ---------------------------------------------------------------------------

  defp export_sources_json(deployment) do
    scope = deployment.source_scope || %{}

    sources =
      case GnomeGarden.Procurement.list_procurement_sources() do
        {:ok, list} -> list
        _ -> []
      end

    json =
      sources
      |> Enum.filter(&matches_scope?(&1, scope))
      |> Enum.map(&source_to_json/1)
      |> Jason.encode!(pretty: true)

    path = Path.join([File.cwd!(), "sidecar", @sources_filename])
    File.write!(path, json)
  end

  defp matches_scope?(source, scope) do
    region_ok =
      case scope["regions"] || scope[:regions] do
        nil -> true
        regions -> to_string(source.region) in Enum.map(regions, &to_string/1)
      end

    type_ok =
      case scope["source_types"] || scope[:source_types] do
        nil -> true
        types -> to_string(source.source_type) in Enum.map(types, &to_string/1)
      end

    region_ok and type_ok
  end

  defp source_to_json(s) do
    %{
      name: s.name,
      url: s.url,
      type: to_string(s.source_type),
      region: to_string(s.region),
      portal_id: s.portal_id,
      notes: s.notes
    }
  end
end
