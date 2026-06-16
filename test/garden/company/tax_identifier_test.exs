defmodule GnomeGarden.Company.TaxIdentifierTest do
  use GnomeGarden.DataCase

  alias GnomeGarden.Company
  alias GnomeGarden.Company.DefaultRegistration
  alias GnomeGarden.SensitiveValueCrypto

  @scope "gnome_garden:commercial_company_tax_identifiers:v1"

  setup do
    {:ok, profile} =
      Company.create_company_profile(%{
        key: "tax-test-#{System.unique_integer([:positive])}",
        name: "Gnome Automation",
        legal_name: "Gnome Automation LLC"
      })

    %{profile: profile}
  end

  test "stores tax identifier values encrypted with masked lookup fields", %{profile: profile} do
    assert {:ok, identifier} =
             Company.create_company_tax_identifier(%{
               company_profile_id: profile.id,
               identifier_type: :fein,
               jurisdiction: "US",
               label: "Federal Employer Identification Number",
               value: "12-3456789"
             })

    assert identifier.value_present
    assert identifier.value_last4 == "6789"
    assert identifier.encrypted_value["ciphertext"]
    refute inspect(identifier) =~ "12-3456789"
    assert SensitiveValueCrypto.decrypt!(@scope, identifier.encrypted_value) == "12-3456789"
  end

  test "default registration captures public company facts and optional FEIN" do
    result = DefaultRegistration.ensure_default(fein: "98-7654321")

    assert result.profile.key == "primary"

    assert get_in(result.profile.metadata, ["vendor_registration", "company", "legal_entity_name"]) ==
             "Gnome Automation LLC"

    assert [identifier] = result.tax_identifiers
    assert identifier.identifier_type == :fein
    assert identifier.value_last4 == "4321"

    second = DefaultRegistration.ensure_default(fein: "98-7654321")
    assert hd(second.tax_identifiers).id == identifier.id
  end
end
