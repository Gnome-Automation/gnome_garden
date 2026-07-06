defmodule GnomeGarden.Acquisition.PilotSeedsTest do
  use GnomeGarden.DataCase, async: true

  alias GnomeGarden.Acquisition
  alias GnomeGarden.Acquisition.PilotSeeds
  alias GnomeGarden.Commercial
  alias GnomeGarden.Procurement

  test "ensure_defaults creates active discovery programs and configured procurement sources idempotently" do
    assert {:ok, %{programs: programs, sources: sources}} = PilotSeeds.ensure_defaults()

    assert length(programs) == 6
    assert length(sources) == 6
    assert Enum.all?(programs, &(&1.status == :active))
    assert Enum.all?(sources, &(&1.status == :approved))
    assert Enum.all?(sources, &(&1.config_status == :configured))

    assert {:ok, %{programs: second_programs, sources: second_sources}} =
             PilotSeeds.ensure_defaults()

    assert Enum.map(second_programs, & &1.id) == Enum.map(programs, & &1.id)
    assert Enum.map(second_sources, & &1.id) == Enum.map(sources, & &1.id)

    assert {:ok, acquisition_sources} = Acquisition.list_console_sources()
    assert Enum.any?(acquisition_sources, &(&1.name == "SAM.gov Contract Opportunities"))

    sam_source = Enum.find(sources, &(&1.source_type == :sam_gov))
    assert {:ok, sam_filters} = Procurement.list_source_search_filters(sam_source.id)

    assert Enum.sort(Enum.map(sam_filters, &{&1.filter_type, &1.value})) == [
             {:keyword, "PLC"},
             {:keyword, "SCADA"},
             {:keyword, "control system"},
             {:keyword, "instrumentation"},
             {:keyword, "telemetry"},
             {:naics, "238210"},
             {:naics, "541330"},
             {:naics, "541511"},
             {:naics, "541512"},
             {:naics, "541519"}
           ]

    keyword_filters = Enum.filter(sam_filters, &(&1.filter_type == :keyword))
    assert Enum.all?(keyword_filters, &(&1.per_run_limit in [8, 10]))

    naics_filters = Enum.filter(sam_filters, &(&1.filter_type == :naics))
    assert Enum.all?(naics_filters, &(&1.per_run_limit == 5))

    software_source =
      Enum.find(sources, &(&1.name == "SAM.gov Software Development Opportunities"))

    assert software_source.source_type == :sam_gov
    assert software_source.metadata["company_profile_mode"] == "broad_software"

    assert {:ok, software_filters} = Procurement.list_source_search_filters(software_source.id)

    assert Enum.sort(Enum.map(software_filters, &{&1.filter_type, &1.value})) == [
             {:keyword, "API integration"},
             {:keyword, "custom software"},
             {:keyword, "dashboard"},
             {:keyword, "software development"},
             {:keyword, "web application"},
             {:keyword, "workflow software"},
             {:naics, "541511"},
             {:naics, "541512"},
             {:naics, "541519"}
           ]

    assert {:ok, active_programs} = Commercial.list_active_discovery_programs()
    assert Enum.any?(active_programs, &(&1.name == "Seven Day Food Plant Automation Sweep"))

    assert {:ok, ready_sources} = Procurement.list_procurement_sources_ready_for_scan(24)
    assert Enum.any?(ready_sources, &(&1.name == "City of Anaheim OpenGov"))
  end
end
