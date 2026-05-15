defmodule GnomeGarden.Acquisition.PilotSeedsTest do
  use GnomeGarden.DataCase, async: true

  alias GnomeGarden.Acquisition
  alias GnomeGarden.Acquisition.PilotSeeds
  alias GnomeGarden.Commercial
  alias GnomeGarden.Procurement

  test "ensure_defaults creates active discovery programs and configured procurement sources idempotently" do
    assert {:ok, %{programs: programs, sources: sources}} = PilotSeeds.ensure_defaults()

    assert length(programs) == 6
    assert length(sources) == 5
    assert Enum.all?(programs, &(&1.status == :active))
    assert Enum.all?(sources, &(&1.status == :approved))
    assert Enum.all?(sources, &(&1.config_status == :configured))

    assert {:ok, %{programs: second_programs, sources: second_sources}} =
             PilotSeeds.ensure_defaults()

    assert Enum.map(second_programs, & &1.id) == Enum.map(programs, & &1.id)
    assert Enum.map(second_sources, & &1.id) == Enum.map(sources, & &1.id)

    assert {:ok, acquisition_sources} = Acquisition.list_console_sources()
    assert Enum.any?(acquisition_sources, &(&1.name == "SAM.gov Contract Opportunities"))

    assert {:ok, active_programs} = Commercial.list_active_discovery_programs()
    assert Enum.any?(active_programs, &(&1.name == "Seven Day Food Plant Automation Sweep"))

    assert {:ok, ready_sources} = Procurement.list_procurement_sources_ready_for_scan(24)
    assert Enum.any?(ready_sources, &(&1.name == "City of Anaheim OpenGov"))
  end
end
