defmodule GnomeGarden.Commercial.CreatePursuitFromSignalTest do
  use GnomeGarden.DataCase, async: true

  alias GnomeGarden.Commercial
  alias GnomeGarden.Operations

  test "creates a pursuit from an accepted signal and converts the signal" do
    {:ok, organization} =
      Operations.create_organization(%{
        name: "Northwind Automation",
        status: :prospect,
        relationship_roles: ["prospect"]
      })

    {:ok, signal} =
      Commercial.create_signal(%{
        title: "Northwind wastewater controls upgrade",
        description: "Instrumentation refresh and reporting portal",
        signal_type: :bid_notice,
        source_channel: :agent_discovery,
        organization_id: organization.id,
        notes: "Agent found this on a monitored procurement source"
      })

    {:ok, accepted_signal} = Commercial.accept_signal(signal)

    {:ok, pursuit} =
      Commercial.create_pursuit_from_signal(
        accepted_signal.id,
        %{target_value: Decimal.new("125000.00"), expected_close_on: ~D[2026-06-15]}
      )

    {:ok, converted_signal} = Commercial.get_signal(accepted_signal.id)

    assert pursuit.signal_id == accepted_signal.id
    assert pursuit.organization_id == organization.id
    assert pursuit.name == accepted_signal.title
    assert pursuit.pursuit_type == :bid_response
    assert pursuit.priority == :high
    assert pursuit.probability == 20
    assert pursuit.delivery_model == :project
    assert pursuit.billing_model == :fixed_fee
    assert pursuit.stage == :new
    assert converted_signal.status == :converted
  end

  test "requires the signal to be accepted before creating a pursuit" do
    {:ok, organization} =
      Operations.create_organization(%{
        name: "Blue River Foods",
        status: :prospect,
        relationship_roles: ["prospect"]
      })

    {:ok, signal} =
      Commercial.create_signal(%{
        title: "Blue River MES modernization",
        signal_type: :inbound_request,
        source_channel: :website,
        organization_id: organization.id
      })

    assert {:error, error} = Commercial.create_pursuit_from_signal(signal.id)
    assert Exception.message(error) =~ "signal must be accepted before creating a pursuit"
  end
end
