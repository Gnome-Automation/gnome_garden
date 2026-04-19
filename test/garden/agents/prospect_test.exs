defmodule GnomeGarden.Agents.ProspectTest do
  use GnomeGarden.DataCase, async: true

  alias GnomeGarden.Agents
  alias GnomeGarden.Commercial
  alias GnomeGarden.Operations

  test "prospects can link to organizations and signals in the long-term model" do
    {:ok, prospect} =
      Agents.create_prospect(%{
        name: "Blue Mesa Packaging",
        website: "https://blue-mesa.example.com",
        location: "Anaheim, CA",
        region: :oc,
        industry: :packaging,
        signals: ["hiring_controls_engineer"]
      })

    {:ok, organization} =
      Operations.create_organization(%{
        name: "Blue Mesa Packaging",
        status: :prospect,
        relationship_roles: ["prospect"]
      })

    {:ok, prospect} =
      Agents.convert_prospect_to_organization(prospect, %{organization_id: organization.id})

    {:ok, signal} =
      Commercial.create_signal(%{
        title: "Blue Mesa Packaging controls hiring",
        signal_type: :outbound_target,
        source_channel: :agent_discovery,
        organization_id: organization.id
      })

    {:ok, converted_prospect} =
      Agents.convert_prospect_to_signal(prospect, %{signal_id: signal.id})

    assert converted_prospect.converted_organization_id == organization.id
    assert converted_prospect.converted_signal_id == signal.id
    assert converted_prospect.status == :contacted
  end
end
