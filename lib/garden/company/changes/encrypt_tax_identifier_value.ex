defmodule GnomeGarden.Company.Changes.EncryptTaxIdentifierValue do
  @moduledoc false

  use Ash.Resource.Change

  alias GnomeGarden.SensitiveValueCrypto

  @scope "gnome_garden:commercial_company_tax_identifiers:v1"

  @impl true
  def change(changeset, _opts, _context) do
    changeset
    |> maybe_encrypt_value()
    |> validate_value_present()
  end

  defp maybe_encrypt_value(changeset) do
    case Ash.Changeset.get_argument(changeset, :value) do
      value when is_binary(value) ->
        value = String.trim(value)

        if value == "" do
          changeset
        else
          changeset
          |> Ash.Changeset.change_attribute(
            :encrypted_value,
            SensitiveValueCrypto.encrypt!(@scope, value)
          )
          |> Ash.Changeset.change_attribute(
            :value_fingerprint,
            SensitiveValueCrypto.fingerprint(value)
          )
          |> Ash.Changeset.change_attribute(:value_last4, SensitiveValueCrypto.last4(value))
          |> Ash.Changeset.change_attribute(:value_present, true)
          |> Ash.Changeset.change_attribute(:last_rotated_at, DateTime.utc_now())
        end

      _ ->
        changeset
    end
  end

  defp validate_value_present(changeset) do
    value = Ash.Changeset.get_argument(changeset, :value)
    encrypted_value = Ash.Changeset.get_attribute(changeset, :encrypted_value)

    if blank?(value) and is_nil(encrypted_value) do
      Ash.Changeset.add_error(changeset, field: :value, message: "is required")
    else
      changeset
    end
  end

  defp blank?(value) when is_binary(value), do: String.trim(value) == ""
  defp blank?(_value), do: true
end
