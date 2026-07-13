defmodule GnomeGarden.Acquisition.Actions.BackfillProgramSources do
  @moduledoc false
  use Ash.Resource.Actions.Implementation
  require Logger

  alias GnomeGarden.Acquisition

  @impl true
  def run(_input, _opts, context) do
    actor = context.actor

    with {:ok, exa_source} <- ensure_exa_source(actor),
         {:ok, programs} <- Acquisition.list_programs(actor: actor, load: [:discovery_program]),
         {:ok, discovery_count} <- backfill_discovery_programs(programs, exa_source, actor),
         {:ok, findings} <- Acquisition.list_findings(actor: actor),
         {:ok, finding_result} <- backfill_finding_pairs(findings, actor) do
      {:ok,
       %{
         exa_source_id: exa_source.id,
         discovery_program_sources: discovery_count,
         finding_pairs: finding_result.pairs,
         findings_linked: finding_result.linked,
         unresolved_findings: finding_result.unresolved,
         activated: 0
       }}
    end
  end

  defp ensure_exa_source(actor) do
    Acquisition.create_source(
      %{
        external_ref: "provider:exa:search",
        name: "Exa Search",
        url: "https://api.exa.ai/search",
        source_family: :discovery,
        source_kind: :directory,
        status: :active,
        enabled: true,
        scan_strategy: :deterministic,
        description: "Bounded Exa company-search capability."
      },
      actor: actor,
      upsert?: true,
      upsert_identity: :unique_external_ref,
      upsert_fields: [:name, :url, :description]
    )
  end

  defp backfill_discovery_programs(programs, source, actor) do
    programs
    |> Enum.filter(&(&1.program_family == :discovery and loaded?(&1.discovery_program)))
    |> Enum.reduce_while({:ok, 0}, fn program, {:ok, count} ->
      attrs = discovery_policy_attrs(program, source)

      case Acquisition.create_program_source(attrs, actor: actor) do
        {:ok, _policy} -> {:cont, {:ok, count + 1}}
        {:error, error} -> {:halt, {:error, error}}
      end
    end)
  end

  defp backfill_finding_pairs(findings, actor) do
    findings
    |> Enum.filter(&(is_binary(&1.program_id) and is_binary(&1.source_id)))
    |> Enum.reduce_while({:ok, %{pairs: 0, linked: 0, unresolved: 0}}, fn finding, {:ok, acc} ->
      attrs = %{
        program_id: finding.program_id,
        source_id: finding.source_id,
        metadata: %{"backfill_origin" => "finding_pair"}
      }

      with {:ok, policy} <- Acquisition.create_program_source(attrs, actor: actor),
           {:ok, _finding} <-
             Acquisition.update_finding(finding, %{program_source_id: policy.id}, actor: actor) do
        {:cont, {:ok, %{acc | pairs: acc.pairs + 1, linked: acc.linked + 1}}}
      else
        {:error, error} ->
          Logger.warning(
            "Unable to backfill ProgramSource for finding #{finding.id}: #{inspect(error)}"
          )

          {:cont, {:ok, %{acc | unresolved: acc.unresolved + 1}}}
      end
    end)
  end

  defp discovery_policy_attrs(program, source) do
    discovery = program.discovery_program

    templates =
      Enum.uniq(discovery.search_terms ++ discovery.target_industries ++ discovery.target_regions)

    %{
      program_id: program.id,
      source_id: source.id,
      query_templates: templates,
      cadence_minutes: discovery.cadence_hours * 60,
      max_queries_per_run: 8,
      max_results_per_query: 8,
      spend_limit_per_run: Money.new!(:USD, "0.25"),
      spend_limit_per_day: Money.new!(:USD, "10.00"),
      enrichment_policy: :verify_promotable,
      max_enrichments_per_run: 5,
      finding_limit_per_run: 5,
      finding_limit_per_day: 25,
      metadata: %{
        "backfill_origin" => "commercial_discovery_program",
        "commercial_discovery_program_id" => discovery.id,
        "legacy_scope_snapshot" => program.scope
      }
    }
  end

  defp loaded?(%Ash.NotLoaded{}), do: false
  defp loaded?(nil), do: false
  defp loaded?(_record), do: true
end
