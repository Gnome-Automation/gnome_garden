defmodule GnomeGarden.Company.PaymentDestinationTest do
  use GnomeGarden.DataCase

  alias GnomeGarden.Company
  alias GnomeGarden.Company.DefaultPaymentDestinations
  alias GnomeGarden.SensitiveValueCrypto

  @scope "gnome_garden:finance_payment_destinations:v1"

  test "stores payment destination account numbers encrypted with masked lookup fields" do
    assert {:ok, destination} =
             Company.create_payment_destination(%{
               key: "test-checking-#{System.unique_integer([:positive])}",
               label: "Test Checking",
               provider: :bank,
               account_kind: :checking,
               beneficiary_name: "Gnome Automation LLC",
               beneficiary_address: %{"city" => "Sacramento"},
               bank_name: "Column N.A.",
               bank_address: %{"city" => "San Francisco"},
               domestic_routing_number: "121145433",
               wire_routing_number: "121145433",
               currency_code: "USD",
               account_number: "000111222333444"
             })

    assert destination.account_number_present
    assert destination.account_number_last4 == "3444"
    assert destination.encrypted_account_number["ciphertext"]
    refute inspect(destination) =~ "000111222333444"

    assert SensitiveValueCrypto.decrypt!(@scope, destination.encrypted_account_number) ==
             "000111222333444"
  end

  test "default Mercury checking destination is idempotent when account number is supplied" do
    [first] =
      DefaultPaymentDestinations.ensure_defaults(
        mercury_checking_account_number: "999888777666555"
      )

    [second] =
      DefaultPaymentDestinations.ensure_defaults(
        mercury_checking_account_number: "999888777666555"
      )

    assert first.id == second.id
    assert first.key == "gnome_mercury_checking"
    assert first.provider == :mercury
    assert first.bank_name == "Column N.A."
    assert first.account_number_last4 == "6555"
  end
end
