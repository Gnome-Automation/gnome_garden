defmodule GnomeGarden.Company.Changes.EncryptPaymentDestinationAccountNumber do
  @moduledoc false

  use Ash.Resource.Change

  alias GnomeGarden.SensitiveValueCrypto

  @scope "gnome_garden:finance_payment_destinations:v1"

  @impl true
  def change(changeset, _opts, _context) do
    changeset
    |> maybe_encrypt_account_number()
    |> validate_account_number_present()
  end

  defp maybe_encrypt_account_number(changeset) do
    case Ash.Changeset.get_argument(changeset, :account_number) do
      value when is_binary(value) ->
        value = String.trim(value)

        if value == "" do
          changeset
        else
          changeset
          |> Ash.Changeset.change_attribute(
            :encrypted_account_number,
            SensitiveValueCrypto.encrypt!(@scope, value)
          )
          |> Ash.Changeset.change_attribute(
            :account_number_fingerprint,
            SensitiveValueCrypto.fingerprint(value)
          )
          |> Ash.Changeset.change_attribute(
            :account_number_last4,
            SensitiveValueCrypto.last4(value)
          )
          |> Ash.Changeset.change_attribute(:account_number_present, true)
          |> Ash.Changeset.change_attribute(:last_rotated_at, DateTime.utc_now())
        end

      _ ->
        changeset
    end
  end

  defp validate_account_number_present(changeset) do
    account_number = Ash.Changeset.get_argument(changeset, :account_number)
    encrypted_account_number = Ash.Changeset.get_attribute(changeset, :encrypted_account_number)

    if blank?(account_number) and is_nil(encrypted_account_number) do
      Ash.Changeset.add_error(changeset, field: :account_number, message: "is required")
    else
      changeset
    end
  end

  defp blank?(value) when is_binary(value), do: String.trim(value) == ""
  defp blank?(_value), do: true
end
