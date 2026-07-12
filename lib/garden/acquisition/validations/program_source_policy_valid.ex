defmodule GnomeGarden.Acquisition.Validations.ProgramSourcePolicyValid do
  @moduledoc false

  use Ash.Resource.Validation

  @impl true
  def validate(changeset, _opts, _context) do
    with :ok <- require_queries(Ash.Changeset.get_attribute(changeset, :query_templates)),
         :ok <- require_positive_money(changeset, :spend_limit_per_run),
         :ok <- require_positive_money(changeset, :spend_limit_per_day) do
      :ok
    end
  end

  defp require_queries([_ | _] = templates) do
    if Enum.all?(templates, &safe_query_template?/1) do
      :ok
    else
      {:error,
       field: :query_templates,
       message: "must be bounded text without credentials or executable code"}
    end
  end

  defp require_queries(_templates),
    do: {:error, field: :query_templates, message: "must not be empty"}

  defp safe_query_template?(template) when is_binary(template) do
    trimmed = String.trim(template)

    trimmed != "" and String.length(trimmed) <= 500 and
      not String.match?(
        trimmed,
        ~r/(api[_-]?key|password|bearer\s+|<script|\b(import|eval|exec)\s*\()/i
      )
  end

  defp safe_query_template?(_template), do: false

  defp require_positive_money(changeset, field) do
    case Ash.Changeset.get_attribute(changeset, field) do
      %Money{amount: amount} ->
        if Decimal.positive?(amount),
          do: :ok,
          else: {:error, field: field, message: "must be positive"}

      _value ->
        {:error, field: field, message: "must be positive"}
    end
  end
end
