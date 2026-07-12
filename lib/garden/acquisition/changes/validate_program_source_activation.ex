defmodule GnomeGarden.Acquisition.Changes.ValidateProgramSourceActivation do
  @moduledoc false
  use Ash.Resource.Change

  alias GnomeGarden.Acquisition

  @impl true
  def change(changeset, _opts, context) do
    Ash.Changeset.before_action(changeset, fn changeset -> validate(changeset, context.actor) end)
  end

  defp validate(changeset, actor) do
    policy = changeset.data

    with :ok <- require_queries(policy),
         :ok <- require_positive_money(policy.spend_limit_per_run, :spend_limit_per_run),
         :ok <- require_positive_money(policy.spend_limit_per_day, :spend_limit_per_day),
         {:ok, program} <- Acquisition.get_program(policy.program_id, actor: actor),
         :ok <- require_state(program.status == :active, "program must be active"),
         {:ok, source} <- Acquisition.get_source(policy.source_id, actor: actor),
         :ok <-
           require_state(
             source.enabled and source.status == :active,
             "source must be active and enabled"
           ) do
      changeset
    else
      {:error, error} -> Ash.Changeset.add_error(changeset, error)
    end
  end

  defp require_queries(%{query_templates: [_ | _] = templates}) do
    if Enum.all?(templates, &safe_query_template?/1) do
      :ok
    else
      {:error, "query templates must be bounded text without credentials or executable code"}
    end
  end

  defp require_queries(_policy), do: {:error, "query templates must not be empty"}

  defp safe_query_template?(template) when is_binary(template) do
    trimmed = String.trim(template)

    trimmed != "" and String.length(trimmed) <= 500 and
      not String.match?(
        trimmed,
        ~r/(api[_-]?key|password|bearer\s+|<script|\b(import|eval|exec)\s*\()/i
      )
  end

  defp safe_query_template?(_template), do: false

  defp require_positive_money(%Money{amount: amount}, field) do
    if Decimal.positive?(amount), do: :ok, else: {:error, "#{field} must be positive"}
  end

  defp require_positive_money(_value, field), do: {:error, "#{field} must be positive"}
  defp require_state(true, _message), do: :ok
  defp require_state(false, message), do: {:error, message}
end
