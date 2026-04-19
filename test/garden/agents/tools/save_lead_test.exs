defmodule GnomeGarden.Agents.Tools.SaveLeadTest do
  use GnomeGarden.DataCase, async: true

  alias GnomeGarden.Agents.Tools.SaveLead
  alias GnomeGarden.Commercial
  alias GnomeGarden.Operations

  test "stores discovered lead data in operations and commercial intake" do
    {:ok, result} =
      SaveLead.run(
        %{
          company_name: "North Coast Packaging",
          company_description:
            "Food packaging manufacturer running multiple lines with aging controls and reporting gaps.",
          industry: "manufacturing",
          location: "Anaheim, CA",
          website: "northcoastpackaging.com",
          signal:
            "Hiring controls engineer after opening a second packaging line and posting a modernization initiative.",
          employee_count: 130,
          contact_first_name: "Maya",
          contact_last_name: "Lopez",
          contact_title: "Controls Engineer",
          contact_email: "maya@northcoastpackaging.com",
          contact_phone: "555-0100",
          source_url: "https://example.com/north-coast-packaging-expansion"
        },
        %{}
      )

    {:ok, organization} = Operations.get_organization(result.organization_id)
    {:ok, person} = Operations.get_person(result.person_id)
    {:ok, signal} = Commercial.get_signal(result.signal_id)

    assert organization.name == "North Coast Packaging"
    assert organization.status == :prospect
    assert organization.website == "https://northcoastpackaging.com"
    assert organization.relationship_roles == ["prospect"]

    assert person.first_name == "Maya"
    assert person.last_name == "Lopez"
    assert to_string(person.email) == "maya@northcoastpackaging.com"
    assert person.phone == "555-0100"

    assert {:ok, [affiliation]} =
             Operations.list_affiliations_for_organization(organization.id)

    assert affiliation.person_id == person.id
    assert affiliation.title == "Controls Engineer"
    assert affiliation.contact_roles == ["technical_contact"]
    assert affiliation.is_primary

    assert signal.organization_id == organization.id
    assert String.starts_with?(signal.title, "North Coast Packaging — Hiring controls engineer")
    assert String.length(signal.title) <= 120
    assert signal.signal_type == :outbound_target
    assert signal.source_channel == :agent_discovery
    assert signal.source_url == "https://example.com/north-coast-packaging-expansion"
    assert signal.notes =~ "Hiring controls engineer"
    assert metadata_value(signal.metadata, :contact_person_id) == person.id
    assert metadata_value(signal.metadata, :industry) == "manufacturing"
    assert metadata_value(signal.metadata, :source) == "save_lead"
  end

  defp metadata_value(metadata, key) do
    Map.get(metadata, key) || Map.get(metadata, to_string(key))
  end
end
