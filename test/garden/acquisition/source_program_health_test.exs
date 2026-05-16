defmodule GnomeGarden.Acquisition.SourceProgramHealthTest do
  use GnomeGarden.DataCase, async: false

  alias GnomeGarden.Acquisition
  alias GnomeGarden.Agents.Workers.Procurement.SourceScan
  alias GnomeGarden.Commercial
  alias GnomeGarden.Procurement

  setup do
    original_username = System.get_env("PLANETBIDS_USERNAME")
    original_password = System.get_env("PLANETBIDS_PASSWORD")

    on_exit(fn ->
      restore_env("PLANETBIDS_USERNAME", original_username)
      restore_env("PLANETBIDS_PASSWORD", original_password)
    end)

    :ok
  end

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

    {:ok, procurement_source} =
      Procurement.configure_procurement_source(procurement_source, %{
        scrape_config: %{
          listing_selector: ".listing",
          title_selector: ".title",
          listing_url: procurement_source.url
        }
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

  test "console sources do not mark unconfigured procurement sources runnable" do
    {:ok, procurement_source} =
      Procurement.create_procurement_source(%{
        name: "Unconfigured Source",
        url: "https://example.com/procurement/unconfigured-source",
        source_type: :utility,
        portal_id: "unconfigured-source",
        region: :ca,
        priority: :high,
        status: :approved
      })

    {:ok, acquisition_source} =
      Acquisition.get_source_by_external_ref("procurement_source:#{procurement_source.id}")

    {:ok, source} = Acquisition.get_source(acquisition_source.id, load: [:runnable])

    refute source.runnable
  end

  test "procurement launch metadata updates acquisition source last run timestamp" do
    started_at = ~U[2026-05-16 16:50:00Z]

    {:ok, procurement_source} =
      Procurement.create_procurement_source(%{
        name: "Launched Procurement Source",
        url: "https://example.com/procurement/launched-source",
        source_type: :utility,
        portal_id: "launched-source",
        region: :ca,
        priority: :high,
        status: :approved
      })

    {:ok, acquisition_source} =
      Acquisition.get_source_by_external_ref("procurement_source:#{procurement_source.id}")

    assert is_nil(acquisition_source.last_run_at)

    {:ok, _procurement_source} =
      Procurement.update_procurement_source(procurement_source, %{
        metadata: %{
          "last_agent_run_id" => Ecto.UUID.generate(),
          "last_agent_run_state" => "running",
          "last_agent_run_started_at" => DateTime.to_iso8601(started_at)
        }
      })

    {:ok, refreshed_source} = Acquisition.get_source(acquisition_source.id)

    assert refreshed_source.last_run_at == started_at
    assert is_nil(refreshed_source.last_success_at)
  end

  test "console sources explain listing selector misses from scan diagnostics" do
    {:ok, source} =
      Acquisition.create_source(%{
        name: "Broken Listing Selector",
        external_ref: "test:broken-listing-selector",
        url: "https://example.com/broken-listing-selector",
        source_family: :procurement,
        source_kind: :portal,
        status: :active,
        enabled: true,
        scan_strategy: :agentic,
        metadata: %{
          "last_scan_summary" => %{
            "diagnosis" => "listing_selector_matched_no_rows",
            "extracted" => 0,
            "scored" => 0,
            "saved" => 0,
            "extraction" => %{
              "listing_selector" => ".bid-row",
              "row_count" => 0,
              "title_count" => 0
            }
          }
        }
      })

    {:ok, loaded_source} =
      Acquisition.get_source(source.id, load: [:health_status, :health_variant, :health_note])

    assert loaded_source.health_status == :selector_failed
    assert loaded_source.health_variant == :error
    assert loaded_source.health_note =~ "matched 0 rows"
    assert loaded_source.health_note =~ ".bid-row"
  end

  test "console sources explain title selector misses from scan diagnostics" do
    {:ok, source} =
      Acquisition.create_source(%{
        name: "Broken Title Selector",
        external_ref: "test:broken-title-selector",
        url: "https://example.com/broken-title-selector",
        source_family: :procurement,
        source_kind: :portal,
        status: :active,
        enabled: true,
        scan_strategy: :agentic,
        metadata: %{
          "last_scan_summary" => %{
            "diagnosis" => "title_selector_matched_no_titles",
            "extracted" => 0,
            "scored" => 0,
            "saved" => 0,
            "extraction" => %{
              "listing_selector" => "table tbody tr",
              "title_selector" => ".title",
              "row_count" => 12,
              "title_count" => 0
            }
          }
        }
      })

    {:ok, loaded_source} =
      Acquisition.get_source(source.id, load: [:health_status, :health_variant, :health_note])

    assert loaded_source.health_status == :selector_failed
    assert loaded_source.health_variant == :error
    assert loaded_source.health_note =~ "matched 12 rows"
    assert loaded_source.health_note =~ ".title"
  end

  test "sam.gov source scans query the API and save qualified bids" do
    run_id = Ecto.UUID.generate()

    {:ok, procurement_source} =
      Procurement.create_procurement_source(%{
        name: "SAM Source",
        url: "https://sam.gov/opportunities",
        source_type: :sam_gov,
        portal_id: "sam",
        region: :national,
        priority: :medium,
        status: :approved
      })

    {:ok, procurement_source} =
      Procurement.configure_procurement_source(procurement_source, %{
        scrape_config: %{
          keywords: "SCADA PLC controls",
          naics_codes: ["541330"],
          limit: 10
        }
      })

    http_get = fn _url, opts ->
      assert opts[:params][:api_key] == "test-sam-key"
      assert opts[:params][:keywords] == "SCADA PLC controls"
      assert opts[:params][:ncode] == "541330"

      {:ok,
       %{
         status: 200,
         body: %{
           "opportunitiesData" => [
             %{
               "noticeId" => "SAM-PLC-1",
               "title" => "SCADA PLC controls modernization and instrumentation services",
               "description" =>
                 "Federal water treatment facility automation upgrade with PLC, SCADA, controls integration, telemetry, and instrumentation support.",
               "fullParentPathName" => "Department of Energy",
               "uiLink" => "https://sam.gov/opp/SAM-PLC-1/view",
               "postedDate" => "2026-05-01",
               "responseDeadLine" => "2026-06-01T17:00:00-05:00",
               "naicsCode" => "541330",
               "placeOfPerformance" => %{
                 "city" => %{"name" => "Oak Ridge"},
                 "state" => %{"code" => "TN", "name" => "Tennessee"}
               }
             }
           ]
         }
       }}
    end

    assert {:ok, result} =
             SourceScan.execute_run(%{
               run: %{id: run_id, metadata: %{procurement_source_id: procurement_source.id}},
               deployment: %{},
               tool_context: %{
                 agent_run_id: run_id,
                 sam_gov_api_key: "test-sam-key",
                 http_get: http_get
               }
             })

    assert result.metadata.saved == 1
    assert result.text =~ "Scanned SAM Source: 1 saved, 0 excluded, 1 extracted."

    assert {:ok, bid} = Procurement.get_bid_by_url("https://sam.gov/opp/SAM-PLC-1/view")
    assert bid.procurement_source_id == procurement_source.id
    assert bid.score_tier in [:hot, :warm]

    {:ok, acquisition_source} =
      Acquisition.get_source_by_external_ref("procurement_source:#{procurement_source.id}",
        load: [:health_status, :health_variant, :health_note]
      )

    assert acquisition_source.health_note =~ "Last successful scan"
  end

  test "planetbids sources show needs login health when credentials are missing" do
    System.delete_env("PLANETBIDS_USERNAME")
    System.delete_env("PLANETBIDS_PASSWORD")

    {:ok, procurement_source} =
      Procurement.create_procurement_source(%{
        name: "Credentialed PlanetBids Source",
        url: "https://vendors.planetbids.com/portal/12345/bo/bo-search",
        source_type: :planetbids,
        portal_id: "12345",
        region: :ca,
        priority: :high,
        status: :approved,
        requires_login: true
      })

    {:ok, procurement_source} =
      Procurement.configure_procurement_source(procurement_source, %{
        scrape_config: %{
          listing_selector: ".bid-row",
          title_selector: ".bid-title",
          listing_url: procurement_source.url
        }
      })

    {:ok, acquisition_source} =
      Acquisition.get_source_by_external_ref("procurement_source:#{procurement_source.id}")

    {:ok, source} =
      Acquisition.get_source(acquisition_source.id,
        load: [:runnable, :health_label, :health_note, :health_status, :health_variant]
      )

    refute source.runnable
    assert source.health_status == :needs_login
    assert source.health_variant == :warning
    assert source.health_label == "Needs login"
    assert source.health_note =~ "PlanetBids credentials are missing"
  end

  test "planetbids sources are runnable when credentials are configured" do
    System.put_env("PLANETBIDS_USERNAME", "operator@example.com")
    System.put_env("PLANETBIDS_PASSWORD", "secret-for-test")

    {:ok, procurement_source} =
      Procurement.create_procurement_source(%{
        name: "Runnable PlanetBids Source",
        url: "https://vendors.planetbids.com/portal/67890/bo/bo-search",
        source_type: :planetbids,
        portal_id: "67890",
        region: :ca,
        priority: :high,
        status: :approved,
        requires_login: true
      })

    {:ok, procurement_source} =
      Procurement.configure_procurement_source(procurement_source, %{
        scrape_config: %{
          listing_selector: ".bid-row",
          title_selector: ".bid-title",
          listing_url: procurement_source.url
        }
      })

    {:ok, acquisition_source} =
      Acquisition.get_source_by_external_ref("procurement_source:#{procurement_source.id}")

    {:ok, source} =
      Acquisition.get_source(acquisition_source.id,
        load: [:runnable, :health_status, :health_variant]
      )

    assert source.runnable
    refute source.health_status == :needs_login
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

  defp restore_env(name, nil), do: System.delete_env(name)
  defp restore_env(name, value), do: System.put_env(name, value)

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
