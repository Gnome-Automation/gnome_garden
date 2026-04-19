defmodule GnomeGarden.Agents.Workers.Sales.TargetDiscoveryTest do
  use GnomeGarden.DataCase, async: true

  alias GnomeGarden.Commercial
  alias GnomeGarden.Operations
  alias GnomeGarden.Agents.Workers.Sales.TargetDiscovery

  test "create_leads_from_result routes parsed agent output through SaveLead" do
    result_text =
      "LEAD: Apex Beverage Systems | food_bev | Anaheim, CA | Hiring PLC programmer for line expansion | Maya Lopez | Controls Manager | https://example.com/jobs/apex"

    assert [{:ok, result}] = TargetDiscovery.create_leads_from_result(result_text)

    {:ok, organization} = Operations.get_organization(result.organization_id)
    {:ok, target_account} = Commercial.get_target_account(result.target_account_id)
    {:ok, observation} = Commercial.get_target_observation(result.target_observation_id)

    assert organization.name == "Apex Beverage Systems"
    assert organization.status == :prospect
    assert target_account.organization_id == organization.id
    assert target_account.name == "Apex Beverage Systems"
    assert observation.target_account_id == target_account.id
    assert observation.summary =~ "Hiring PLC programmer"
  end

  test "create_leads_from_result threads discovery_program_id through save_lead" do
    {:ok, discovery_program} =
      Commercial.create_discovery_program(%{
        name: "Packaging Target Sweep",
        target_regions: ["oc"],
        target_industries: ["packaging"]
      })

    result_text =
      "LEAD: Boxline Packaging | packaging | Anaheim, CA | Hiring automation technician for conveyor upgrade | Alex Kim | Ops Director | https://example.com/jobs/boxline"

    assert [{:ok, result}] =
             TargetDiscovery.create_leads_from_result(
               result_text,
               discovery_program_id: discovery_program.id
             )

    {:ok, target_account} = Commercial.get_target_account(result.target_account_id)
    {:ok, observation} = Commercial.get_target_observation(result.target_observation_id)

    assert target_account.discovery_program_id == discovery_program.id
    assert observation.discovery_program_id == discovery_program.id
  end
end
