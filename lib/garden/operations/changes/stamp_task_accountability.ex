defmodule GnomeGarden.Operations.Changes.StampTaskAccountability do
  @moduledoc """
  Stamps task accountability from the acting operator, server-side.

  Creator is set once at create time and is not client input; whoever changes
  the owner is recorded as the assigner. Actorless calls (agents, seeds) leave
  the fields nil rather than guessing.
  """

  use Ash.Resource.Change

  @impl true
  def change(changeset, _opts, context) do
    member_id = team_member_id(context.actor)

    changeset
    |> stamp_created_by(member_id)
    |> stamp_assigned_by(member_id)
  end

  defp stamp_created_by(changeset, nil), do: changeset

  defp stamp_created_by(%{action_type: :create} = changeset, member_id),
    do: Ash.Changeset.force_change_attribute(changeset, :created_by_team_member_id, member_id)

  defp stamp_created_by(changeset, _member_id), do: changeset

  # Any owner change rewrites the assigner — including actorless changes
  # (agents, background jobs), which must clear the previous human's stamp
  # rather than leave it stale.
  defp stamp_assigned_by(changeset, member_id) do
    case Ash.Changeset.fetch_change(changeset, :owner_team_member_id) do
      {:ok, nil} ->
        Ash.Changeset.force_change_attribute(changeset, :assigned_by_team_member_id, nil)

      {:ok, _owner_id} ->
        Ash.Changeset.force_change_attribute(changeset, :assigned_by_team_member_id, member_id)

      :error ->
        changeset
    end
  end

  defp team_member_id(nil), do: nil
  defp team_member_id(actor), do: GnomeGarden.Operations.current_team_member_id(actor)
end
