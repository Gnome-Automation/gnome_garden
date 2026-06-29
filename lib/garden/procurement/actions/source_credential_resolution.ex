defmodule GnomeGarden.Procurement.Actions.SourceCredentialResolution do
  @moduledoc false

  alias GnomeGarden.Procurement
  alias GnomeGarden.Procurement.BitwardenCredentialResolver
  alias GnomeGarden.Procurement.SourceCredentialCrypto

  def username_password(family, procurement_source_id) do
    with {:ok, family} <- require_family(family),
         {:ok, credential} <- resolve_credential(family, procurement_source_id),
         :ok <- ensure_username_password_verified(credential, family),
         {:ok, credentials} <- resolve_username_password(credential),
         :ok <- mark_used(credential) do
      {:ok, credentials}
    end
  end

  def api_key(family) do
    with {:ok, family} <- require_family(family),
         {:ok, credential} <- resolve_family_credential(family),
         :ok <- ensure_api_key_verified(credential, family),
         {:ok, api_key} <- decrypt_secret(credential.encrypted_api_key),
         :ok <- mark_used(credential) do
      {:ok, api_key}
    end
  end

  def status(family, procurement_source_id) do
    with {:ok, family} <- require_family(family) do
      case resolve_credential(family, procurement_source_id) do
        {:ok, credential} -> {:ok, stored_status(credential)}
        {:error, {:missing_credentials, _message}} -> {:ok, :missing}
      end
    end
  end

  def missing_credentials_message("planetbids") do
    "PlanetBids credentials are missing. Add source credentials in the database, or set #{Enum.join(GnomeGarden.Procurement.SourceCredentials.planetbids_env_names(), " and ")} as a fallback."
  end

  def missing_credentials_message("publicpurchase") do
    "PublicPurchase credentials are missing. Add source credentials in the database, or set #{Enum.join(GnomeGarden.Procurement.SourceCredentials.publicpurchase_env_names(), " and ")} as a fallback."
  end

  def missing_credentials_message("opengov") do
    "OpenGov credentials are missing. Add source credentials in the database."
  end

  def missing_credentials_message("bidnet") do
    "BidNet credentials are missing. Add source credentials in the database."
  end

  def missing_credentials_message("sam_gov") do
    "SAM.gov API key is missing. Add a source credential in the database, or set #{Enum.join(GnomeGarden.Procurement.SourceCredentials.sam_gov_env_names(), " and ")} as a fallback."
  end

  def missing_credentials_message(_family), do: "Required source credentials are missing."

  def credential_family_label("planetbids"), do: "PlanetBids"
  def credential_family_label("publicpurchase"), do: "PublicPurchase"
  def credential_family_label("opengov"), do: "OpenGov"
  def credential_family_label("bidnet"), do: "BidNet"
  def credential_family_label("sam_gov"), do: "SAM.gov"
  def credential_family_label(_family), do: "Source"

  def family_string(family) when is_atom(family), do: Atom.to_string(family)
  def family_string(family) when is_binary(family), do: String.trim(family)
  def family_string(_family), do: nil

  defp resolve_credential(family, procurement_source_id) when is_binary(procurement_source_id) do
    case Procurement.list_source_credentials_for_source(procurement_source_id, authorize?: false) do
      {:ok, [credential | _]} -> {:ok, credential}
      _ -> resolve_family_credential(family)
    end
  end

  defp resolve_credential(family, _procurement_source_id), do: resolve_family_credential(family)

  defp resolve_family_credential(family) do
    case Procurement.list_source_credentials_for_family(family, authorize?: false) do
      {:ok, [credential | _]} -> {:ok, credential}
      _ -> {:error, {:missing_credentials, missing_credentials_message(family)}}
    end
  end

  defp ensure_username_password_verified(credential, family) do
    case stored_status(credential) do
      :verified ->
        if username_password_reference_present?(credential) do
          :ok
        else
          {:error, "#{credential_family_label(family)} credentials are incomplete."}
        end

      :invalid ->
        {:error, invalid_credentials_message(credential, family)}

      _pending_or_missing ->
        {:error, pending_credentials_message(family)}
    end
  end

  defp ensure_api_key_verified(credential, family) do
    case stored_status(credential) do
      :verified ->
        if is_map(credential.encrypted_api_key) do
          :ok
        else
          {:error, "#{credential_family_label(family)} API key is incomplete."}
        end

      :invalid ->
        {:error, invalid_credentials_message(credential, family)}

      _pending_or_missing ->
        {:error, pending_credentials_message(family)}
    end
  end

  defp stored_status(%{status: :invalid}), do: :invalid
  defp stored_status(%{test_status: :invalid}), do: :invalid

  defp stored_status(%{test_status: test_status})
       when test_status in [:queued, :testing, :untested],
       do: :pending

  defp stored_status(%{
         credential_storage: :bitwarden,
         test_status: test_status,
         bitwarden_item_id: item_id,
         bitwarden_item_name: item_name
       })
       when test_status in [:verified, :manual_required] do
    if present?(item_id) or present?(item_name), do: :verified, else: :pending
  end

  defp stored_status(%{test_status: test_status, encrypted_api_key: payload})
       when test_status in [:verified, :manual_required] and is_map(payload),
       do: decryptable_status(payload)

  defp stored_status(%{test_status: test_status, encrypted_password: payload, username: username})
       when test_status in [:verified, :manual_required] and is_map(payload) do
    if present?(username), do: decryptable_status(payload), else: :pending
  end

  defp stored_status(_credential), do: :pending

  defp decryptable_status(payload) do
    case decrypt_secret(payload) do
      {:ok, _secret} -> :verified
      {:error, _reason} -> :invalid
    end
  end

  defp decrypt_secret(payload) when is_map(payload) do
    {:ok, SourceCredentialCrypto.decrypt_secret!(payload)}
  rescue
    error -> {:error, Exception.message(error)}
  end

  defp resolve_username_password(%{credential_storage: :bitwarden} = credential) do
    BitwardenCredentialResolver.username_password(credential)
  end

  defp resolve_username_password(%{username: username, encrypted_password: payload} = credential)
       when is_binary(username) and is_map(payload) do
    with {:ok, password} <- decrypt_secret(payload) do
      {:ok, %{username: username, password: password, credential_id: credential.id}}
    end
  end

  defp resolve_username_password(_credential),
    do: {:error, "Username and password are required."}

  defp username_password_reference_present?(%{credential_storage: :bitwarden} = credential) do
    present?(credential.bitwarden_item_id) or present?(credential.bitwarden_item_name)
  end

  defp username_password_reference_present?(credential) do
    present?(credential.username) and is_map(credential.encrypted_password)
  end

  defp mark_used(credential) do
    case Procurement.mark_source_credential_used(credential, %{}, authorize?: false) do
      {:ok, _credential} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp invalid_credentials_message(%{last_failure_reason: reason}, family)
       when is_binary(reason) and reason != "" do
    "#{credential_family_label(family)} credentials are invalid: #{reason}"
  end

  defp invalid_credentials_message(_credential, family) do
    "#{credential_family_label(family)} credentials are invalid. Update credentials and test again."
  end

  defp pending_credentials_message(family) do
    "#{credential_family_label(family)} credentials are saved, but verification is still pending."
  end

  defp require_family(family) do
    case family_string(family) do
      family when is_binary(family) and family != "" -> {:ok, family}
      _ -> {:error, "Credential family is required."}
    end
  end

  defp present?(value) when is_binary(value), do: String.trim(value) != ""
  defp present?(_value), do: false
end
