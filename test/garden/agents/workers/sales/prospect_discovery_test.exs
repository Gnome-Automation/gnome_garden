defmodule GnomeGarden.Agents.Workers.Sales.ProspectDiscoveryTest do
  use GnomeGarden.DataCase, async: true

  alias GnomeGarden.Commercial
  alias GnomeGarden.Operations
  alias GnomeGarden.Agents.Workers.Sales.ProspectDiscovery

  test "create_leads_from_result routes parsed agent output through SaveLead" do
    result_text =
      "LEAD: Apex Beverage Systems | food_bev | Anaheim, CA | Hiring PLC programmer for line expansion | Maya Lopez | Controls Manager | https://example.com/jobs/apex"

    assert [{:ok, result}] = ProspectDiscovery.create_leads_from_result(result_text)

    {:ok, organization} = Operations.get_organization(result.organization_id)
    {:ok, signal} = Commercial.get_signal(result.signal_id)

    assert organization.name == "Apex Beverage Systems"
    assert organization.status == :prospect
    assert signal.organization_id == organization.id
    assert signal.source_channel == :agent_discovery
    assert signal.notes =~ "Hiring PLC programmer"
  end
end
