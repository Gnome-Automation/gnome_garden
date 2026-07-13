defmodule GnomeGarden.Procurement.Actions.ResolveBrowserSessionState do
  @moduledoc false
  use Ash.Resource.Actions.Implementation

  alias GnomeGarden.Procurement
  alias GnomeGarden.Procurement.BrowserSessionCrypto

  @impl true
  def run(input, _opts, context) do
    session_id = Ash.ActionInput.get_argument(input, :session_id)
    source_id = Ash.ActionInput.get_argument(input, :procurement_source_id)
    credential_id = Ash.ActionInput.get_argument(input, :source_credential_id)

    with {:ok, session} <-
           Procurement.get_source_browser_session(session_id, actor: context.actor),
         :ok <- validate_session(session, source_id, credential_id),
         {:ok, credential} <-
           Procurement.get_source_credential(credential_id,
             actor: context.actor,
             authorize?: false
           ),
         :ok <- validate_credential(session, credential) do
      decrypt(session)
    end
  end

  defp validate_session(%{status: :valid} = session, source_id, credential_id) do
    cond do
      session.procurement_source_id != source_id ->
        {:error, :browser_session_source_mismatch}

      session.source_credential_id != credential_id ->
        {:error, :browser_session_credential_mismatch}

      expired?(session.expires_at) ->
        {:error, :browser_session_expired}

      not is_map(session.encrypted_storage_state) ->
        {:error, :browser_session_state_missing}

      true ->
        :ok
    end
  end

  defp validate_session(%{status: status}, _source_id, _credential_id),
    do: {:error, {:browser_session_unavailable, status}}

  defp validate_credential(session, %{status: :active} = credential) do
    if session.credential_fingerprint == BrowserSessionCrypto.credential_fingerprint(credential) do
      :ok
    else
      {:error, :browser_session_credential_rotated}
    end
  end

  defp validate_credential(_session, credential),
    do: {:error, {:browser_session_credential_unavailable, credential.status}}

  defp decrypt(session) do
    {:ok,
     BrowserSessionCrypto.decrypt!(
       session.procurement_source_id,
       session.source_credential_id,
       session.encrypted_storage_state
     )}
  rescue
    _error -> {:error, :browser_session_state_invalid}
  end

  defp expired?(nil), do: true
  defp expired?(expires_at), do: DateTime.compare(expires_at, DateTime.utc_now()) != :gt
end
