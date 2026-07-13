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

    with {:ok, program} <- Acquisition.get_program(policy.program_id, actor: actor),
         :ok <- require_state(program.status == :active, "program must be active"),
         {:ok, source} <- Acquisition.get_source(policy.source_id, actor: actor),
         :ok <-
           require_state(
             source.enabled and source.status == :active,
             "source must be active and enabled"
           ) do
      changeset
    else
      {:error, error} ->
        Ash.Changeset.add_error(changeset,
          field: :status,
          message: error_message(error)
        )
    end
  end

  defp require_state(true, _message), do: :ok
  defp require_state(false, message), do: {:error, message}
  defp error_message(message) when is_binary(message), do: message
  defp error_message(error), do: Exception.message(Ash.Error.to_error_class(error))
end
