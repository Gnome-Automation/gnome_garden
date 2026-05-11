defmodule GnomeGardenWeb.PageControllerTest do
  use GnomeGardenWeb.ConnCase

  alias GnomeGarden.Commercial
  alias GnomeGarden.Execution
  alias GnomeGarden.Operations
  alias GnomeGarden.Procurement

  test "GET /", %{conn: conn} do
    conn = get(conn, ~p"/")
    assert html_response(conn, 200) =~ "Operations Workspace"
  end

  test "GET / surfaces due-soon maintenance plans", %{conn: conn} do
    {:ok, organization} =
      Operations.create_organization(%{
        name: "Beacon Packaging",
        organization_kind: :business,
        status: :active
      })

    {:ok, asset} =
      Operations.create_asset(%{
        organization_id: organization.id,
        asset_tag: "AST-910",
        name: "Packaging PLC",
        asset_type: :controller
      })

    {:ok, maintenance_plan} =
      Execution.create_maintenance_plan(%{
        organization_id: organization.id,
        asset_id: asset.id,
        name: "Monthly PLC review",
        interval_unit: :month,
        interval_value: 1,
        next_due_on: Date.add(Date.utc_today(), 7)
      })

    conn = get(conn, ~p"/")
    response = html_response(conn, 200)

    assert response =~ "Due Soon Maintenance"
    assert response =~ maintenance_plan.name
  end

  test "GET / surfaces runnable acquisition programs", %{conn: conn} do
    {:ok, discovery_program} =
      Commercial.create_discovery_program(%{
        name: "Due Discovery #{System.unique_integer([:positive])}",
        target_regions: ["oc"],
        target_industries: ["packaging"],
        cadence_hours: 24
      })

    {:ok, _discovery_program} = Commercial.activate_discovery_program(discovery_program)

    conn = get(conn, ~p"/")
    response = html_response(conn, 200)

    assert response =~ "Runnable Programs"
    assert response =~ discovery_program.name
  end

  test "GET / surfaces acquisition sources and active programs in the intake flow", %{conn: conn} do
    {:ok, source} =
      Procurement.create_procurement_source(%{
        name: "Regional Water Bid Portal",
        url: "https://example.com/procurement/regional-water-bids",
        source_type: :utility,
        portal_id: "regional-water-bids",
        region: :ca,
        priority: :high,
        status: :approved
      })

    {:ok, _source} =
      Procurement.configure_procurement_source(
        source,
        %{scrape_config: %{"provider" => "bidnet_direct"}},
        actor: nil
      )

    {:ok, discovery_program} =
      Commercial.create_discovery_program(%{
        name: "Industrial Accounts West",
        target_regions: ["oc"],
        target_industries: ["manufacturing"]
      })

    {:ok, _discovery_program} = Commercial.activate_discovery_program(discovery_program)

    conn = get(conn, ~p"/")
    response = html_response(conn, 200)

    assert response =~ "Runnable Sources"
    assert response =~ "Runnable Programs"
    assert response =~ "Acquisition Flow"
    assert response =~ source.name
    assert response =~ discovery_program.name
  end
end
