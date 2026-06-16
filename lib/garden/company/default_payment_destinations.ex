defmodule GnomeGarden.Company.DefaultPaymentDestinations do
  @moduledoc """
  Idempotent bootstrap for company-owned payment destinations.
  """

  alias GnomeGarden.Company

  @mercury_checking %{
    key: "gnome_mercury_checking",
    label: "Gnome Mercury Checking",
    provider: :mercury,
    status: :active,
    account_kind: :checking,
    beneficiary_name: "Gnome Automation LLC",
    beneficiary_address: %{
      "street" => "2108 N Street, Ste N",
      "city" => "Sacramento",
      "state" => "CA",
      "postal_code" => "95816",
      "country" => "US"
    },
    bank_name: "Column N.A.",
    bank_address: %{
      "street" => "1 Letterman Drive, Building A, Suite A4-700",
      "city" => "San Francisco",
      "state" => "CA",
      "postal_code" => "94129",
      "country" => "US"
    },
    domestic_routing_number: "121145433",
    wire_routing_number: "121145433",
    alternate_routing_number: "121145307",
    swift_bic: "CLNOUS66MER",
    intermediary_swift_bic: "CHASUS33XXX",
    currency_code: "USD",
    notes:
      "Mercury checking account wire/ACH details for vendor onboarding and customer payment setup.",
    metadata: %{
      "source" => "Mercury wire details",
      "banking_partner" => "Column N.A.",
      "captured_on" => "2026-06-13",
      "mt103" => %{
        "account_with_institution" => "57D",
        "intermediary_institution" => "56A",
        "recipient" => "59"
      }
    }
  }

  @spec ensure_defaults(keyword()) :: [GnomeGarden.Company.PaymentDestination.t()]
  def ensure_defaults(opts \\ []) do
    case Keyword.get(opts, :mercury_checking_account_number) ||
           System.get_env("GNOME_MERCURY_CHECKING_ACCOUNT_NUMBER") do
      value when is_binary(value) and value != "" ->
        [ensure_mercury_checking(value)]

      _ ->
        []
    end
  end

  @spec ensure_mercury_checking(String.t()) :: GnomeGarden.Company.PaymentDestination.t()
  def ensure_mercury_checking(account_number) when is_binary(account_number) do
    attrs = Map.put(@mercury_checking, :account_number, account_number)

    case Company.get_payment_destination_by_key(@mercury_checking.key) do
      {:ok, destination} ->
        {:ok, destination} =
          Company.update_payment_destination(
            destination,
            Map.drop(attrs, [:key, :account_number])
          )

        destination

      {:error, _reason} ->
        {:ok, destination} = Company.create_payment_destination(attrs)
        destination
    end
  end
end
