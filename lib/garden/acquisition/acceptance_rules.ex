defmodule GnomeGarden.Acquisition.AcceptanceRules do
  @moduledoc false

  import GnomeGarden.Acquisition.RuleChecks, only: [blank?: 1, maybe_block: 3]

  @required_load [
    :summary,
    :source_url,
    :work_summary,
    :finding_family,
    :source_discovery_record_id,
    source_discovery_record: [:discovery_evidence_count]
  ]

  def required_load, do: @required_load

  def ready?(finding), do: blockers(finding) == []

  def blockers(finding) do
    []
    |> maybe_block(blank?(finding.summary), "Add a summary before accepting.")
    |> maybe_block(blank?(finding.source_url), "Add a source URL before accepting.")
    |> maybe_block(blank?(finding.work_summary), "Add a work summary before accepting.")
    |> family_blockers(finding)
  end

  defp family_blockers(blockers, %{finding_family: :discovery, source_discovery_record_id: nil}) do
    blockers
  end

  defp family_blockers(blockers, %{finding_family: :discovery} = finding) do
    evidence_count = discovery_evidence_count(finding)

    maybe_block(
      blockers,
      evidence_count < 1,
      "Add at least one piece of discovery evidence before accepting."
    )
  end

  defp family_blockers(blockers, _finding), do: blockers

  defp discovery_evidence_count(%{source_discovery_record: %{discovery_evidence_count: count}})
       when is_integer(count),
       do: count

  defp discovery_evidence_count(_finding), do: 0
end
