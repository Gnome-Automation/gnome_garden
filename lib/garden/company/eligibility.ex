defmodule GnomeGarden.Company.Eligibility do
  @moduledoc """
  Requirement-aware eligibility: matches a bid's explicit requirements
  against the active qualification snapshot and reports what is missing.

  Requirements use the shared gap vocabulary (bead gkc.4) and come only from
  operator-recorded `capability_gaps` on the bid. Free-text score notes are
  deliberately excluded: eligibility must never infer a hard gate from a
  keyword. Nothing here mutates scores or the profile.
  """

  alias GnomeGarden.Company.ProfileContext
  alias GnomeGarden.Company.CapabilityGap

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
  def requirements(bid), do: CapabilityGap.normalize(bid.capability_gaps)

  defp satisfied?(requirement, qualifications) do
    kinds = CapabilityGap.qualification_kinds(requirement)
    Enum.any?(qualifications, &(&1.kind in kinds))
  end
end
