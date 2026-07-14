defmodule GnomeGarden.Company.Changes.StampInitiativeActors do
  @moduledoc """
  Stamps initiative accountability from the acting operator, server-side.

  Creates record who captured the idea (or evidence); decision transitions
  (achieve/decline) record who decided. Actorless calls leave the fields nil
  rather than guessing — but note that initiatives are operator-driven by
  design; agents reach them only through the recommendation gate.
  """

  use Ash.Resource.Change

  @impl true
  def change(changeset, _opts, context) do
    case GnomeGarden.Operations.current_team_member_id(context.actor) do
      nil ->
        changeset

      member_id ->
        stamp(changeset, member_id)
    end
  end

  defp stamp(%{action_type: :create} = changeset, member_id) do
    if has_attribute?(changeset, :created_by_team_member_id) do
      Ash.Changeset.force_change_attribute(changeset, :created_by_team_member_id, member_id)
    else
      changeset
    end
  end

  defp stamp(%{action: %{name: name}} = changeset, member_id)
       when name in [:achieve, :decline] do
    Ash.Changeset.force_change_attribute(changeset, :decided_by_team_member_id, member_id)
  end

  defp stamp(changeset, _member_id), do: changeset

  defp has_attribute?(changeset, name),
    do: Ash.Resource.Info.attribute(changeset.resource, name) != nil
end
