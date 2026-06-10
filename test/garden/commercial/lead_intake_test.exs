defmodule GnomeGarden.Commercial.LeadIntakeTest do
  use GnomeGarden.DataCase, async: true

  alias GnomeGarden.Commercial
  alias GnomeGarden.Operations

  describe "create_referral_lead/2" do
    test "creates organization, sites, contacts, affiliations, signal, and follow-up task through Ash actions" do
      attrs = %{
        organization: %{
          name: "PolyPeptide Laboratories",
          legal_name: "PolyPeptide Laboratories Inc.",
          website: "https://polypeptide.com",
          primary_region: "CA",
          notes: "Hot referral lead. NDA recently signed."
        },
        sites: [
          %{
            name: "Torrance",
            address1: "365 Maple Avenue",
            city: "Torrance",
            state: "CA",
            postal_code: "90503",
            country_code: "US"
          }
        ],
        contacts: [
          %{
            first_name: "Julian",
            last_name: "Ingram-Palmer",
            email: "julian.ingrampalmer@polypeptide.com",
            phone: "(310) 806-8442",
            title: "Global Process Design Engineer",
            contact_roles: ["referrer", "technical_stakeholder"],
            is_primary: true
          },
          %{
            first_name: "Moo",
            last_name: "Thongsrisook",
            email: "Moo.Thongsrisook@polypeptide.com",
            phone: "+1 310 782-3569",
            mobile: "+1 310 951-6844",
            title: "Indirect Procurement Specialist",
            contact_roles: ["procurement"]
          }
        ],
        signal: %{
          title: "PolyPeptide referral after NDA",
          description:
            "Referral lead for controls, automation, validation, and plant-floor systems work.",
          source_url: "https://polypeptide.com",
          external_ref: "manual_referral:polypeptide:test",
          referral_source: "Julian Ingram-Palmer",
          notes: "NDA signed with Moo Thongsrisook."
        },
        task: %{
          title: "Follow up on PolyPeptide NDA/referral lead",
          description:
            "Confirm next step with Moo and Julian and identify active controls scope.",
          task_type: :call,
          priority: :urgent
        }
      }

      assert {:ok, result} = Commercial.create_referral_lead(attrs)

      assert result.organization.name == "PolyPeptide Laboratories"
      assert result.organization.status == :prospect
      assert result.organization.website_domain == "polypeptide.com"
      assert length(result.sites) == 1
      assert length(result.contacts) == 2
      assert length(result.affiliations) == 2

      assert result.signal.title == "PolyPeptide referral after NDA"
      assert result.signal.signal_type == :referral
      assert result.signal.source_channel == :referral
      assert result.signal.organization_id == result.organization.id
      assert result.signal.metadata["referral_source"] == "Julian Ingram-Palmer"

      assert result.task.title == "Follow up on PolyPeptide NDA/referral lead"
      assert result.task.origin_domain == :commercial
      assert result.task.origin_resource == "signal"
      assert result.task.signal_id == result.signal.id
      assert result.task.organization_id == result.organization.id

      assert {:ok, loaded_signal} = Commercial.get_signal(result.signal.id)
      assert loaded_signal.organization_id == result.organization.id

      assert {:ok, people} = Operations.list_people_for_organization(result.organization.id)

      assert Enum.map(people, &to_string(&1.email)) |> Enum.sort() ==
               [
                 "Moo.Thongsrisook@polypeptide.com",
                 "julian.ingrampalmer@polypeptide.com"
               ]
               |> Enum.sort()

      assert {:ok, rerun} = Commercial.create_referral_lead(attrs)
      assert rerun.signal.id == result.signal.id
    end
  end
end
