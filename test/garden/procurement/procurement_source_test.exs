defmodule GnomeGarden.Procurement.ProcurementSourceTest do
  use GnomeGarden.DataCase, async: false

  alias GnomeGarden.Operations
  alias GnomeGarden.Acquisition
  alias GnomeGarden.Procurement

  defmodule FailingBrowserClient do
    def start_session(_opts), do: {:ok, %{id: "failing-browser"}}
    def end_session(_session), do: :ok

    def navigate(_session, _url, _opts),
      do: {:error, "Navigation failed: net::ERR_NAME_NOT_RESOLVED"}
  end

  test "creates a pre-configured company-site source for an organization" do
    {:ok, organization} =
      Operations.create_organization(%{
        name: "Signal Harbor Manufacturing",
        status: :prospect,
        relationship_roles: ["prospect"]
      })

    {:ok, source} =
      Procurement.create_procurement_source_for_organization(%{
        name: "Signal Harbor Manufacturing",
        url: "https://signalharbor.example.com",
        source_type: :company_site,
        region: :oc,
        organization_id: organization.id
      })

    assert source.organization_id == organization.id
    assert source.config_status == :configured
    assert source.status == :approved
    assert source.added_by == :agent
    assert source.portfolio_decision == :defer
    assert source.compliance_decision == :defer
    assert source.allowed_retrieval_paths == [:browser]

    assert {:ok, [fetched_source]} =
             Procurement.list_procurement_sources_by_organization(organization.id)

    assert fetched_source.id == source.id
  end

  test "portfolio review prevents ungoverned sources from entering automation" do
    {:ok, source} =
      Procurement.create_procurement_source(%{
        name: "Candidate OpenGov Source",
        url: "https://procurement.opengov.com/portal/example",
        source_type: :opengov,
        region: :oc,
        priority: :medium,
        status: :candidate
      })

    assert source.portfolio_decision == :defer
    assert source.compliance_decision == :defer
    assert source.adapter_owner == "GnomeGarden.Agents.Procurement.OpenGovAdapter"

    {:ok, source} = Procurement.approve_procurement_source(source)

    {:ok, source} =
      Procurement.configure_procurement_source(source, %{
        scrape_config: %{"listing_url" => source.url}
      })

    assert {:ok, ready_sources} = Acquisition.list_console_sources_ready()
    refute Enum.any?(ready_sources, &(&1.procurement_source_id == source.id))

    assert {:error, error} =
             Procurement.review_procurement_source_portfolio(source, %{
               portfolio_decision: :adopt,
               compliance_decision: :defer,
               expected_coverage: "Public opportunities",
               adapter_owner: source.adapter_owner,
               allowed_retrieval_paths: [:http, :browser]
             })

    assert Ash.Error.to_error_class(error).errors
           |> Enum.any?(&(&1.field == :compliance_decision))

    assert {:ok, governed} =
             Procurement.review_procurement_source_portfolio(source, %{
               portfolio_decision: :adopt,
               compliance_decision: :adopt,
               expected_coverage: "Public opportunities",
               adapter_owner: source.adapter_owner,
               allowed_retrieval_paths: [:http, :browser],
               governance_notes: "Public portal access approved for bounded retrieval."
             })

    assert governed.policy_reviewed_at
    assert governed.portfolio_decision == :adopt
    assert governed.compliance_decision == :adopt

    assert {:ok, ready_sources} = Acquisition.list_console_sources_ready()
    assert Enum.any?(ready_sources, &(&1.procurement_source_id == source.id))
  end

  test "SAM.gov adoption requires the reviewed account-specific daily limit" do
    {:ok, source} =
      Procurement.create_procurement_source(%{
        name: "Governed SAM.gov Source",
        url: "https://sam.gov/opportunities/governed",
        source_type: :sam_gov,
        region: :national,
        priority: :high,
        status: :approved
      })

    assert source.portfolio_decision == :defer
    assert source.compliance_decision == :defer

    attrs = %{
      portfolio_decision: :adopt,
      compliance_decision: :adopt,
      expected_coverage: "Active federal contract opportunities",
      adapter_owner: source.adapter_owner,
      allowed_retrieval_paths: [:provider_api]
    }

    assert {:error, error} = Procurement.review_procurement_source_portfolio(source, attrs)

    assert Ash.Error.to_error_class(error).errors
           |> Enum.any?(&(&1.field == :rate_limit_per_day))

    assert {:ok, adopted} =
             Procurement.review_procurement_source_portfolio(
               source,
               Map.put(attrs, :rate_limit_per_day, 10)
             )

    assert adopted.portfolio_decision == :adopt
    assert adopted.rate_limit_per_day == 10

    assert {:ok, acquisition_source} =
             Acquisition.get_source_by_external_ref("procurement_source:#{source.id}")

    assert {:ok, workspace} = Acquisition.get_source_workspace(acquisition_source.id)
    assert workspace.procurement_source.id == source.id
    assert workspace.procurement_source.provider_budget_state["remaining_requests"] == 10
  end

  test "idempotent source discovery never resets reviewed governance" do
    attrs = %{
      name: "Stable Governed Source",
      url: "https://example.com/stable-governed-source",
      source_type: :custom,
      region: :oc,
      priority: :medium,
      status: :approved
    }

    source = Procurement.create_procurement_source!(attrs)

    reviewed =
      Procurement.review_procurement_source_portfolio!(source, %{
        portfolio_decision: :adopt,
        compliance_decision: :adopt,
        expected_coverage: "Reviewed source-specific coverage",
        adapter_owner: source.adapter_owner,
        allowed_retrieval_paths: [:http],
        governance_notes: "Operator-reviewed policy"
      })

    rediscovered = Procurement.create_procurement_source!(attrs)

    assert rediscovered.id == reviewed.id
    assert rediscovered.portfolio_decision == :adopt
    assert rediscovered.compliance_decision == :adopt
    assert rediscovered.expected_coverage == "Reviewed source-specific coverage"
    assert rediscovered.allowed_retrieval_paths == [:http]
    assert rediscovered.governance_notes == "Operator-reviewed policy"
    assert rediscovered.policy_reviewed_at == reviewed.policy_reviewed_at
  end

  test "scan deferral removes a governed source from the ready queue until cleared" do
    {:ok, source} =
      Procurement.create_procurement_source(%{
        name: "Deferred Governed Source",
        url: "https://example.com/deferred-governed-source",
        source_type: :custom,
        region: :oc,
        priority: :medium,
        status: :approved
      })

    {:ok, source} =
      Procurement.configure_procurement_source(source, %{
        scrape_config: %{
          listing_url: source.url,
          listing_selector: ".listing",
          title_selector: ".title"
        }
      })

    {:ok, source} =
      Procurement.review_procurement_source_portfolio(source, %{
        portfolio_decision: :adopt,
        compliance_decision: :adopt,
        expected_coverage: source.expected_coverage,
        adapter_owner: source.adapter_owner,
        allowed_retrieval_paths: source.allowed_retrieval_paths
      })

    assert {:ok, ready} = Procurement.list_procurement_sources_ready_for_scan(24)
    assert Enum.any?(ready, &(&1.id == source.id))

    assert {:ok, deferred} =
             Procurement.defer_procurement_source_scan(source, %{
               deferred_until: DateTime.utc_now() |> DateTime.add(3_600, :second),
               defer_reason: "Provider quota reset"
             })

    assert deferred.health_action_reason == "Provider quota reset"
    assert {:ok, ready} = Procurement.list_procurement_sources_ready_for_scan(24)
    refute Enum.any?(ready, &(&1.id == source.id))

    assert {:ok, _resumed} = Procurement.clear_procurement_source_scan_deferral(deferred)
    assert {:ok, ready} = Procurement.list_procurement_sources_ready_for_scan(24)
    assert Enum.any?(ready, &(&1.id == source.id))
  end

  test "ready for scan includes scan-failed sources for automatic retry" do
    {:ok, source} =
      Procurement.create_procurement_source(%{
        name: "Retryable Failed Source",
        url: "https://example.com/retryable-failed-source",
        source_type: :custom,
        region: :oc,
        priority: :medium,
        status: :approved
      })

    {:ok, source} =
      Procurement.configure_procurement_source(source, %{
        scrape_config: %{
          listing_url: "https://example.com/retryable-failed-source",
          listing_selector: ".listing",
          title_selector: ".title"
        }
      })

    {:ok, source} =
      Procurement.review_procurement_source_portfolio(source, %{
        portfolio_decision: :adopt,
        compliance_decision: :adopt,
        expected_coverage: source.expected_coverage,
        adapter_owner: source.adapter_owner,
        allowed_retrieval_paths: source.allowed_retrieval_paths
      })

    {:ok, failed_source} = Procurement.scan_fail_procurement_source(source)

    assert failed_source.config_status == :scan_failed

    assert {:ok, ready_sources} = Procurement.list_procurement_sources_ready_for_scan(24)

    assert Enum.any?(ready_sources, &(&1.id == source.id))
  end

  test "groups independently scanned sub-sources by provider portal ID" do
    {:ok, parent} =
      Procurement.create_procurement_source(%{
        name: "PlanetBids Orange County",
        url: "https://vendors.planetbids.com/",
        source_type: :directory,
        region: :oc,
        priority: :high,
        enabled: false,
        status: :approved
      })

    {:ok, cypress} =
      Procurement.create_procurement_source(%{
        name: "City of Cypress PlanetBids",
        url: "https://vendors.planetbids.com/portal/78736/bo/bo-search",
        source_type: :planetbids,
        portal_id: "78736",
        parent_source_id: parent.id,
        region: :oc,
        priority: :medium,
        status: :approved
      })

    {:ok, irvine} =
      Procurement.create_procurement_source(%{
        name: "City of Irvine PlanetBids",
        url: "https://vendors.planetbids.com/portal/15927/bo/bo-search",
        source_type: :planetbids,
        portal_id: "15927",
        parent_source_id: parent.id,
        region: :oc,
        priority: :high,
        status: :approved
      })

    assert {:ok, sub_sources} = Procurement.list_procurement_sub_sources(parent.id)
    assert Enum.map(sub_sources, & &1.id) == [cypress.id, irvine.id]

    assert {:ok, fetched} =
             Procurement.get_procurement_sub_source_by_portal_id(parent.id, "78736")

    assert fetched.id == cypress.id
  end

  test "supports PublicPurchase agency sub-sources as persisted portal records" do
    {:ok, parent} =
      Procurement.create_procurement_source(%{
        name: "PublicPurchase Agency Portals",
        url: "https://www.publicpurchase.example",
        source_type: :directory,
        enabled: false,
        status: :approved
      })

    assert {:ok, source} =
             Procurement.create_procurement_source(%{
               name: "City of Del Mar PublicPurchase",
               url: "https://www.publicpurchase.example/gems/delmar",
               source_type: :publicpurchase,
               portal_id: "delmar,ca",
               parent_source_id: parent.id,
               requires_login: true,
               status: :approved
             })

    assert source.source_type == :publicpurchase
    assert source.portal_id == "delmar,ca"
    assert source.parent_source_id == parent.id
  end

  test "auto configure failure marks source config failed and records diagnostics" do
    original_browser_client = Application.get_env(:gnome_garden, :browser_client)

    :ok = GnomeGarden.Browser.SessionManager.reset()
    Application.put_env(:gnome_garden, :browser_client, FailingBrowserClient)

    on_exit(fn ->
      _ = GnomeGarden.Browser.SessionManager.reset()

      if original_browser_client do
        Application.put_env(:gnome_garden, :browser_client, original_browser_client)
      else
        Application.delete_env(:gnome_garden, :browser_client)
      end
    end)

    {:ok, source} =
      Procurement.create_procurement_source(%{
        name: "Dead Auto Configure Source",
        url: "https://dead-auto-configure.example",
        source_type: :custom,
        region: :oc,
        priority: :medium,
        status: :approved
      })

    assert {:ok, failed_source} = Procurement.auto_configure_procurement_source(source)

    assert failed_source.config_status == :config_failed
    assert failed_source.metadata["last_config_error"] =~ "ERR_NAME_NOT_RESOLVED"
    assert failed_source.metadata["last_config_error_at"]

    assert {:ok, sources_needing_configuration} =
             Procurement.list_procurement_sources_needing_configuration()

    refute Enum.any?(sources_needing_configuration, &(&1.id == source.id))
  end
end
