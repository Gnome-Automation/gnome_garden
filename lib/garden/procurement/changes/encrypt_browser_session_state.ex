defmodule GnomeGarden.Procurement.Changes.EncryptBrowserSessionState do
  @moduledoc false
  use Ash.Resource.Change

  alias GnomeGarden.Procurement
  alias GnomeGarden.Procurement.BrowserSessionCrypto

  @impl true
  def change(changeset, _opts, context), do: encrypt(changeset, context.actor)

  defp encrypt(changeset, actor) do
    storage_state = Ash.Changeset.get_argument(changeset, :storage_state)
    source_id = Ash.Changeset.get_attribute(changeset, :procurement_source_id)
    credential_id = Ash.Changeset.get_attribute(changeset, :source_credential_id)

    with {:ok, canonical_state} <- canonical_storage_state(storage_state),
         true <- is_binary(source_id) and is_binary(credential_id),
         {:ok, %{status: :active} = credential} <-
           Procurement.get_source_credential(credential_id,
             actor: actor,
             authorize?: false
           ),
         true <-
           is_nil(credential.procurement_source_id) or
             credential.procurement_source_id == source_id do
      changeset
      |> Ash.Changeset.change_attribute(
        :encrypted_storage_state,
        BrowserSessionCrypto.encrypt!(source_id, credential_id, canonical_state)
      )
      |> Ash.Changeset.change_attribute(
        :storage_state_fingerprint,
        BrowserSessionCrypto.fingerprint(canonical_state)
      )
      |> Ash.Changeset.change_attribute(
        :credential_fingerprint,
        BrowserSessionCrypto.credential_fingerprint(credential)
      )
    else
      {:error, :invalid_storage_state} ->
        Ash.Changeset.add_error(changeset,
          field: :storage_state,
          message: "must be a JSON object"
        )

      _invalid_binding ->
        Ash.Changeset.add_error(changeset,
          field: :source_credential_id,
          message: "must identify an active credential for this source"
        )
    end
  end

  defp canonical_storage_state(value) when is_binary(value) do
    case Jason.decode(value) do
      {:ok, %{} = state} -> {:ok, Jason.encode!(state)}
      _invalid -> {:error, :invalid_storage_state}
    end
  end

  defp canonical_storage_state(_value), do: {:error, :invalid_storage_state}
end
