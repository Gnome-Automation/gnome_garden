defmodule GnomeGarden.Company.Validations.QualificationDetails do
  @moduledoc """
  Kind-specific validation for qualification details — validated maps now,
  embedded typed resources when the vocabulary grows (the same recorded
  right-sizing call as automation rule definitions).

  Unknown detail keys are rejected so `details` cannot become a metadata
  catch-all.
  """

  use Ash.Resource.Validation

  @allowed %{
    registration: ~w(portal renewal_frequency account_email),
    license: ~w(classification qualifier bond_on_file),
    certification: ~w(program level eligibility_basis),
    insurance: ~w(carrier policy_number per_occurrence_limit aggregate_limit),
    bonding: ~w(surety broker single_project_limit aggregate_limit letter_on_file),
    partner_standing: ~w(program tier requirements_url)
  }

  @impl true
  def validate(changeset, _opts, _context) do
    kind = Ash.Changeset.get_attribute(changeset, :kind)
    details = Ash.Changeset.get_attribute(changeset, :details) || %{}
    allowed = Map.get(@allowed, kind, [])

    cond do
      not is_map(details) or Enum.any?(Map.keys(details), &(not is_binary(&1))) ->
        {:error, field: :details, message: "must be a map with string keys"}

      (unknown = Map.keys(details) -- allowed) != [] ->
        {:error,
         field: :details,
         message:
           "unknown keys for #{kind}: #{Enum.join(unknown, ", ")} (allowed: #{Enum.join(allowed, ", ")})"}

      kind == :bonding and not limits_present?(details) ->
        {:error,
         field: :details, message: "bonding requires single_project_limit and aggregate_limit"}

      true ->
        :ok
    end
  end

  defp limits_present?(details),
    do: filled?(details["single_project_limit"]) and filled?(details["aggregate_limit"])

  defp filled?(value), do: is_binary(value) and String.trim(value) != ""
end
