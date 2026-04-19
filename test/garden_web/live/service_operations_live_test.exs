defmodule GnomeGardenWeb.ServiceOperationsLiveTest do
  use GnomeGardenWeb.ConnCase

  import Phoenix.LiveViewTest

  alias GnomeGarden.Execution
  alias GnomeGarden.Operations

  test "asset routes render", %{conn: conn} do
    {:ok, organization} =
      Operations.create_organization(%{
        name: "Kepler Automation",
        organization_kind: :business,
        status: :active
      })

    {:ok, asset} =
      Operations.create_asset(%{
        organization_id: organization.id,
        asset_tag: "AST-100",
        name: "Main PLC Rack",
        asset_type: :controller
      })

    {:ok, index_view, index_html} = live(conn, ~p"/operations/assets")
    assert has_element?(index_view, "#assets")
    assert index_html =~ asset.name

    {:ok, show_view, _show_html} = live(conn, ~p"/operations/assets/#{asset}")
    assert render(show_view) =~ asset.asset_tag

    {:ok, form_view, _form_html} =
      live(conn, ~p"/operations/assets/new?organization_id=#{organization.id}")

    assert has_element?(form_view, "#asset-form")
  end

  test "service ticket routes render", %{conn: conn} do
    {:ok, organization} =
      Operations.create_organization(%{
        name: "Nova Controls",
        organization_kind: :business,
        status: :active
      })

    {:ok, asset} =
      Operations.create_asset(%{
        organization_id: organization.id,
        asset_tag: "AST-200",
        name: "SCADA Gateway",
        asset_type: :server
      })

    {:ok, service_ticket} =
      Execution.create_service_ticket(%{
        organization_id: organization.id,
        asset_id: asset.id,
        ticket_number: "TCK-100",
        title: "Gateway offline",
        severity: :high
      })

    {:ok, index_view, index_html} = live(conn, ~p"/execution/service-tickets")
    assert has_element?(index_view, "#service-tickets")
    assert index_html =~ service_ticket.title

    {:ok, show_view, _show_html} = live(conn, ~p"/execution/service-tickets/#{service_ticket}")
    assert render(show_view) =~ service_ticket.ticket_number

    {:ok, form_view, _form_html} =
      live(conn, ~p"/execution/service-tickets/new?organization_id=#{organization.id}")

    assert has_element?(form_view, "#service-ticket-form")
  end

  test "work order routes render", %{conn: conn} do
    {:ok, organization} =
      Operations.create_organization(%{
        name: "Ion Manufacturing",
        organization_kind: :business,
        status: :active
      })

    {:ok, service_ticket} =
      Execution.create_service_ticket(%{
        organization_id: organization.id,
        ticket_number: "TCK-200",
        title: "Panel inspection"
      })

    {:ok, work_order} =
      Execution.create_work_order(%{
        organization_id: organization.id,
        service_ticket_id: service_ticket.id,
        reference_number: "WO-100",
        title: "Inspect Panel 7",
        work_type: :inspection
      })

    {:ok, index_view, index_html} = live(conn, ~p"/execution/work-orders")
    assert has_element?(index_view, "#work-orders")
    assert index_html =~ work_order.title

    {:ok, show_view, _show_html} = live(conn, ~p"/execution/work-orders/#{work_order}")
    assert render(show_view) =~ work_order.reference_number

    {:ok, form_view, _form_html} =
      live(conn, ~p"/execution/work-orders/new?service_ticket_id=#{service_ticket.id}")

    assert has_element?(form_view, "#work-order-form")
  end
end
