defmodule GnomeGarden.Calculations.AcquisitionFindingDisplaySummary do
  @moduledoc """
  Operator-facing fallback summary for acquisition findings.
  """

  use Ash.Resource.Calculation

  @impl true
  def load(_query, _opts, _context) do
    [:summary, :recommendation, :work_summary, :score_note, :work_note, :due_note]
  end

  @impl true
  def calculate(records, _opts, _context) do
    Enum.map(records, &display_summary/1)
  end

  defp display_summary(finding) do
    [
      text_value(finding.summary),
      text_value(finding.recommendation),
      text_value(finding.score_note),
      text_value(finding.work_note),
      text_value(finding.due_note),
      text_value(finding.work_summary),
      "Review the source record and linked evidence before deciding."
    ]
    |> Enum.find(&(&1 && &1 != ""))
  end

  defp text_value(value) when is_binary(value), do: String.trim(value)
  defp text_value(_value), do: nil
end
