defmodule GnomeGarden.Commercial.VendorOnboardingTest do
  use GnomeGarden.DataCase, async: false

  alias GnomeGarden.Company
  alias GnomeGarden.Operations

  test "imports vendor profile and PolyPeptide onboarding records idempotently" do
    payload = vendor_payload()

    assert {:ok, result} = Company.import_vendor_onboarding(payload, authorize?: false)
    assert result["customer_count"] == 1

    {:ok, profile} = Company.get_primary_company_profile(authorize?: false)
    {:ok, organization} = Operations.get_organization_by_name("PolyPeptide Laboratories Group")
    {:ok, people} = Operations.list_people_for_organization(organization.id, authorize?: false)
    {:ok, affiliations} = Operations.list_affiliations_for_organization(organization.id)
    {:ok, tasks} = Operations.list_tasks_by_organization(organization.id, authorize?: false)

    assert profile.metadata["vendor_registration"]["company"]["legal_entity_name"] ==
             "Gnome Automation LLC"

    assert profile.metadata["vendor_registration"]["banking"]["account"]["number"] ==
             "TEST-CHECKING-0001"

    assert organization.status == :active
    assert organization.relationship_roles == ["customer"]

    ap_contact = List.first(people)
    assert to_string(ap_contact.email) == "Accountspayable.torrance@polypeptide.com"

    ap_affiliation = List.first(affiliations)

    assert ap_affiliation.contact_roles == [
             "accounts_payable",
             "invoicing"
           ]

    task = List.first(tasks)
    assert task.title =~ "supplier code of conduct"
    assert task.priority == :high

    assert get_in(task.metadata, [
             "vendor_onboarding",
             "task_key"
           ]) == "supplier_code_of_conduct_confirmation_letter"

    assert {:ok, %{"customer_count" => 1}} =
             Company.import_vendor_onboarding(payload, authorize?: false)

    {:ok, profile} = Company.get_primary_company_profile(authorize?: false)
    {:ok, organization} = Operations.get_organization_by_name("PolyPeptide Laboratories Group")
    {:ok, tasks} = Operations.list_tasks_by_organization(organization.id, authorize?: false)
    {:ok, affiliations} = Operations.list_affiliations_for_organization(organization.id)

    assert profile.metadata["vendor_registration"]["customers"] == nil
    assert length(tasks) == 1
    assert length(affiliations) == 1
  end

  defp vendor_payload do
    %{
      "extracted_at" => "2026-06-11",
      "source" => "PolyPeptide vendor registration exercise + secure banking fixture",
      "company" => %{
        "legal_entity_name" => "Gnome Automation LLC",
        "entity_type" => "LLC (California)"
      },
      "banking" => %{
        "provider" => "Mercury (fintech layer)",
        "account" => %{
          "kind" => "checking",
          "number" => "TEST-CHECKING-0001"
        }
      },
      "customers" => [
        %{
          "name" => "PolyPeptide Laboratories Group",
          "description" => "Global CDMO for peptide- and oligonucleotide-based APIs",
          "location_engaged" => "Torrance, CA",
          "status" => %{
            "nda" => "executed",
            "vendor_banking_form" => "submitted 2026-06 (Net 60, DDP)",
            "supplier_code_of_conduct_letter" =>
              "OPEN - download from PolyPeptide Downloads page, sign, and return"
          },
          "accounts_payable_email" => "Accountspayable.torrance@polypeptide.com",
          "invoicing" => %{
            "format" => "PDF via email",
            "required_fields" => [
              "Invoice number",
              "Invoice date",
              "Due date",
              "Total amount",
              "Currency code (USD)"
            ]
          },
          "payment_terms" => "Net 60 (their stated minimum)"
        }
      ]
    }
  end
end
