defmodule GnomeGarden.Company.RegistrationFactsTest do
  use GnomeGarden.DataCase

  alias GnomeGarden.Company.RegistrationFacts
  alias GnomeGarden.Company.DefaultRegistration
  alias GnomeGarden.Company.DefaultPaymentDestinations

  test "returns masked vendor-registration facts by default and revealed values only on request" do
    DefaultRegistration.ensure_default(fein: "98-7654321")
    DefaultPaymentDestinations.ensure_defaults(mercury_checking_account_number: "999888777666555")

    assert {:ok, masked} = RegistrationFacts.resolve()
    assert masked.company.legal_entity_name == "Gnome Automation LLC"
    assert masked.tax_identifiers.fein_us.value_last4 == "4321"
    assert is_nil(masked.tax_identifiers.fein_us.value)
    assert masked.payment_destination.account_number_last4 == "6555"
    assert is_nil(masked.payment_destination.account_number)

    assert {:ok, revealed} = RegistrationFacts.resolve(reveal_sensitive?: true)
    assert revealed.tax_identifiers.fein_us.value == "98-7654321"
    assert revealed.payment_destination.account_number == "999888777666555"
  end
end
