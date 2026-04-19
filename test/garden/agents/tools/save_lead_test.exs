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
    {:ok, target_account} = Commercial.get_target_account(result.target_account_id)
    {:ok, observation} = Commercial.get_target_observation(result.target_observation_id)

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

    assert target_account.organization_id == organization.id
    assert target_account.name == "North Coast Packaging"
    assert target_account.website_domain == "northcoastpackaging.com"
    assert target_account.fit_score >= 70
    assert target_account.intent_score >= 65
    assert metadata_value(target_account.metadata, :contact_person_id) == person.id
    assert metadata_value(target_account.metadata, :source) == "save_lead"

    assert observation.target_account_id == target_account.id
    assert observation.source_channel in [:news_site, :agent_discovery]
    assert observation.source_url == "https://example.com/north-coast-packaging-expansion"
    assert observation.summary =~ "Hiring controls engineer"
    assert metadata_value(observation.metadata, :contact_person_id) == person.id
    assert metadata_value(observation.metadata, :industry) == "manufacturing"
    assert metadata_value(observation.metadata, :source) == "save_lead"
  end

  test "attaches discovered records to a discovery program when provided" do
    {:ok, discovery_program} =
      Commercial.create_discovery_program(%{
        name: "Regional Beverage Hunt",
        target_regions: ["oc"],
        target_industries: ["food_bev"]
      })

    {:ok, result} =
      SaveLead.run(
        %{
          company_name: "Coastal Canning",
          discovery_program_id: discovery_program.id,
          company_description:
            "Regional beverage co-packer adding a second canning line and looking for controls help.",
          industry: "food_bev",
          location: "Costa Mesa, CA",
          website: "https://coastalcanning.example.com",
          signal: "Expansion and hiring signal on the new canning line",
          source_url: "https://example.com/coastal-canning-expansion"
        },
        %{}
      )

    {:ok, target_account} = Commercial.get_target_account(result.target_account_id)
    {:ok, observation} = Commercial.get_target_observation(result.target_observation_id)

    assert target_account.discovery_program_id == discovery_program.id
    assert observation.discovery_program_id == discovery_program.id
    assert metadata_value(target_account.metadata, :discovery_program_id) == discovery_program.id
    assert metadata_value(observation.metadata, :discovery_program_id) == discovery_program.id
  end

  defp metadata_value(metadata, key) do
    Map.get(metadata, key) || Map.get(metadata, to_string(key))
  end
end
