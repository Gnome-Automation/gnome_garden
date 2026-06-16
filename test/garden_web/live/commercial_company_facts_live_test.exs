defmodule GnomeGardenWeb.CommercialCompanyFactsLiveTest do
  use GnomeGardenWeb.ConnCase

  setup :register_and_log_in_user

  import Phoenix.LiveViewTest

  alias GnomeGarden.Company.RegistrationFacts
  alias GnomeGarden.Company.DefaultRegistration
  alias GnomeGarden.Company.DefaultPaymentDestinations

  test "renders editable company facts with sensitive values masked until revealed", %{conn: conn} do
    DefaultRegistration.ensure_default(fein: "98-7654321")
    DefaultPaymentDestinations.ensure_defaults(mercury_checking_account_number: "999888777666555")

    {:ok, view, html} = live(conn, ~p"/company/facts")

    assert html =~ "Company Profile"
    assert html =~ "Reusable Registration Profile"
    assert html =~ "People &amp; Contacts"
    assert html =~ "Documents"
    assert html =~ "Source Review"
    assert html =~ "Gnome Automation LLC"
    assert html =~ "Members"
    assert html =~ "Bassam Hammoud"
    assert html =~ "Patrick Curran"
    assert html =~ "Stored ending 4321"
    assert html =~ "Stored ending 6555"
    refute html =~ "98-7654321"
    refute html =~ "999888777666555"

    html =
      view
      |> element("button", "Reveal Sensitive")
      |> render_click()

    assert html =~ "98-7654321"
    assert html =~ "999888777666555"
  end

  test "saves company, tax identifier, and payment destination edits", %{conn: conn} do
    DefaultRegistration.ensure_default(fein: "98-7654321")
    DefaultPaymentDestinations.ensure_defaults(mercury_checking_account_number: "999888777666555")

    {:ok, view, _html} = live(conn, ~p"/company/facts")

    view
    |> form("#company-facts-form", %{
      "company" => %{
        "legal_name" => "Gnome Automation LLC",
        "telephone" => "(555) 123-4567",
        "order_email" => "orders@example.com",
        "purchasing_email" => "buy@example.com",
        "finance_email" => "finance@example.com",
        "member_0_key" => "bassam_hammoud",
        "member_0_name" => "Bassam Hammoud",
        "member_0_title" => "Co-Founder",
        "member_0_phone" => "(555) 111-2222",
        "member_0_email" => "bhammoud@gnomeautomation.com",
        "member_1_key" => "patrick_curran",
        "member_1_name" => "Patrick Curran",
        "member_1_title" => "Co-Founder",
        "member_1_phone" => "970-556-4676",
        "member_1_email" => "pc@gnomeautomation.com",
        "vendor_contact_member_key" => "bassam_hammoud",
        "vendor_contact_phone" => "(555) 111-2222",
        "vendor_contact_email" => "bhammoud@gnomeautomation.com",
        "address_street" => "2108 N Street, Ste N",
        "address_city" => "Sacramento",
        "address_state" => "CA",
        "address_postal_code" => "95816",
        "country" => "United States of America",
        "delivery_terms" => "DDP",
        "payment_terms" => "Net 45",
        "currency" => "USD"
      }
    })
    |> render_submit()

    view
    |> form("#tax-identifier-form", %{
      "tax_identifier" => %{
        "label" => "Federal Employer Identification Number",
        "value" => "11-2222333",
        "notes" => "Updated from company facts screen."
      }
    })
    |> render_submit()

    view
    |> form("#payment-destination-form", %{
      "payment_destination" => %{
        "label" => "Gnome Mercury Checking",
        "beneficiary_name" => "Gnome Automation LLC",
        "bank_name" => "Column N.A.",
        "account_number" => "444555666777888",
        "domestic_routing_number" => "121145433",
        "wire_routing_number" => "121145433",
        "alternate_routing_number" => "121145307",
        "swift_bic" => "CLNOUS66MER",
        "intermediary_swift_bic" => "CHASUS33XXX",
        "currency_code" => "USD",
        "bank_street" => "1 Letterman Drive, Building A, Suite A4-700",
        "bank_city" => "San Francisco",
        "bank_state" => "CA",
        "bank_postal_code" => "94129"
      }
    })
    |> render_submit()

    assert {:ok, facts} = RegistrationFacts.resolve(reveal_sensitive?: true)
    assert facts.company.telephone == "(555) 123-4567"
    assert Enum.map(facts.company.members, & &1["name"]) == ["Bassam Hammoud", "Patrick Curran"]
    assert facts.company.vendor_contact["member_key"] == "bassam_hammoud"
    assert facts.company.vendor_contact["name"] == "Bassam Hammoud"
    assert facts.standard_terms["payment_terms"]["default_answer"] == "Net 45"
    assert facts.tax_identifiers.fein_us.value == "11-2222333"
    assert facts.payment_destination.account_number == "444555666777888"
  end

  test "legacy commercial company facts route still renders", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/commercial/company-facts")

    assert html =~ "Company Profile"
  end
end
