defmodule GnomeGardenWeb.PageControllerTest do
  use GnomeGardenWeb.ConnCase

  alias GnomeGarden.Execution
  alias GnomeGarden.Operations

  test "GET /", %{conn: conn} do
    conn = get(conn, ~p"/")
    assert html_response(conn, 200) =~ "Operations Cockpit"
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
end
