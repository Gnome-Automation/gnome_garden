defmodule GnomeGarden.Procurement.Changes.InvalidateCredentialBrowserSessions do
  @moduledoc false
  use Ash.Resource.Change

  alias GnomeGarden.Procurement

  @impl true
  def change(changeset, opts, context) do
    mode = Keyword.get(opts, :mode, :expire)

    Ash.Changeset.after_action(changeset, fn _changeset, credential ->
      with {:ok, sessions} <-
             Procurement.list_source_browser_sessions_for_credential(credential.id,
               actor: context.actor,
               authorize?: false
             ),
           :ok <- invalidate(sessions, mode, context.actor) do
        {:ok, credential}
      end
    end)
  end

  defp invalidate(sessions, mode, actor) do
    sessions
    |> Enum.reject(&(&1.status in [:expired, :compromised, :disabled]))
    |> Enum.reduce_while(:ok, fn session, :ok ->
      result =
        case mode do
          :compromise ->
            Procurement.compromise_source_browser_session(
              session,
              %{last_failure_reason: "Credential was compromised."},
              actor: actor,
              authorize?: false
            )

          :expire ->
            Procurement.expire_source_browser_session(
              session,
              %{last_failure_reason: "Credential was rotated or disabled."},
              actor: actor,
              authorize?: false
            )
        end

      case result do
        {:ok, _session} -> {:cont, :ok}
        {:error, error} -> {:halt, {:error, error}}
      end
    end)
  end
end
