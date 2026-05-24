defmodule GnomeGarden.Procurement.ProcurementSourceTest do
  use GnomeGarden.DataCase, async: true

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
end
