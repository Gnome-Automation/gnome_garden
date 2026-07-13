defmodule GnomeGarden.Procurement.BrowserSessionCrypto do
  @moduledoc false

  alias GnomeGarden.SensitiveValueCrypto

  def encrypt!(source_id, credential_id, storage_state) do
    SensitiveValueCrypto.encrypt!(scope(source_id, credential_id), storage_state)
  end

  def decrypt!(source_id, credential_id, encrypted_storage_state) do
    SensitiveValueCrypto.decrypt!(scope(source_id, credential_id), encrypted_storage_state)
  end

  def fingerprint(storage_state), do: SensitiveValueCrypto.fingerprint(storage_state)

  def credential_fingerprint(credential) do
    credential.password_fingerprint ||
      credential.api_key_fingerprint ||
      SensitiveValueCrypto.fingerprint(
        Enum.join(
          [
            credential.credential_storage,
            credential.bitwarden_item_id,
            credential.bitwarden_item_name,
            credential.username,
            credential.last_rotated_at
          ]
          |> Enum.map(&to_string(&1 || "")),
          ":"
        )
      )
  end

  defp scope(source_id, credential_id),
    do: "gnome_garden:procurement_browser_session:v1:#{source_id}:#{credential_id}"
end
