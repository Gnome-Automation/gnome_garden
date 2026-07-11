defmodule GnomeGarden.Procurement.ProcurementSourceTest do
  use GnomeGarden.DataCase, async: false

  alias GnomeGarden.Operations
  alias GnomeGarden.Procurement

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

    assert {:ok, [fetched_source]} =
             Procurement.list_procurement_sources_by_organization(organization.id)

    assert fetched_source.id == source.id
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
    original_browser_path = Application.get_env(:gnome_garden, :browser_path)
    browser_path = fake_browser_path("Navigation failed: net::ERR_NAME_NOT_RESOLVED")

    Application.put_env(:gnome_garden, :browser_path, browser_path)

    on_exit(fn ->
      if original_browser_path do
        Application.put_env(:gnome_garden, :browser_path, original_browser_path)
      else
        Application.delete_env(:gnome_garden, :browser_path)
      end

      File.rm(browser_path)
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

  defp fake_browser_path(output) do
    path =
      Path.join(
        System.tmp_dir!(),
        "gnome-garden-fake-browser-#{System.unique_integer([:positive])}"
      )

    File.write!(path, """
    #!/bin/sh
    cat <<'EOF'
    #{output}
    EOF
    exit 1
    """)

    File.chmod!(path, 0o755)
    path
  end
end
