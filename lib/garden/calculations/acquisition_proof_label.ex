defmodule GnomeGarden.Calculations.AcquisitionProofLabel do
  @moduledoc """
  Presentation-facing proof summary for acquisition findings.
  """

  use Ash.Resource.Calculation

  @impl true
  def load(_query, _opts, _context) do
    [:finding_family, :document_count, :discovery_evidence_count]
  end

  @impl true
  def calculate(records, _opts, _context) do
    Enum.map(records, &proof_label/1)
  end

  defp proof_label(%{finding_family: :discovery} = finding) do
    "#{document_count(finding)} docs · #{discovery_evidence_count(finding)} evidence"
  end

  defp proof_label(finding), do: "#{document_count(finding)} documents"

  defp document_count(%{document_count: count}) when is_integer(count), do: count
  defp document_count(_finding), do: 0

  defp discovery_evidence_count(%{discovery_evidence_count: count}) when is_integer(count),
    do: count

  defp discovery_evidence_count(_finding), do: 0
end
