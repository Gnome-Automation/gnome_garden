defmodule GnomeGardenWeb.TaskEntryPointsLiveTest do
  use GnomeGardenWeb.ConnCase

  setup :register_and_log_in_user

  import Phoenix.LiveViewTest

  alias GnomeGarden.Execution
  alias GnomeGarden.Operations

  test "project page shows linked tasks and a prefilled create path", %{conn: conn} do
    {:ok, organization} =
      Operations.create_organization(%{
        name: "Riverside HOA",
        organization_kind: :business,
        status: :prospect
      })

    {:ok, project} =
      Execution.create_project(%{organization_id: organization.id, name: "Irrigation retrofit"})

    {:ok, task} =
      Operations.create_task(%{
        title: "Pull county permit",
        project_id: project.id
      })

    {:ok, view, html} = live(conn, ~p"/execution/projects/#{project}")

    assert html =~ "Pull county permit"
    assert html =~ "project_id=#{project.id}"

    {:ok, _completed} = Operations.complete_task(task, authorize?: false)
    assert render(view) =~ "Completed"
  end

  test "work item and work order pages render task panels", %{conn: conn} do
    {:ok, organization} =
      Operations.create_organization(%{
        name: "Northwind Automation",
        organization_kind: :business,
        status: :prospect
      })

    {:ok, project} =
      Execution.create_project(%{organization_id: organization.id, name: "Summit upgrade"})

    {:ok, work_item} =
      Execution.create_work_item(%{project_id: project.id, title: "Zone 2 valves"})

    {:ok, work_order} =
      Execution.create_work_order(%{
        organization_id: organization.id,
        project_id: project.id,
        title: "Tuesday site visit"
      })

    {:ok, _task} =
      Operations.create_task(%{title: "Order valves", work_item_id: work_item.id})

    {:ok, _wi_view, wi_html} = live(conn, ~p"/execution/work-items/#{work_item}")
    assert wi_html =~ "Order valves"
    assert wi_html =~ "work_item_id=#{work_item.id}"

    {:ok, _wo_view, wo_html} = live(conn, ~p"/execution/work-orders/#{work_order}")
    assert wo_html =~ "work_order_id=#{work_order.id}"
  end
end
