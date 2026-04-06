defmodule GnomeGarden.Sales.Changes.ValidateWorkflowTransition do
  @moduledoc """
  Validates that a stage transition is valid for the opportunity's workflow type.

  AshStateMachine enforces the superset of all valid transitions.
  This change module further restricts transitions to only those
  that belong to the opportunity's specific workflow path.
  """
  use Ash.Resource.Change

  @workflow_stages %{
    bid_response: [
      :discovery,
      :review,
      :qualification,
      :drafting,
      :submitted,
      :closed_won,
      :closed_lost
    ],
    outreach: [
      :discovery,
      :research,
      :outreach,
      :meeting,
      :qualification,
      :proposal,
      :negotiation,
      :closed_won,
      :closed_lost
    ],
    inbound: [
      :discovery,
      :qualification,
      :meeting,
      :proposal,
      :negotiation,
      :closed_won,
      :closed_lost
    ]
  }

  @impl true
  def change(changeset, _opts, _context) do
    workflow = Ash.Changeset.get_attribute(changeset, :workflow)
    action_name = changeset.action.name

    # If no workflow set, allow any transition (backwards compat)
    if workflow do
      valid_stages = Map.get(@workflow_stages, workflow, [])
      target = target_stage(action_name)

      if target && target not in valid_stages do
        Ash.Changeset.add_error(changeset,
          field: :stage,
          message: "stage %{stage} is not valid for the %{workflow} workflow",
          vars: %{stage: target, workflow: workflow}
        )
      else
        changeset
      end
    else
      changeset
    end
  end

  defp target_stage(:advance_to_review), do: :review
  defp target_stage(:advance_to_research), do: :research
  defp target_stage(:advance_to_qualification), do: :qualification
  defp target_stage(:advance_to_outreach), do: :outreach
  defp target_stage(:advance_to_meeting), do: :meeting
  defp target_stage(:advance_to_drafting), do: :drafting
  defp target_stage(:advance_to_proposal), do: :proposal
  defp target_stage(:advance_to_negotiation), do: :negotiation
  defp target_stage(:advance_to_submitted), do: :submitted
  defp target_stage(_), do: nil
end
