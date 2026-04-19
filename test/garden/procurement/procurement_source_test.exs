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
end
