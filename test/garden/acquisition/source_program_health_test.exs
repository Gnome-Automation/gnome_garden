defmodule GnomeGarden.Acquisition.SourceProgramHealthTest do
  use GnomeGarden.DataCase, async: true

  alias GnomeGarden.Acquisition
  alias GnomeGarden.Commercial
  alias GnomeGarden.Procurement

  test "console sources expose failing run health and runnable state" do
    {:ok, procurement_source} =
      Procurement.create_procurement_source(%{
        name: "Failing Water Source",
        url: "https://example.com/procurement/failing-water-source",
        source_type: :utility,
        portal_id: "failing-water-source",
        region: :ca,
        priority: :high,
        status: :approved
      })

    {:ok, acquisition_source} =
      Acquisition.get_source_by_external_ref("procurement_source:#{procurement_source.id}")

    failed_at = DateTime.add(DateTime.utc_now(), -2 * 60 * 60, :second)

    {:ok, _source} =
      Acquisition.update_source(acquisition_source, %{
        last_run_at: failed_at,
        metadata: %{"last_agent_run_state" => "failed"}
      })

    {:ok, source} =
      Acquisition.get_source(acquisition_source.id,
        load: [:runnable, :health_note, :health_status, :health_variant]
      )

    assert source.runnable
    assert source.health_status == :failing
    assert source.health_variant == :error
    assert source.health_note =~ "Last run failed"
  end

  test "console sources detect noisy finding mixes" do
    {:ok, procurement_source} =
      Procurement.create_procurement_source(%{
        name: "Noisy Bid Source",
        url: "https://example.com/procurement/noisy-bid-source",
        source_type: :bidnet,
        portal_id: "noisy-bid-source",
        region: :oc,
        priority: :medium,
        status: :approved
      })

    {:ok, acquisition_source} =
      Acquisition.get_source_by_external_ref("procurement_source:#{procurement_source.id}")

    for index <- 1..3 do
      assert {:ok, _finding} =
               Acquisition.create_finding(%{
                 external_ref: "noisy-source-finding-#{index}-#{procurement_source.id}",
                 title: "Noisy Finding #{index}",
                 finding_family: :procurement,
                 finding_type: :bid_notice,
                 status: if(rem(index, 2) == 0, do: :rejected, else: :suppressed),
                 observed_at: DateTime.utc_now(),
                 source_id: acquisition_source.id
               })
    end

    {:ok, source} =
      Acquisition.get_source(acquisition_source.id,
        load: [:health_note, :health_status, :noise_finding_count]
      )

    assert source.noise_finding_count == 3
    assert source.health_status == :noisy
    assert source.health_note =~ "3 noise"
  end

  test "console programs detect stale cadence from scope" do
    {:ok, discovery_program} =
      Commercial.create_discovery_program(%{
        name: "Stale Discovery Sweep",
        target_regions: ["oc"],
        target_industries: ["manufacturing"],
        cadence_hours: 24
      })

    {:ok, active_discovery_program} = Commercial.activate_discovery_program(discovery_program)

    {:ok, acquisition_program} =
      Acquisition.get_program_by_external_ref("discovery_program:#{active_discovery_program.id}")

    stale_run_at = DateTime.add(DateTime.utc_now(), -48 * 60 * 60, :second)

    {:ok, _program} =
      Acquisition.update_program(acquisition_program, %{
        last_run_at: stale_run_at,
        scope: Map.put(acquisition_program.scope || %{}, :cadence_hours, 24)
      })

    {:ok, program} =
      Acquisition.get_program(acquisition_program.id,
        load: [:runnable, :health_note, :health_status, :health_variant]
      )

    assert program.runnable
    assert program.health_status == :stale
    assert program.health_variant == :warning
    assert program.health_note =~ "Cadence overdue"
  end
end
