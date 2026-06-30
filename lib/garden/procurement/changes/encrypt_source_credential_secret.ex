defmodule GnomeGarden.Procurement.Changes.EncryptSourceCredentialSecret do
  @moduledoc false

  use Ash.Resource.Change

  alias GnomeGarden.Procurement.SourceCredentialCrypto

  @impl true
  def change(changeset, _opts, _context) do
    changeset
    |> maybe_encrypt(:password, :encrypted_password, :password_fingerprint, :password_present)
    |> maybe_encrypt(:api_key, :encrypted_api_key, :api_key_fingerprint, :api_key_present)
    |> validate_secret_present()
  end

  defp maybe_encrypt(
         changeset,
         argument,
         encrypted_attribute,
         fingerprint_attribute,
         present_attribute
       ) do
    case Ash.Changeset.get_argument(changeset, argument) do
      value when is_binary(value) ->
        value = String.trim(value)

        if value == "" do
          changeset
        else
          changeset
          |> Ash.Changeset.change_attribute(
            encrypted_attribute,
            SourceCredentialCrypto.encrypt_secret!(value)
          )
          |> Ash.Changeset.change_attribute(
            fingerprint_attribute,
            SourceCredentialCrypto.secret_fingerprint(value)
          )
          |> Ash.Changeset.change_attribute(present_attribute, true)
          |> Ash.Changeset.change_attribute(:last_rotated_at, DateTime.utc_now())
        end

      _ ->
        changeset
    end
  end

  defp validate_secret_present(changeset) do
    credential_storage = attribute_value(changeset, :credential_storage)
    provider = Ash.Changeset.get_attribute(changeset, :provider)
    password = Ash.Changeset.get_argument(changeset, :password)
    api_key = Ash.Changeset.get_argument(changeset, :api_key)

    cond do
      credential_storage == :bitwarden ->
        validate_bitwarden_reference_present(changeset)

      provider == :sam_gov and blank?(api_key) ->
        Ash.Changeset.add_error(changeset, field: :api_key, message: "is required")

      provider != :sam_gov and blank?(password) ->
        Ash.Changeset.add_error(changeset, field: :password, message: "is required")

      true ->
        changeset
    end
  end

  defp validate_bitwarden_reference_present(changeset) do
    item_id = attribute_value(changeset, :bitwarden_item_id)
    item_name = attribute_value(changeset, :bitwarden_item_name)

    if blank?(item_id) and blank?(item_name) do
      Ash.Changeset.add_error(changeset,
        field: :bitwarden_item_name,
        message: "or item ID is required"
      )
    else
      changeset
    end
  end

  defp attribute_value(changeset, attribute) do
    Map.get(changeset.params, attribute) ||
      Map.get(changeset.params, Atom.to_string(attribute)) ||
      Ash.Changeset.get_attribute(changeset, attribute)
  end

  defp blank?(value) when is_binary(value), do: String.trim(value) == ""
  defp blank?(_value), do: true
end
