defmodule GnomeGarden.Acquisition.PromotionRules do
  @moduledoc false

  import GnomeGarden.Acquisition.RuleChecks, only: [blank?: 1, maybe_block: 3]

  @procurement_promotion_document_types [:solicitation, :scope, :pricing, :addendum]

  @required_load [
    :status,
    :summary,
    :source_url,
    :work_summary,
    :location,
    :due_at,
    :promotion_document_count,
    :signal_id,
    :finding_family,
    :source_discovery_record_id,
    source_discovery_record: [:discovery_evidence_count]
  ]

  def required_load, do: @required_load
  def procurement_promotion_document_types, do: @procurement_promotion_document_types

  def substantive_procurement_document_type?(document_type),
    do: document_type in @procurement_promotion_document_types

  def ready?(finding), do: blockers(finding) == []

  def blockers(finding) do
    []
    |> maybe_block(finding.status != :accepted, "Accept the finding before promoting it.")
    |> maybe_block(not is_nil(finding.signal_id), "Finding already has a linked signal.")
    |> maybe_block(blank?(finding.summary), "Add a summary before promotion.")
    |> maybe_block(blank?(finding.source_url), "Add a source URL before promotion.")
    |> maybe_block(blank?(finding.work_summary), "Add a work summary before promotion.")
    |> family_blockers(finding)
  end

  defp family_blockers(blockers, %{finding_family: :procurement} = finding) do
    blockers
    |> maybe_block(is_nil(finding.due_at), "Capture a due date before promotion.")
    |> maybe_block(blank?(finding.location), "Capture a location before promotion.")
    |> maybe_block(
      promotion_document_count(finding) < 1,
      "Attach a substantive procurement packet (solicitation, scope, pricing, or addendum) before promotion."
    )
  end

  defp family_blockers(blockers, %{finding_family: :discovery, source_discovery_record_id: nil}) do
    blockers
  end

  defp family_blockers(blockers, %{finding_family: :discovery} = finding) do
    evidence_count = discovery_evidence_count(finding)

    maybe_block(
      blockers,
      evidence_count < 1,
      "Add at least one piece of discovery evidence before promotion."
    )
  end

  defp family_blockers(blockers, _finding), do: blockers

  defp discovery_evidence_count(%{source_discovery_record: %{discovery_evidence_count: count}})
       when is_integer(count),
       do: count

  defp discovery_evidence_count(_finding), do: 0

  defp promotion_document_count(%{promotion_document_count: count}) when is_integer(count),
    do: count

  defp promotion_document_count(_finding), do: 0
end
