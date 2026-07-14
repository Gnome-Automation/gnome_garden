defmodule GnomeGarden.Company.Eligibility do
  @moduledoc """
  Requirement-aware eligibility: matches a bid's explicit requirements
  against the active qualification snapshot and reports what is missing.

  Requirements use the shared gap vocabulary (bead gkc.4). They come from
  two explicit sources — operator-recorded `capability_gaps` on the bid and
  keyword-mapped scoring risk flags — and missing ones surface as
  eligibility gaps. Nothing here mutates scores or the profile; only a
  reviewed profile update changes semantic capability (see
  docs/company-growth-plan.md).
  """

  alias GnomeGarden.Company.ProfileContext

  # Which qualification kinds satisfy each requirement in the gap vocabulary.
  @requirement_kinds %{
    missing_certification: [:certification],
    bond_capacity: [:bonding],
    license_class: [:license],
    insurance_limit: [:insurance],
    tech_platform: [:partner_standing]
  }

  @risk_flag_requirements [
    {"bond", :bond_capacity},
    {"certif", :missing_certification},
    {"license", :license_class},
    {"insurance", :insurance_limit}
  ]

  @doc "Assess a bid against active qualifications; returns required/met/missing."
  def assess(bid, qualifications \\ nil) do
    qualifications = qualifications || ProfileContext.active_qualifications()
    required = requirements(bid)

    {met, missing} =
      Enum.split_with(required, fn requirement ->
        satisfied?(requirement, qualifications)
      end)

    %{required: required, met: met, missing: missing}
  end

  @doc "Explicit requirements derived from the bid's structured fields."
  def requirements(bid) do
    from_gaps = bid.capability_gaps || []

    from_flags =
      bid.score_risk_flags
      |> List.wrap()
      |> Enum.flat_map(fn flag ->
        flag = String.downcase(to_string(flag))

        @risk_flag_requirements
        |> Enum.filter(fn {needle, _requirement} -> String.contains?(flag, needle) end)
        |> Enum.map(fn {_needle, requirement} -> requirement end)
      end)

    Enum.uniq(from_gaps ++ from_flags)
  end

  defp satisfied?(requirement, qualifications) do
    kinds = Map.get(@requirement_kinds, requirement, [])
    Enum.any?(qualifications, &(&1.kind in kinds))
  end
end
