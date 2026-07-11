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

    {:ok, source} =
      Acquisition.get_source(acquisition_source.id,
        load: [:runnable, :health_note, :health_status, :health_variant]
      )

    refute source.runnable
    assert source.health_status == :needs_configuration
    assert source.health_variant == :info
    assert source.health_note == "Queued for automatic source setup."
  end

  test "queued procurement sources show configuration in progress" do
    {:ok, procurement_source} =
      Procurement.create_procurement_source(%{
        name: "Queued Configuration Source",
        url: "https://example.com/procurement/queued-configuration-source",
        source_type: :utility,
        portal_id: "queued-configuration-source",
        region: :ca,
        priority: :high,
        status: :approved
      })

    {:ok, procurement_source} = Procurement.queue_procurement_source(procurement_source)

    {:ok, acquisition_source} =
      Acquisition.get_source_by_external_ref("procurement_source:#{procurement_source.id}")

    {:ok, source} =
      Acquisition.get_source(acquisition_source.id,
        load: [:runnable, :health_note, :health_status, :health_variant]
      )

    refute source.runnable
    assert source.health_status == :configuring
    assert source.health_variant == :info
    assert source.health_note == "Automatic source setup is running."
  end

  test "configured procurement sources without a first run show ready health" do
    {:ok, procurement_source} =
      Procurement.create_procurement_source(%{
        name: "Ready First Scan Source",
        url: "https://example.com/procurement/ready-first-scan-source",
        source_type: :utility,
        portal_id: "ready-first-scan-source",
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

    {:ok, source} =
      Acquisition.get_source(acquisition_source.id,
        load: [:runnable, :health_note, :health_status, :health_variant]
      )

    assert source.runnable
    assert source.health_status == :ready
    assert source.health_variant == :success
    assert source.health_note == "Configured and ready for its first scan."
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
    previous_sam_key = System.get_env("SAM_GOV_API_KEY")
    System.put_env("SAM_GOV_API_KEY", "test-sam-key")

    on_exit(fn ->
      restore_env("SAM_GOV_API_KEY", previous_sam_key)
    end)

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
          naics_codes: ["541330", "238210"],
          limit: 10
        }
      })

    test_pid = self()

    http_get = fn _url, opts ->
      assert opts[:params][:api_key] == "test-sam-key"
      assert opts[:params][:title] == "SCADA PLC controls"
      assert opts[:params][:ncode] in ["541330", "238210"]

      send(test_pid, {:sam_request, opts[:params][:ncode]})

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
               "responseDeadLine" => "2026-12-01T17:00:00-05:00",
               "naicsCode" => opts[:params][:ncode],
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
    assert_received {:sam_request, "541330"}
    assert_received {:sam_request, "238210"}

    assert {:ok, bid} = Procurement.get_bid_by_url("https://sam.gov/opp/SAM-PLC-1/view")
    assert bid.procurement_source_id == procurement_source.id
    assert bid.score_tier in [:hot, :warm]

    {:ok, acquisition_source} =
      Acquisition.get_source_by_external_ref("procurement_source:#{procurement_source.id}",
        load: [:health_status, :health_variant, :health_note]
      )

    assert acquisition_source.health_note =~ "Last successful scan"
  end

  test "sam.gov source scans resolve stored credentials when run context omits API key" do
    previous_sam_key = System.get_env("SAM_GOV_API_KEY")
    System.delete_env("SAM_GOV_API_KEY")

    on_exit(fn ->
      restore_env("SAM_GOV_API_KEY", previous_sam_key)
    end)

    {:ok, credential} =
      Procurement.create_source_credential(%{
        provider: :sam_gov,
        credential_family: "sam_gov",
        api_key: "stored-sam-key"
      })

    {:ok, _credential} = Procurement.mark_source_credential_verified(credential, %{})

    run_id = Ecto.UUID.generate()

    {:ok, procurement_source} =
      Procurement.create_procurement_source(%{
        name: "Stored Credential SAM Source",
        url: "https://sam.gov/opportunities/stored-credential",
        source_type: :sam_gov,
        portal_id: "sam-stored-credential",
        region: :national,
        priority: :medium,
        status: :approved
      })

    {:ok, procurement_source} =
      Procurement.configure_procurement_source(procurement_source, %{
        scrape_config: %{
          keywords: "software development dashboard API integration",
          naics_codes: ["541511"],
          limit: 10
        }
      })

    http_get = fn _url, opts ->
      assert opts[:params][:api_key] == "stored-sam-key"
      assert opts[:params][:title] == "software development dashboard API integration"
      assert opts[:params][:ncode] == "541511"

      {:ok,
       %{
         status: 200,
         body: %{
           "opportunitiesData" => [
             %{
               "noticeId" => "SAM-SOFTWARE-1",
               "title" => "Custom software development dashboard and API integration",
               "description" =>
                 "Custom software development for a workflow dashboard, API integration, reporting, and operations automation.",
               "fullParentPathName" => "Department of Commerce",
               "uiLink" => "https://sam.gov/opp/SAM-SOFTWARE-1/view",
               "postedDate" => "2026-06-01",
               "responseDeadLine" => "2026-12-15T17:00:00-05:00",
               "naicsCode" => "541511",
               "placeOfPerformance" => %{
                 "city" => %{"name" => "Washington"},
                 "state" => %{"code" => "DC", "name" => "District of Columbia"}
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
               tool_context: %{agent_run_id: run_id, http_get: http_get}
             })

    assert result.metadata.saved == 1
    assert result.text =~ "Scanned Stored Credential SAM Source: 1 saved"

    assert {:ok, bid} =
             Procurement.get_bid_by_url("https://sam.gov/opp/SAM-SOFTWARE-1/view")

    assert bid.procurement_source_id == procurement_source.id
  end

  test "sam.gov source scans use enabled persisted search filters and record counts" do
    previous_sam_key = System.get_env("SAM_GOV_API_KEY")
    System.put_env("SAM_GOV_API_KEY", "test-sam-key")

    on_exit(fn ->
      restore_env("SAM_GOV_API_KEY", previous_sam_key)
    end)

    run_id = Ecto.UUID.generate()

    {:ok, procurement_source} =
      Procurement.create_procurement_source(%{
        name: "SAM Filtered Source",
        url: "https://sam.gov/opportunities/search",
        source_type: :sam_gov,
        portal_id: "sam-filtered",
        region: :national,
        priority: :high,
        status: :approved
      })

    {:ok, procurement_source} =
      Procurement.configure_procurement_source(procurement_source, %{
        scrape_config: %{
          keywords: "ignored when persisted keyword is absent",
          naics_codes: ["000000"],
          limit: 20
        }
      })

    {:ok, enabled_filter} =
      Procurement.create_source_search_filter(%{
        procurement_source_id: procurement_source.id,
        filter_type: :naics,
        value: "541330",
        label: "Engineering services",
        per_run_limit: 7,
        enabled: true
      })

    {:ok, _disabled_filter} =
      Procurement.create_source_search_filter(%{
        procurement_source_id: procurement_source.id,
        filter_type: :naics,
        value: "238210",
        label: "Electrical contractors",
        per_run_limit: 7,
        enabled: false
      })

    test_pid = self()

    http_get = fn _url, opts ->
      assert opts[:params][:api_key] == "test-sam-key"
      assert opts[:params][:ncode] == "541330"
      assert opts[:params][:limit] == 7
      refute Map.has_key?(opts[:params], :title)

      send(test_pid, {:sam_request, opts[:params][:ncode]})

      {:ok,
       %{
         status: 200,
         body: %{
           "opportunitiesData" => [
             %{
               "noticeId" => "SAM-FILTER-1",
               "title" => "SCADA PLC controls modernization and instrumentation services",
               "description" =>
                 "Federal water treatment automation upgrade with PLC, SCADA, controls integration, telemetry, and instrumentation support.",
               "fullParentPathName" => "Department of Energy",
               "uiLink" => "https://sam.gov/opp/SAM-FILTER-1/view",
               "postedDate" => "2026-05-01",
               "responseDeadLine" => "2026-12-01T17:00:00-05:00",
               "naicsCode" => opts[:params][:ncode]
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
    assert_received {:sam_request, "541330"}
    refute_received {:sam_request, "238210"}
    refute_received {:sam_request, "000000"}

    {:ok, enabled_filter} = Procurement.get_source_search_filter(enabled_filter.id)
    assert enabled_filter.last_returned_count == 1
    assert enabled_filter.last_saved_count == 1
    assert enabled_filter.last_run_at

    assert {:ok, filters} = Procurement.list_source_search_filters(procurement_source.id)
    enabled_filter = Enum.find(filters, &(&1.value == "541330"))

    assert enabled_filter.performance_recommendation == "Keep"
    assert enabled_filter.performance_variant == :success
    assert enabled_filter.performance_note == "1 saved from 1 returned in the last run."

    {:ok, source} = Procurement.get_procurement_source(procurement_source.id)
    search_filter_counts = get_in(source.metadata, ["last_scan_summary", "search_filter_counts"])
    assert [%{"value" => "541330", "returned" => 1}] = search_filter_counts
  end

  test "sam.gov source scans record failure diagnostics on API errors" do
    {:ok, procurement_source} =
      Procurement.create_procurement_source(%{
        name: "SAM Rate Limited Source",
        url: "https://sam.gov/opportunities/rate-limited",
        source_type: :sam_gov,
        portal_id: "sam-rate-limited",
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

    http_get = fn _url, _opts ->
      {:ok, %{status: 429, body: %{"message" => "rate limited"}}}
    end

    assert {:error, "SAM.gov rate limit exceeded (1000/day)"} =
             Procurement.run_source_scan(
               %{source_id: procurement_source.id},
               scanner_context: %{sam_gov_api_key: "test-sam-key", http_get: http_get},
               authorize?: false
             )

    assert {:ok, source} = Procurement.get_procurement_source(procurement_source.id)
    assert source.config_status == :scan_failed
    assert source.metadata["last_scan_status"] == "failed"
    assert source.metadata["last_scan_summary"]["diagnosis"] == "scan_failed"

    assert source.metadata["last_scan_summary"]["reason"] ==
             "SAM.gov rate limit exceeded (1000/day)"
  end

  test "sam.gov sources show needs login health when API key is missing" do
    previous_sam_key = System.get_env("SAM_GOV_API_KEY")
    System.delete_env("SAM_GOV_API_KEY")

    on_exit(fn ->
      restore_env("SAM_GOV_API_KEY", previous_sam_key)
    end)

    {:ok, procurement_source} =
      Procurement.create_procurement_source(%{
        name: "Credentialed SAM Source",
        url: "https://sam.gov/opportunities",
        source_type: :sam_gov,
        portal_id: "sam-missing-key",
        region: :national,
        priority: :high,
        status: :approved
      })

    {:ok, _procurement_source} =
      Procurement.configure_procurement_source(procurement_source, %{
        scrape_config: %{
          keywords: "SCADA PLC controls",
          naics_codes: ["541330"],
          limit: 10
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
    assert source.health_note =~ "SAM.gov API key is missing"
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

  test "public planetbids sources do not require credentials" do
    System.delete_env("PLANETBIDS_USERNAME")
    System.delete_env("PLANETBIDS_PASSWORD")

    {:ok, procurement_source} =
      Procurement.create_procurement_source(%{
        name: "Public PlanetBids Source",
        url: "https://vendors.planetbids.com/portal/23456/bo/bo-search",
        source_type: :planetbids,
        portal_id: "23456",
        region: :ca,
        priority: :high,
        status: :approved,
        requires_login: false
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
        load: [:runnable, :health_note, :health_status, :health_variant]
      )

    assert source.runnable
    assert source.health_status == :ready
    assert source.health_variant == :success
    assert source.health_note == "Configured and ready for its first scan."
  end

  test "scan diagnostics can move a public source into credentials needed" do
    {:ok, procurement_source} =
      Procurement.create_procurement_source(%{
        name: "Login Revealed PlanetBids Source",
        url: "https://vendors.planetbids.com/portal/34567/bo/bo-search",
        source_type: :planetbids,
        portal_id: "34567",
        region: :ca,
        priority: :high,
        status: :approved,
        requires_login: false
      })

    {:ok, procurement_source} =
      Procurement.configure_procurement_source(procurement_source, %{
        scrape_config: %{
          listing_selector: ".bid-row",
          title_selector: ".bid-title",
          listing_url: procurement_source.url
        }
      })

    {:ok, procurement_source} =
      Procurement.update_procurement_source(procurement_source, %{
        metadata: %{
          "last_scan_summary" => %{
            "diagnosis" => "login_required",
            "extracted" => 0,
            "scored" => 0,
            "saved" => 0
          }
        }
      })

    {:ok, acquisition_source} =
      Acquisition.get_source_by_external_ref("procurement_source:#{procurement_source.id}")

    {:ok, source} =
      Acquisition.get_source(acquisition_source.id,
        load: [:health_label, :health_note, :health_status, :health_variant]
      )

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

  test "stored credentials must verify before they unblock source launch" do
    System.delete_env("PLANETBIDS_USERNAME")
    System.delete_env("PLANETBIDS_PASSWORD")

    {:ok, procurement_source} =
      Procurement.create_procurement_source(%{
        name: "Verified Credential PlanetBids Source",
        url: "https://vendors.planetbids.com/portal/67891/bo/bo-search",
        source_type: :planetbids,
        portal_id: "67891",
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

    {:ok, credential} =
      Procurement.create_source_credential(%{
        provider: :planetbids,
        credential_family: "planetbids",
        username: "operator@example.com",
        password: "secret-for-test"
      })

    {:ok, acquisition_source} =
      Acquisition.get_source_by_external_ref("procurement_source:#{procurement_source.id}")

    {:ok, pending_source} =
      Acquisition.get_source(acquisition_source.id,
        load: [:runnable, :health_note, :health_status, :health_variant]
      )

    refute pending_source.runnable
    assert pending_source.health_status == :credentials_pending
    assert pending_source.health_variant == :warning
    assert pending_source.health_note =~ "Waiting for credential verification"

    {:ok, _credential} = Procurement.mark_source_credential_verified(credential, %{})

    {:ok, verified_source} =
      Acquisition.get_source(acquisition_source.id,
        load: [:runnable, :health_status, :health_variant]
      )

    assert verified_source.runnable
    assert verified_source.health_status == :ready
    assert verified_source.health_variant == :success
  end

  test "console sources detect noisy finding mixes" do
    {:ok, procurement_source} =
      Procurement.create_procurement_source(%{
        name: "Noisy Bid Source",
        url: "https://example.com/procurement/noisy-bid-source",
        source_type: :custom,
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

  test "console sources expose review outcome counts separately" do
    {:ok, acquisition_source} =
      Acquisition.create_source(%{
        name: "Outcome Split Source",
        external_ref: "test:outcome-split-source",
        url: "https://example.com/outcome-split-source",
        source_family: :procurement,
        source_kind: :portal,
        status: :active,
        enabled: true,
        scan_strategy: :agentic
      })

    for {status, index} <- [
          {:new, 1},
          {:reviewing, 2},
          {:accepted, 3},
          {:parked, 4},
          {:rejected, 5},
          {:promoted, 6}
        ] do
      assert {:ok, _finding} =
               Acquisition.create_finding(%{
                 external_ref: "outcome-split-finding-#{index}",
                 title: "Outcome Split Finding #{index}",
                 finding_family: :procurement,
                 finding_type: :bid_notice,
                 status: status,
                 observed_at: DateTime.utc_now(),
                 source_id: acquisition_source.id
               })
    end

    {:ok, source} =
      Acquisition.get_source(acquisition_source.id,
        load: [
          :finding_count,
          :review_finding_count,
          :accepted_finding_count,
          :parked_finding_count,
          :rejected_finding_count,
          :promoted_finding_count
        ]
      )

    assert source.finding_count == 6
    assert source.review_finding_count == 2
    assert source.accepted_finding_count == 1
    assert source.parked_finding_count == 1
    assert source.rejected_finding_count == 1
    assert source.promoted_finding_count == 1
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
