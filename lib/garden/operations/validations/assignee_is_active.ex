defmodule GnomeGarden.Operations.Validations.AssigneeIsActive do
  @moduledoc """
  Rejects task assignment to a team member that is not active.

  Only runs when `owner_team_member_id` is being changed; clearing the owner
  (unassigned triage state) is always allowed.
  """

  use Ash.Resource.Validation

  @impl true
  def validate(changeset, _opts, _context) do
    case Ash.Changeset.fetch_change(changeset, :owner_team_member_id) do
      {:ok, nil} ->
        :ok

      {:ok, team_member_id} ->
        validate_active(team_member_id)

      :error ->
        :ok
    end
  end

  defp validate_active(team_member_id) do
    case Ash.get(GnomeGarden.Operations.TeamMember, team_member_id, authorize?: false) do
      {:ok, %{status: :active}} ->
        :ok

      {:ok, _inactive} ->
        {:error, field: :owner_team_member_id, message: "must be an active team member"}

      {:error, _error} ->
        {:error, field: :owner_team_member_id, message: "must be an existing team member"}
    end
  end
end
