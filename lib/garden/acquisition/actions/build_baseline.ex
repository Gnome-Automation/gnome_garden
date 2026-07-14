defmodule GnomeGarden.Acquisition.Actions.BuildBaseline do
  @moduledoc """
  Builds a read-only acquisition maturity and yield baseline through domain
  code interfaces.
  """

  use Ash.Resource.Actions.Implementation

  alias GnomeGarden.Acquisition
  alias GnomeGarden.Acquisition.FailureTaxonomy
  alias GnomeGarden.Commercial.DiscoveryPipeline

  @impl true
  def run(_input, _opts, context) do
    read_opts = [actor: context.actor]

    with {:ok, sources} <- Acquisition.list_console_sources(read_opts),
         {:ok, programs} <- Acquisition.list_console_programs(read_opts),
         {:ok, findings} <- Acquisition.list_findings(read_opts),
         {:ok, decisions} <- Acquisition.list_finding_review_decisions(read_opts),
         {:ok, preview_runs} <- Acquisition.list_lead_preview_runs(read_opts) do
      {:ok, build_report(sources, programs, findings, decisions, preview_runs)}
    end
  end

  defp build_report(sources, programs, findings, decisions, preview_runs) do
    procurement_sources = Enum.filter(sources, &(&1.source_family == :procurement))
    discovery_programs = Enum.filter(programs, &(&1.program_family == :discovery))
    discovery_findings = Enum.filter(findings, &(&1.finding_family == :discovery))
    execution_profile = DiscoveryPipeline.execution_profile()

    %{
      schema_version: 2,
      generated_at: DateTime.utc_now() |> DateTime.truncate(:second),
      maturity: %{
        procurement: %{
          execution_mode: :live_source_scanning,
          source_count: length(procurement_sources),
          sources_with_runs: Enum.count(procurement_sources, &present?(&1.last_run_at)),
          scan_strategy_counts: frequencies(procurement_sources, & &1.scan_strategy),
          provider_counts: frequencies(procurement_sources, &provider_type/1),
          last_scan_totals: scan_totals(procurement_sources)
        },
        commercial_discovery: %{
          execution: execution_profile,
          program_count: length(discovery_programs),
          programs_with_runs: Enum.count(discovery_programs, &present?(&1.last_run_at)),
          finding_count: length(discovery_findings),
          scheduled_live_search_run_count:
            Enum.count(preview_runs, &present?(&1.discovery_program_id))
        }
      },
      sources: %{
        total: length(sources),
        by_family: frequencies(sources, & &1.source_family),
        by_health: frequencies(sources, & &1.health_status),
        by_status: frequencies(sources, & &1.status),
        finding_totals: sum_source_findings(sources)
      },
      programs: %{
        total: length(programs),
        by_family: frequencies(programs, & &1.program_family),
        by_health: frequencies(programs, & &1.health_status),
        by_status: frequencies(programs, & &1.status)
      },
      findings: %{
        total: length(findings),
        by_family: frequencies(findings, & &1.finding_family),
        by_status: frequencies(findings, & &1.status),
        rejection_reasons: rejection_reasons(decisions)
      },
      exa: %{
        preview_run_count: length(preview_runs),
        by_status: frequencies(preview_runs, & &1.status),
        query_count: sum(preview_runs, & &1.query_count),
        candidate_count: sum(preview_runs, & &1.candidate_count),
        promotable_count: sum(preview_runs, & &1.promotable_count),
        suppressed_count: sum(preview_runs, & &1.suppressed_count),
        total_cost:
          Enum.reduce(
            preview_runs,
            Decimal.new(0),
            &Decimal.add(&2, &1.total_cost || Decimal.new(0))
          )
      },
      failures: %{
        categories: FailureTaxonomy.categories(),
        counts: failure_counts(sources)
      }
    }
  end

  defp frequencies(records, value_fun) do
    records
    |> Enum.map(value_fun)
    |> Enum.reject(&is_nil/1)
    |> Enum.frequencies()
  end

  defp sum(records, value_fun), do: Enum.reduce(records, 0, &((value_fun.(&1) || 0) + &2))

  defp sum_source_findings(sources) do
    %{
      total: sum(sources, & &1.finding_count),
      review: sum(sources, & &1.review_finding_count),
      accepted: sum(sources, & &1.accepted_finding_count),
      parked: sum(sources, & &1.parked_finding_count),
      rejected: sum(sources, & &1.rejected_finding_count),
      promoted: sum(sources, & &1.promoted_finding_count),
      noise: sum(sources, & &1.noise_finding_count)
    }
  end

  defp scan_totals(sources) do
    Enum.reduce(sources, %{extracted: 0, scored: 0, saved: 0}, fn source, totals ->
      summary = metadata_value(source.metadata, "last_scan_summary") || %{}

      %{
        extracted: totals.extracted + metadata_integer(summary, "extracted"),
        scored: totals.scored + metadata_integer(summary, "scored"),
        saved: totals.saved + metadata_integer(summary, "saved")
      }
    end)
  end

  defp failure_counts(sources) do
    sources
    |> Enum.map(&FailureTaxonomy.classify/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.frequencies()
  end

  defp rejection_reasons(decisions) do
    decisions
    |> Enum.filter(&(&1.decision in [:rejected, :suppressed, :parked]))
    |> Enum.map(&(&1.reason_code || "uncategorized"))
    |> Enum.frequencies()
  end

  defp provider_type(%{procurement_source: %Ash.NotLoaded{}}), do: nil
  defp provider_type(%{procurement_source: nil}), do: nil
  defp provider_type(%{procurement_source: source}), do: source.source_type

  defp metadata_value(metadata, key) when is_map(metadata) do
    Map.get(metadata, key) || existing_atom_value(metadata, key)
  end

  defp metadata_value(_metadata, _key), do: nil

  defp existing_atom_value(metadata, key) when is_binary(key) do
    Map.get(metadata, String.to_existing_atom(key))
  rescue
    ArgumentError -> nil
  end

  defp existing_atom_value(_metadata, _key), do: nil

  defp metadata_integer(metadata, key) do
    case metadata_value(metadata, key) do
      value when is_integer(value) -> value
      value when is_binary(value) -> parse_integer(value)
      _ -> 0
    end
  end

  defp parse_integer(value) do
    case Integer.parse(value) do
      {parsed, ""} -> parsed
      _ -> 0
    end
  end

  defp present?(nil), do: false
  defp present?(_value), do: true
end
