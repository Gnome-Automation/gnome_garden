defmodule GnomeGarden.Automation.Validations.ValidDefinition do
  @moduledoc """
  Validates rule trigger, criteria, and actions at write time, so a
  malformed definition can never reach evaluation. Publishing additionally
  verifies that referenced playbooks exist and are active.
  """

  use Ash.Resource.Validation

  alias GnomeGarden.Automation.Criteria
  alias GnomeGarden.Automation.RuleActions
  alias GnomeGarden.Automation.Triggers
  alias GnomeGarden.Operations

  @impl true
  def validate(changeset, _opts, _context) do
    with :ok <- validate_trigger(changeset),
         :ok <- validate_criteria(Ash.Changeset.get_attribute(changeset, :criteria)),
         :ok <- validate_actions(changeset) do
      validate_playbook_references(changeset)
    end
  end

  defp validate_trigger(changeset) do
    resource = Ash.Changeset.get_attribute(changeset, :trigger_resource)
    action = Ash.Changeset.get_attribute(changeset, :trigger_action)

    if Triggers.known?(resource, action) do
      :ok
    else
      {:error,
       field: :trigger_action,
       message: "must be one of the instrumented triggers: #{Triggers.describe()}"}
    end
  end

  defp validate_criteria(criteria) do
    if Criteria.valid?(criteria) do
      :ok
    else
      {:error,
       field: :criteria,
       message:
         "must be a list of %{field, op, value} maps with op in: #{Enum.join(Criteria.ops(), ", ")}"}
    end
  end

  # Drafts may be saved without actions; publishing requires at least one.
  defp validate_actions(changeset) do
    actions = Ash.Changeset.get_attribute(changeset, :actions)
    status = Ash.Changeset.get_attribute(changeset, :status)

    cond do
      actions == [] and status == :draft ->
        :ok

      RuleActions.valid?(actions) ->
        :ok

      true ->
        {:error,
         field: :actions,
         message:
           "must be a non-empty list of typed actions (#{Enum.join(RuleActions.types(), ", ")}) " <>
             "with valid params"}
    end
  end

  # A rule may only go live when every playbook it references exists and is
  # active; drafts may reference playbooks that are still being written.
  defp validate_playbook_references(changeset) do
    if Ash.Changeset.get_attribute(changeset, :status) == :published do
      changeset
      |> Ash.Changeset.get_attribute(:actions)
      |> Enum.filter(&(&1["type"] == "apply_playbook"))
      |> Enum.reduce_while(:ok, fn action, :ok ->
        case Operations.get_playbook_by_name(action["playbook_name"], authorize?: false) do
          {:ok, %{status: :active}} ->
            {:cont, :ok}

          {:ok, _archived} ->
            {:halt,
             {:error,
              field: :actions, message: "playbook #{inspect(action["playbook_name"])} is archived"}}

          {:error, _not_found} ->
            {:halt,
             {:error,
              field: :actions,
              message: "playbook #{inspect(action["playbook_name"])} does not exist"}}
        end
      end)
    else
      :ok
    end
  end
end
