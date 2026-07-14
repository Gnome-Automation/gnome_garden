defmodule GnomeGarden.Procurement.Validations.SourceGovernanceReady do
  @moduledoc false

  use Ash.Resource.Validation

  @impl true
  def validate(changeset, _opts, _context) do
    if Ash.Changeset.get_attribute(changeset, :portfolio_decision) == :adopt do
      validate_adoption(changeset)
    else
      :ok
    end
  end

  defp validate_adoption(changeset) do
    required = [
      {:expected_coverage, Ash.Changeset.get_attribute(changeset, :expected_coverage)},
      {:adapter_owner, Ash.Changeset.get_attribute(changeset, :adapter_owner)},
      {:allowed_retrieval_paths, Ash.Changeset.get_attribute(changeset, :allowed_retrieval_paths)}
    ]

    case Enum.find(required, fn {_field, value} -> blank?(value) end) do
      {field, _value} ->
        {:error, field: field, message: "is required before adopting a source"}

      nil ->
        validate_compliance(changeset)
    end
  end

  defp validate_compliance(changeset) do
    cond do
      Ash.Changeset.get_attribute(changeset, :compliance_decision) != :adopt ->
        {:error,
         field: :compliance_decision,
         message: "must be adopt before source automation can be adopted"}

      Ash.Changeset.get_attribute(changeset, :source_type) == :sam_gov and
          blank?(Ash.Changeset.get_attribute(changeset, :rate_limit_per_day)) ->
        {:error,
         field: :rate_limit_per_day,
         message: "must record the SAM.gov account-specific daily request limit"}

      true ->
        :ok
    end
  end

  defp blank?(nil), do: true
  defp blank?(""), do: true
  defp blank?([]), do: true
  defp blank?(_value), do: false
end
