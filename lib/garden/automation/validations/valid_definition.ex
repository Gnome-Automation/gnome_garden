defmodule GnomeGarden.Automation.Validations.ValidDefinition do
  @moduledoc """
  Validates rule criteria and actions shape at write time, so a malformed
  definition can never reach evaluation.
  """

  use Ash.Resource.Validation

  alias GnomeGarden.Automation.Criteria
  alias GnomeGarden.Automation.RuleActions

  @impl true
  def validate(changeset, _opts, _context) do
    with :ok <- validate_criteria(Ash.Changeset.get_attribute(changeset, :criteria)),
         :ok <- validate_actions(changeset) do
      :ok
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
             "with their required params"}
    end
  end
end
