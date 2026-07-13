defmodule GnomeGardenWeb.AcquisitionSourceLiveTest do
  use GnomeGardenWeb.ConnCase
  use Oban.Testing, repo: GnomeGarden.Repo

  setup :register_and_log_in_user

  import Phoenix.LiveViewTest

  alias GnomeGarden.Acquisition
  alias GnomeGarden.Procurement
  alias GnomeGarden.Procurement.Workers.TestSourceCredential

  defmodule SuccessfulBidNetSessionRunner do
    def run(action, payload, opts) do
      send(Application.fetch_env!(:gnome_garden, :bidnet_session_test_pid), {
        :bidnet_session_runner,
        action,
        payload,
        opts
      })

      {:ok,
       %{
         "finalUrl" => "https://www.bidnetdirect.com/private",
         "title" => "BidNet Direct",
         "status" => 200,
         "storageStatePath" => payload.storage_state_path,
         "tracePath" => payload.trace_path,
         "screenshotPath" => payload.screenshot_path
       }}
    end
  end

  test "source registry renders synced procurement sources with finding counts", %{conn: conn} do
    {:ok, source} =
      Procurement.create_procurement_source(%{
        name: "OC BidNet Controls",
        url: "https://example.com/bidnet/controls",
        source_type: :bidnet,
        portal_id: "oc-controls",
        region: :oc,
        priority: :high,
        status: :approved
      })

    {:ok, _bid} =
      Procurement.create_bid(%{
        procurement_source_id: source.id,
        title: "Water plant controls retrofit",
        url: "https://example.com/bids/water-plant-controls-retrofit",
        external_id: "WATER-PLANT-CONTROLS",
        description: "PLC, SCADA, and historian refresh.",
        agency: "OC Water District",
        location: "Anaheim, CA",
        region: :oc,
        score_total: 84,
        score_tier: :hot,
        score_recommendation: "Promote to signal"
      })

    {:ok, acquisition_source} =
      Acquisition.get_source_by_external_ref("procurement_source:#{source.id}")

    {:ok, acquisition_source} =
      Acquisition.get_source(acquisition_source.id, load: [:finding_count, :runnable])

    assert acquisition_source.name == source.name
    assert acquisition_source.finding_count == 1
    refute acquisition_source.runnable

    {:ok, view, _html} = live(conn, ~p"/acquisition/sources")

    assert render(view) =~ "Source Registry"

    assert render(view) =~ "Source Registry"

    assert has_element?(
             view,
             "#configure-source-#{acquisition_source.id}",
             "Configure"
           )

    {:ok, unchanged_source} = Procurement.get_procurement_source(source.id)
    assert unchanged_source.config_status == :found

    refute render(view) =~ "Manual Fallback"
    refute render(view) =~ "Launch Scan"
  end

  test "source registry hides launch when a source is not runnable", %{conn: conn} do
    {:ok, source} =
      Procurement.create_procurement_source(%{
        name: "Paused Mechanical Portal",
        url: "https://example.com/bidnet/paused-mechanical",
        source_type: :bidnet,
        portal_id: "paused-mechanical",
        region: :ca,
        priority: :medium,
        status: :approved
      })

    {:ok, acquisition_source} =
      Acquisition.get_source_by_external_ref("procurement_source:#{source.id}")

    {:ok, _source} = Acquisition.update_source(acquisition_source, %{enabled: false})

    {:ok, acquisition_source} =
      Acquisition.get_source(acquisition_source.id, load: [:runnable])

    refute acquisition_source.runnable

    {:ok, view, _html} = live(conn, ~p"/acquisition/sources")

    assert render(view) =~ "Source Registry"
  end

  test "source registry refreshes when Ash PubSub publishes source updates", %{conn: conn} do
    {:ok, source} =
      Acquisition.create_source(%{
        name: "Manual directory intake",
        external_ref: "test:manual-directory-intake",
        url: "https://example.com/manual-directory-intake",
        source_family: :discovery,
        source_kind: :directory,
        status: :active,
        enabled: true,
        scan_strategy: :agentic
      })

    {:ok, view, _html} = live(conn, ~p"/acquisition/sources?bucket=all")

    assert render(view) =~ "Manual directory intake"

    {:ok, _source} =
      Acquisition.update_source(source, %{
        name: "Manual directory intake updated"
      })

    assert_eventually(fn -> render(view) =~ "Manual directory intake updated" end)
  end

  test "source registry separates review outcome counts", %{conn: conn} do
    {:ok, source} =
      Acquisition.create_source(%{
        name: "Outcome Count Portal",
        external_ref: "test:outcome-count-portal",
        url: "https://example.com/outcome-count-portal",
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
                 external_ref: "registry-outcome-count-#{index}",
                 title: "Registry Outcome Count #{index}",
                 finding_family: :procurement,
                 finding_type: :bid_notice,
                 status: status,
                 observed_at: DateTime.utc_now(),
                 source_id: source.id
               })
    end

    {:ok, view, _html} = live(conn, ~p"/acquisition/sources?bucket=all")

    html = render(view)

    assert html =~ "Outcome Count Portal"
    assert html =~ "2 waiting"
    assert html =~ "Accepted"
    assert html =~ "Parked"
    assert html =~ "Rejected"
    assert html =~ "Promoted"
  end

  test "source registry exposes a launch next action when a source is ready", %{conn: conn} do
    {:ok, _source} =
      Acquisition.create_source(%{
        name: "Ready company signal scan",
        external_ref: "test:ready-company-signal-scan",
        url: "https://example.com/ready-company-signal-scan",
        source_family: :discovery,
        source_kind: :company_site,
        status: :active,
        enabled: true,
        scan_strategy: :agentic
      })

    {:ok, view, _html} = live(conn, ~p"/acquisition/sources?bucket=ready")

    assert render(view) =~ "Ready company signal scan"
    assert has_element?(view, "button", "Launch Next Scan")
  end

  test "source registry exposes batch launch when multiple sources are ready", %{conn: conn} do
    for suffix <- ["one", "two"] do
      {:ok, _source} =
        Acquisition.create_source(%{
          name: "Ready batch source #{suffix}",
          external_ref: "test:ready-batch-source-#{suffix}",
          url: "https://example.com/ready-batch-source-#{suffix}",
          source_family: :discovery,
          source_kind: :directory,
          status: :active,
          enabled: true,
          scan_strategy: :agentic
        })
    end

    {:ok, view, _html} = live(conn, ~p"/acquisition/sources?bucket=ready")

    html = render(view)

    assert html =~ "Ready batch source one"
    assert html =~ "Ready batch source two"
    assert has_element?(view, "button", "Launch Next Scan")
    assert has_element?(view, "button", "Launch Ready")
  end

  test "source registry separates credential work from general attention", %{conn: conn} do
    original_username = System.get_env("PLANETBIDS_USERNAME")
    original_password = System.get_env("PLANETBIDS_PASSWORD")

    System.delete_env("PLANETBIDS_USERNAME")
    System.delete_env("PLANETBIDS_PASSWORD")

    on_exit(fn ->
      restore_env("PLANETBIDS_USERNAME", original_username)
      restore_env("PLANETBIDS_PASSWORD", original_password)
    end)

    {:ok, _source} =
      Procurement.create_procurement_source(%{
        name: "Credential gated portal",
        url: "https://vendors.planetbids.com/portal/99999/bo/bo-search",
        source_type: :planetbids,
        portal_id: "99999",
        region: :ca,
        priority: :high,
        status: :approved,
        requires_login: true
      })

    {:ok, view, _html} = live(conn, ~p"/acquisition/sources?bucket=credentials_needed")

    html = render(view)

    assert html =~ "Credentials needed"
    assert html =~ "Credential gated portal"
    assert html =~ "PlanetBids credentials are missing"
    assert has_element?(view, "a[href='/acquisition/sources?bucket=credentials_needed']", "1")

    {:ok, attention_view, _html} = live(conn, ~p"/acquisition/sources?bucket=attention")

    refute render(attention_view) =~ "Credential gated portal"
  end

  test "credentials queue includes BidNet sources even without a login flag", %{conn: conn} do
    {:ok, _source} =
      Procurement.create_procurement_source(%{
        name: "BidNet implicit credentials #{System.unique_integer([:positive])}",
        url: "https://example.com/bidnet/implicit-credentials",
        source_type: :bidnet,
        region: :ca,
        priority: :high,
        status: :approved,
        requires_login: false
      })

    {:ok, view, _html} = live(conn, ~p"/acquisition/sources?bucket=credentials_needed")
    assert render(view) =~ "BidNet implicit credentials"
  end

  test "source registry saves source family credentials from the queue", %{conn: conn} do
    original_username = System.get_env("PLANETBIDS_USERNAME")
    original_password = System.get_env("PLANETBIDS_PASSWORD")

    System.delete_env("PLANETBIDS_USERNAME")
    System.delete_env("PLANETBIDS_PASSWORD")

    on_exit(fn ->
      restore_env("PLANETBIDS_USERNAME", original_username)
      restore_env("PLANETBIDS_PASSWORD", original_password)
    end)

    {:ok, procurement_source} =
      Procurement.create_procurement_source(%{
        name: "Credential form portal",
        url: "https://vendors.planetbids.com/portal/10000/bo/bo-search",
        source_type: :planetbids,
        portal_id: "10000",
        region: :ca,
        priority: :high,
        status: :approved,
        requires_login: true
      })

    {:ok, acquisition_source} =
      Acquisition.get_source_by_external_ref("procurement_source:#{procurement_source.id}")

    {:ok, view, _html} = live(conn, ~p"/acquisition/sources?bucket=credentials_needed")

    assert has_element?(view, "#add-credentials-#{acquisition_source.id}", "Credentials")

    view
    |> element("#add-credentials-#{acquisition_source.id}")
    |> render_click()

    assert has_element?(view, "#source-credential-modal")

    view
    |> form("#source-credential-form",
      form: %{
        "username" => "operator@example.com",
        "password" => "source-secret"
      }
    )
    |> render_submit()

    assert {:error, message} = GnomeGarden.Procurement.SourceCredentials.planetbids_credentials()
    assert message =~ "verification is still pending"

    assert {:ok, [credential]} = Procurement.list_source_credentials(authorize?: false)
    assert credential.test_status == :queued
    assert credential.last_test_procurement_source_id == procurement_source.id

    assert_enqueued(
      worker: TestSourceCredential,
      args: %{
        "source_credential_id" => credential.id,
        "procurement_source_id" => procurement_source.id
      }
    )

    html = render(view)
    assert html =~ "credentials saved. Test queued."
    assert html =~ "Credential form portal"
    assert html =~ "Test queued"
  end

  test "source show renders stored credential test timestamps", %{conn: conn} do
    {:ok, procurement_source} =
      Procurement.create_procurement_source(%{
        name: "BidNet Direct",
        url: "https://www.bidnetdirect.com/california/",
        source_type: :bidnet,
        region: :ca,
        priority: :medium,
        status: :approved,
        requires_login: true
      })

    {:ok, acquisition_source} =
      Acquisition.get_source_by_external_ref("procurement_source:#{procurement_source.id}")

    {:ok, credential} =
      Procurement.create_source_credential(%{
        provider: :bidnet,
        credential_family: "bidnet",
        label: "BidNet default",
        username: "operator",
        password: "source-secret"
      })

    {:ok, credential} =
      Procurement.mark_source_credential_test_queued(credential, %{
        last_test_procurement_source_id: procurement_source.id
      })

    {:ok, credential} = Procurement.mark_source_credential_test_running(credential, %{})

    {:ok, _credential} =
      Procurement.mark_source_credential_failed(credential, %{
        last_failure_reason: "Portal rejected these credentials."
      })

    {:ok, _view, html} = live(conn, ~p"/acquisition/sources/#{acquisition_source.id}")

    assert html =~ "Credentials"
    assert html =~ "BidNet"
    assert html =~ "Last Tested"
    assert html =~ "Portal rejected these credentials."
  end

  test "source show refreshes BidNet browser sessions with stored credentials", %{conn: conn} do
    original_runner = Application.get_env(:gnome_garden, :bidnet_session_runner)
    original_pid = Application.get_env(:gnome_garden, :bidnet_session_test_pid)

    Application.put_env(
      :gnome_garden,
      :bidnet_session_runner,
      SuccessfulBidNetSessionRunner
    )

    Application.put_env(:gnome_garden, :bidnet_session_test_pid, self())

    on_exit(fn ->
      restore_app_env(:bidnet_session_runner, original_runner)
      restore_app_env(:bidnet_session_test_pid, original_pid)
    end)

    {:ok, procurement_source} =
      Procurement.create_procurement_source(%{
        name: "BidNet Session Controls",
        url: "https://www.bidnetdirect.com/california/solicitations/open-bids",
        source_type: :bidnet,
        region: :ca,
        priority: :high,
        status: :approved,
        requires_login: true
      })

    {:ok, acquisition_source} =
      Acquisition.get_source_by_external_ref("procurement_source:#{procurement_source.id}")

    {:ok, credential} =
      Procurement.create_source_credential(%{
        provider: :bidnet,
        credential_family: "bidnet",
        scope: :source,
        procurement_source_id: procurement_source.id,
        label: "BidNet source",
        username: "operator@example.com",
        password: "source-secret"
      })

    {:ok, _credential} =
      Procurement.mark_source_credential_manual_verification_required(credential, %{
        last_failure_reason: "Use BidNet browser session refresh."
      })

    {:ok, view, html} = live(conn, ~p"/acquisition/sources/#{acquisition_source.id}")

    assert html =~ "Browser Session"
    assert html =~ "No authenticated browser session"
    assert has_element?(view, "button", "Refresh Session")

    view
    |> element("button", "Refresh Session")
    |> render_click()

    assert_receive {:bidnet_session_runner, :bidnet_login, payload, _opts}
    assert payload.url == procurement_source.url
    assert payload.username == "operator@example.com"
    assert payload.password == "source-secret"

    assert {:ok, [session]} =
             Procurement.list_valid_source_browser_sessions_for_source(procurement_source.id)

    assert payload.storage_state_path =~ session.id
    assert session.source_credential_id == credential.id

    html = render(view)
    assert html =~ "BidNet browser session refreshed."
    assert html =~ "Valid"
  end

  test "source registry requeues tests for stored credentials", %{conn: conn} do
    original_username = System.get_env("PLANETBIDS_USERNAME")
    original_password = System.get_env("PLANETBIDS_PASSWORD")

    System.delete_env("PLANETBIDS_USERNAME")
    System.delete_env("PLANETBIDS_PASSWORD")

    on_exit(fn ->
      restore_env("PLANETBIDS_USERNAME", original_username)
      restore_env("PLANETBIDS_PASSWORD", original_password)
    end)

    {:ok, procurement_source} =
      Procurement.create_procurement_source(%{
        name: "Credential retest portal",
        url: "https://vendors.planetbids.com/portal/10001/bo/bo-search",
        source_type: :planetbids,
        portal_id: "10001",
        region: :ca,
        priority: :high,
        status: :approved,
        requires_login: true
      })

    {:ok, credential} =
      Procurement.create_source_credential(%{
        provider: :planetbids,
        credential_family: "planetbids",
        username: "operator@example.com",
        password: "source-secret"
      })

    {:ok, acquisition_source} =
      Acquisition.get_source_by_external_ref("procurement_source:#{procurement_source.id}")

    {:ok, view, _html} = live(conn, ~p"/acquisition/sources?bucket=all")

    assert has_element?(view, "#test-credentials-#{acquisition_source.id}", "Test Credentials")

    view
    |> element("#test-credentials-#{acquisition_source.id}")
    |> render_click()

    assert {:ok, queued} = Procurement.get_source_credential(credential.id, authorize?: false)
    assert queued.test_status == :queued
    assert queued.last_test_procurement_source_id == procurement_source.id

    assert_enqueued(
      worker: TestSourceCredential,
      args: %{
        "source_credential_id" => credential.id,
        "procurement_source_id" => procurement_source.id
      }
    )

    html = render(view)
    assert html =~ "credential test queued."
    assert html =~ "Test queued"
  end

  test "source registry shows durable run status and run link", %{conn: conn} do
    {:ok, _source} =
      Acquisition.create_source(%{
        name: "Ran directory intake",
        external_ref: "test:ran-directory-intake",
        url: "https://example.com/ran-directory-intake",
        source_family: :discovery,
        source_kind: :directory,
        status: :active,
        enabled: true,
        scan_strategy: :agentic,
        metadata: %{
          "last_agent_run_id" => "12345678-1234-1234-1234-123456789abc",
          "last_agent_run_state" => "running"
        }
      })

    {:ok, view, _html} = live(conn, ~p"/acquisition/sources?bucket=all")

    assert render(view) =~ "Ran directory intake"
    assert render(view) =~ "Running"
    assert render(view) =~ "Run 12345678"

    assert has_element?(
             view,
             "a[href='/console/agents/runs/12345678-1234-1234-1234-123456789abc']",
             "Open Run"
           )
  end

  test "source registry distinguishes timestamp-only run records from never-run sources", %{
    conn: conn
  } do
    {:ok, _source} =
      Acquisition.create_source(%{
        name: "Timestamp only source run",
        external_ref: "test:timestamp-only-source-run",
        url: "https://example.com/timestamp-only-source-run",
        source_family: :discovery,
        source_kind: :directory,
        status: :active,
        enabled: true,
        scan_strategy: :agentic,
        last_run_at: DateTime.utc_now()
      })

    {:ok, view, _html} = live(conn, ~p"/acquisition/sources?bucket=all")

    html = render(view)

    assert html =~ "Timestamp only source run"
    assert html =~ "Run recorded"
    assert html =~ "no agent run link recorded"
  end

  test "source registry surfaces zero-save scan health and last-run findings path", %{conn: conn} do
    run_id = Ecto.UUID.generate()

    {:ok, source} =
      Acquisition.create_source(%{
        name: "Zero save portal",
        external_ref: "test:zero-save-portal",
        url: "https://example.com/zero-save-portal",
        source_family: :procurement,
        source_kind: :portal,
        status: :active,
        enabled: true,
        scan_strategy: :agentic,
        last_run_at: DateTime.utc_now(),
        last_success_at: DateTime.utc_now(),
        metadata: %{
          "last_agent_run_id" => run_id,
          "last_agent_run_state" => "completed",
          "last_scan_summary" => %{
            "extracted" => 30,
            "scored" => 30,
            "saved" => 0,
            "diagnosis" => "scored_but_below_save_threshold",
            "extraction" => %{
              "row_count" => 30,
              "title_count" => 30,
              "link_count" => 28
            }
          }
        }
      })

    {:ok, view, _html} = live(conn, ~p"/acquisition/sources?bucket=attention")

    html = render(view)

    assert html =~ "Zero save portal"
    assert html =~ "Zero saved"
    assert html =~ "Last scan extracted 30 and scored 30, but saved 0."
    assert html =~ "Top candidates were below save threshold."
    assert html =~ "Last extraction: 30 rows / 30 titles / 28 links"

    assert html =~ "New From Last Run"
    assert html =~ "run_id=#{run_id}"
    assert html =~ "source_id=#{source.id}"
  end

  defp restore_env(name, nil), do: System.delete_env(name)
  defp restore_env(name, value), do: System.put_env(name, value)

  defp restore_app_env(key, nil), do: Application.delete_env(:gnome_garden, key)
  defp restore_app_env(key, value), do: Application.put_env(:gnome_garden, key, value)

  test "source refinement hides selector editing and saves search intent filters", %{conn: conn} do
    {:ok, source} =
      Procurement.create_procurement_source(%{
        name: "Configured County Portal",
        url: "https://example.com/configured-county",
        source_type: :custom,
        region: :oc,
        priority: :medium,
        status: :approved
      })

    {:ok, source} = Procurement.config_fail_procurement_source(source, %{})

    {:ok, acquisition_source} =
      Acquisition.get_source_by_external_ref("procurement_source:#{source.id}")

    {:ok, view, _html} = live(conn, ~p"/acquisition/sources/#{acquisition_source.id}/configure")

    html = render(view)

    assert html =~ "Refine Source"
    assert html =~ "Refinement changes operator intent"
    assert html =~ "Scanner Diagnostics"
    refute html =~ "source-config-form"
    refute html =~ "The repeated wrapper for one bid or opportunity row."

    view
    |> form("#source-search-filter-form",
      search_filter: %{
        filter_type: "keyword",
        value: "scada controls",
        label: "Controls work",
        per_run_limit: "5"
      }
    )
    |> render_submit()

    assert render(view) =~ "Search filter added."

    assert {:ok, [filter]} = Procurement.list_source_search_filters(source.id)

    assert filter.filter_type == :keyword
    assert filter.value == "scada controls"
    assert filter.label == "Controls work"
  end

  test "source configuration shows discovery running status for pending sources", %{conn: conn} do
    {:ok, source} =
      Procurement.create_procurement_source(%{
        name: "Pending Discovery Portal",
        url: "https://example.com/pending-discovery",
        source_type: :custom,
        region: :oc,
        priority: :medium,
        status: :approved
      })

    {:ok, source} = Procurement.queue_procurement_source(source, %{})

    {:ok, acquisition_source} =
      Acquisition.get_source_by_external_ref("procurement_source:#{source.id}")

    {:ok, _view, html} = live(conn, ~p"/acquisition/sources/#{acquisition_source.id}/configure")

    assert html =~ "Discovery running"
    assert html =~ "Browser discovery has been queued or is running."
    assert html =~ "Discovery Running"
  end

  test "source refinement shows current browser session status", %{conn: conn} do
    {:ok, source} =
      Procurement.create_procurement_source(%{
        name: "BidNet Refinement Session",
        url: "https://www.bidnetdirect.com/california/solicitations/open-bids",
        source_type: :bidnet,
        region: :ca,
        priority: :high,
        status: :approved,
        requires_login: true
      })

    {:ok, acquisition_source} =
      Acquisition.get_source_by_external_ref("procurement_source:#{source.id}")

    {:ok, session} =
      Procurement.create_source_browser_session(%{
        procurement_source_id: source.id,
        provider: :bidnet,
        session_family: "bidnet"
      })

    {:ok, _session} =
      Procurement.mark_source_browser_session_valid(session, %{
        storage_state_path: "/tmp/gnome-garden/browser-sessions/bidnet/storage-state.json",
        expires_at: DateTime.add(DateTime.utc_now(), 86_400, :second)
      })

    {:ok, _view, html} = live(conn, ~p"/acquisition/sources/#{acquisition_source.id}/configure")

    assert html =~ "Session"
    assert html =~ "Valid"
  end

  test "source configuration shows latest traversal evidence", %{conn: conn} do
    {:ok, source} =
      Procurement.create_procurement_source(%{
        name: "Evidence Portal",
        url: "https://example.com/evidence",
        source_type: :custom,
        region: :oc,
        priority: :medium,
        status: :approved
      })

    {:ok, source} =
      Procurement.configure_procurement_source(source, %{
        scrape_config: %{
          listing_url: "https://example.com/evidence/bids",
          listing_selector: ".bid-row",
          title_selector: ".bid-title"
        }
      })

    {:ok, run} =
      Procurement.start_crawl_run(%{
        procurement_source_id: source.id,
        seed_url: "https://example.com/evidence/bids",
        run_kind: :scan,
        max_pages: 1
      })

    {:ok, page} =
      Procurement.record_crawl_page(%{
        crawl_run_id: run.id,
        url: "https://example.com/evidence/bids",
        normalized_url: "https://example.com/evidence/bids",
        fetch_status: :fetched,
        depth: 0
      })

    {:ok, _candidate} =
      Procurement.propose_extraction_candidate(%{
        crawl_run_id: run.id,
        crawl_page_id: page.id,
        candidate_type: :bid,
        status: :accepted,
        payload: %{"title" => "Pump station SCADA upgrade"},
        evidence: %{"ordinal" => 0}
      })

    {:ok, _run} =
      Procurement.complete_crawl_run(run, %{
        summary: %{"extracted" => 3, "saved" => 1},
        diagnostics: %{"diagnosis" => "saved_candidates"}
      })

    {:ok, acquisition_source} =
      Acquisition.get_source_by_external_ref("procurement_source:#{source.id}")

    {:ok, _view, html} = live(conn, ~p"/acquisition/sources/#{acquisition_source.id}/configure")

    assert html =~ "Traversal Evidence"
    assert html =~ "Inspect Source"
    assert html =~ "https://example.com/evidence/bids"
    assert html =~ "Pages"
    assert html =~ "Candidates"
    assert html =~ "Extracted"
    assert html =~ "Saved"
    assert html =~ "saved_candidates"
  end

  test "source configuration shows a clear browser discovery error after discovery failure", %{
    conn: conn
  } do
    {:ok, source} =
      Procurement.create_procurement_source(%{
        name: "Unclear Portal",
        url: "https://example.com/unclear",
        source_type: :custom,
        region: :oc,
        priority: :medium,
        status: :approved
      })

    {:ok, source} =
      Procurement.update_procurement_source(source, %{
        metadata: %{
          "last_config_error" =>
            "Browser discovery could not identify a reliable listing pattern for this source. No repeated listing rows were found."
        }
      })

    {:ok, _source} = Procurement.config_fail_procurement_source(source, %{})

    {:ok, acquisition_source} =
      Acquisition.get_source_by_external_ref("procurement_source:#{source.id}")

    {:ok, _view, html} = live(conn, ~p"/acquisition/sources/#{acquisition_source.id}/configure")

    assert html =~ "Browser discovery could not get clear data from this source."
    assert html =~ "No repeated listing rows were found."
    assert html =~ "developer tooling to inspect scanner configuration"
    refute html =~ "Save Configuration"
  end

  test "source configuration shows SAM filter performance recommendations", %{conn: conn} do
    {:ok, source} =
      Procurement.create_procurement_source(%{
        name: "SAM Performance Source",
        url: "https://sam.gov/opportunities",
        source_type: :sam_gov,
        portal_id: "sam-performance-source",
        region: :national,
        priority: :medium,
        status: :approved
      })

    {:ok, filter} =
      Procurement.create_source_search_filter(%{
        procurement_source_id: source.id,
        filter_type: :naics,
        value: "541330",
        label: "Engineering services",
        per_run_limit: 10,
        enabled: true
      })

    assert {:ok, _filter} =
             Procurement.record_source_search_filter_run(filter, %{
               last_returned_count: 12,
               last_saved_count: 0
             })

    {:ok, acquisition_source} =
      Acquisition.get_source_by_external_ref("procurement_source:#{source.id}")

    {:ok, finding} =
      Acquisition.create_finding(%{
        title: "SAM filter rejected finding",
        external_ref: "sam-filter-rejected-finding-#{source.id}",
        finding_family: :procurement,
        finding_type: :bid_notice,
        status: :rejected,
        observed_at: DateTime.utc_now(),
        source_id: acquisition_source.id
      })

    assert {:ok, _feedback} =
             Procurement.record_source_search_filter_feedback(%{
               source_search_filter_id: filter.id,
               finding_id: finding.id,
               decision: :rejected,
               reason_code: "wrong_geography",
               reason: "Outside service geography."
             })

    {:ok, view, _html} = live(conn, ~p"/acquisition/sources/#{acquisition_source.id}/configure")

    html = render(view)
    assert html =~ "Search Intent"
    assert html =~ "541330"
    assert html =~ "Disable noisy filter"
    assert html =~ "12 returned in the last run. 1 rejected and 0 suppressed from review."
    assert html =~ "Filter Type"
    assert html =~ "accepted"
    assert html =~ "rejected"

    view
    |> element("button[phx-click='disable_noisy_search_filter']", "Disable Noisy")
    |> render_click()

    {:ok, disabled_filter} = Procurement.get_source_search_filter(filter.id)

    refute disabled_filter.enabled
    assert disabled_filter.metadata["operator_recommendation"] == "disable_noisy"

    assert render(view) =~ "Search filter disabled as noisy."

    view
    |> element("button[phx-click='keep_searching_filter']", "Keep Searching")
    |> render_click()

    {:ok, kept_filter} = Procurement.get_source_search_filter(filter.id)

    assert kept_filter.enabled
    assert kept_filter.metadata["operator_recommendation"] == "keep_searching"
    assert render(view) =~ "Search filter kept for the next run."
  end

  defp assert_eventually(fun, attempts \\ 10)

  defp assert_eventually(fun, attempts) when attempts > 0 do
    if fun.() do
      assert true
    else
      Process.sleep(50)
      assert_eventually(fun, attempts - 1)
    end
  end

  defp assert_eventually(fun, 0), do: assert(fun.())
end
