defmodule GnomeGarden.Agents.Tools.Commercial.SaveTargetAccountTest do
  use GnomeGarden.DataCase, async: true

  alias GnomeGarden.Agents
  alias GnomeGarden.Agents.TemplateCatalog
  alias GnomeGarden.Agents.Tools.Commercial.SaveTargetAccount
  alias GnomeGarden.Commercial
  alias GnomeGarden.Operations
  alias GnomeGarden.Support.IdentityNormalizer

  test "stores discovered target-account data in operations and commercial intake" do
    {:ok, result} =
      SaveTargetAccount.run(
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
    assert organization.website_domain == "northcoastpackaging.com"
    assert organization.relationship_roles == ["prospect"]

    assert {:ok, same_organization} =
             Operations.get_organization_by_website_domain("northcoastpackaging.com")

    assert same_organization.id == organization.id

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
    assert target_account.contact_person_id == person.id
    assert target_account.name == "North Coast Packaging"
    assert target_account.website_domain == "northcoastpackaging.com"
    assert target_account.fit_score >= 70
    assert target_account.intent_score >= 65
    assert metadata_value(target_account.metadata, :source) == "save_target_account"

    assert observation.target_account_id == target_account.id
    assert observation.source_channel in [:news_site, :agent_discovery]
    assert observation.source_url == "https://example.com/north-coast-packaging-expansion"
    assert observation.summary =~ "Hiring controls engineer"
    assert metadata_value(observation.metadata, :contact_person_id) == person.id
    assert metadata_value(observation.metadata, :industry) == "manufacturing"
    assert metadata_value(observation.metadata, :source) == "save_target_account"
  end

  test "attaches discovered records to a discovery program when provided" do
    {:ok, discovery_program} =
      Commercial.create_discovery_program(%{
        name: "Regional Beverage Hunt",
        target_regions: ["oc"],
        target_industries: ["food_bev"]
      })

    {:ok, result} =
      SaveTargetAccount.run(
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

  test "logs target-account outputs onto the originating agent run when run context is present" do
    _ = TemplateCatalog.sync_templates()
    {:ok, template} = Agents.get_agent_template_by_name("target_discovery")

    {:ok, deployment} =
      Agents.create_agent_deployment(%{
        name: "SaveTargetAccount Test Deployment #{System.unique_integer([:positive])}",
        visibility: :private,
        enabled: true,
        config: %{},
        source_scope: %{},
        agent_id: template.id
      })

    {:ok, run} =
      Agents.create_agent_run(%{
        agent_id: template.id,
        deployment_id: deployment.id,
        task: "Test target discovery run",
        run_kind: :manual
      })

    {:ok, result} =
      SaveTargetAccount.run(
        %{
          company_name: "West Basin Foods",
          company_description:
            "Regional food manufacturer with multiple batch lines and a modernization push.",
          industry: "food_bev",
          location: "Long Beach, CA",
          website: "https://westbasinfoods.example.com",
          signal: "Hiring controls engineer for batch line modernization",
          source_url: "https://example.com/west-basin-foods-controls-role"
        },
        %{tool_context: %{run_id: run.id}}
      )

    {:ok, outputs} = Agents.list_agent_run_outputs_for_run(run.id)
    output = Enum.find(outputs, &(&1.output_type == :target_account))

    assert output
    assert output.output_id == result.target_account_id
    assert output.event == :created
    assert output.label == "West Basin Foods"
    assert metadata_value(output.metadata, :target_observation_id) == result.target_observation_id
  end

  test "matches an existing organization by normalized company name" do
    {:ok, existing_organization} =
      Operations.create_organization(%{
        name: "North Coast Packaging, Inc.",
        status: :prospect,
        relationship_roles: ["prospect"]
      })

    {:ok, result} =
      SaveTargetAccount.run(
        %{
          company_name: "North Coast Packaging",
          company_description: "Packaging manufacturer adding controls-heavy production work.",
          location: "Anaheim, CA",
          signal: "Expansion and controls hiring signal"
        },
        %{}
      )

    {:ok, target_account} = Commercial.get_target_account(result.target_account_id)

    assert result.organization_id == existing_organization.id
    assert target_account.organization_id == existing_organization.id

    assert {:ok, [matched_organization]} =
             Operations.list_organizations_by_name_key(
               IdentityNormalizer.organization_name_key("North Coast Packaging")
             )

    assert matched_organization.id == existing_organization.id
  end

  test "matches an existing affiliated person by organization and normalized name" do
    {:ok, organization} =
      Operations.create_organization(%{
        name: "North Coast Packaging",
        status: :prospect,
        relationship_roles: ["prospect"],
        website: "https://northcoastpackaging.com"
      })

    {:ok, person} =
      Operations.create_person(%{
        first_name: "Maya",
        last_name: "Lopez",
        email: "m.lopez@northcoastpackaging.com"
      })

    {:ok, _affiliation} =
      Operations.create_organization_affiliation(%{
        organization_id: organization.id,
        person_id: person.id,
        title: "Controls Engineer",
        is_primary: true
      })

    {:ok, result} =
      SaveTargetAccount.run(
        %{
          company_name: "North Coast Packaging",
          company_description: "Packaging manufacturer expanding controls work.",
          website: "https://northcoastpackaging.com",
          signal: "Hiring controls engineer for expansion work",
          contact_first_name: "Maya",
          contact_last_name: "Lopez",
          contact_title: "Controls Engineer",
          contact_email: "maya.lopez@northcoastpackaging.com"
        },
        %{}
      )

    {:ok, target_account} = Commercial.get_target_account(result.target_account_id)

    assert result.person_id == person.id
    assert target_account.contact_person_id == person.id
  end

  defp metadata_value(metadata, key) do
    Map.get(metadata, key) || Map.get(metadata, to_string(key))
  end
end
