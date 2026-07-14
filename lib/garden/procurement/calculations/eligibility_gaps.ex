defmodule GnomeGarden.Procurement.Calculations.EligibilityGaps do
  @moduledoc """
  Missing capability requirements for a bid, matched against Gnome's active
  qualification snapshot (one snapshot load per calculation batch).
  """

  use Ash.Resource.Calculation

  @impl true
  def load(_query, _opts, _context), do: [:capability_gaps, :score_risk_flags]

  @impl true
  def calculate(records, _opts, _context) do
    qualifications = GnomeGarden.Company.ProfileContext.active_qualifications()

    Enum.map(records, fn bid ->
      GnomeGarden.Company.Eligibility.assess(bid, qualifications).missing
    end)
  end
end
