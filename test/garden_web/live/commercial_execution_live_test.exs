defmodule GnomeGardenWeb.CommercialExecutionLiveTest do
  use GnomeGardenWeb.ConnCase

  setup :register_and_log_in_user

  import Phoenix.LiveViewTest

  alias GnomeGarden.Commercial
  alias GnomeGarden.Execution
  alias GnomeGarden.Finance
  alias GnomeGarden.Operations

  test "proposal routes render", %{conn: conn} do
    {:ok, organization} =
      Operations.create_organization(%{
        name: "Orbit Controls",
        organization_kind: :business,
        status: :prospect
      })

    {:ok, pursuit} =
      Commercial.create_pursuit(%{
        organization_id: organization.id,
        name: "Orbit SCADA migration",
        pursuit_type: :bid_response
      })

    {:ok, proposal} =
      Commercial.create_proposal(%{
        pursuit_id: pursuit.id,
        organization_id: organization.id,
        proposal_number: "PROP-100",
        name: "Orbit Migration Proposal"
      })

    {:ok, _index_view, _index_html} = live(conn, ~p"/commercial/proposals")

    {:ok, show_view, _show_html} = live(conn, ~p"/commercial/proposals/#{proposal}")
    assert render(show_view) =~ proposal.proposal_number

    {:ok, form_view, _form_html} =
      live(conn, ~p"/commercial/proposals/new?pursuit_id=#{pursuit.id}")

    assert has_element?(form_view, "#proposal-form")
  end

  test "agreement routes render", %{conn: conn} do
    {:ok, organization} =
      Operations.create_organization(%{
        name: "Harbor Systems",
        organization_kind: :business,
        status: :active
      })

    {:ok, pursuit} =
      Commercial.create_pursuit(%{
        organization_id: organization.id,
        name: "Harbor dashboard build",
        pursuit_type: :existing_account
      })

    {:ok, proposal} =
      Commercial.create_proposal(%{
        pursuit_id: pursuit.id,
        organization_id: organization.id,
        proposal_number: "PROP-200",
        name: "Harbor Proposal"
      })

    {:ok, issued_proposal} = Commercial.issue_proposal(proposal)
    {:ok, accepted_proposal} = Commercial.accept_proposal(issued_proposal)

    {:ok, agreement} =
      Commercial.create_agreement(%{
        organization_id: organization.id,
        name: "Harbor Service Agreement",
        agreement_type: :service
      })

    {:ok, _index_view, _index_html} = live(conn, ~p"/commercial/agreements")

    {:ok, show_view, _show_html} = live(conn, ~p"/commercial/agreements/#{agreement}")
    assert render(show_view) =~ agreement.name

    {:ok, form_view, _form_html} =
      live(conn, ~p"/commercial/agreements/new?proposal_id=#{accepted_proposal.id}")

    assert has_element?(form_view, "#agreement-form")
  end

  test "project routes render", %{conn: conn} do
    {:ok, organization} =
      Operations.create_organization(%{
        name: "Summit Packaging",
        organization_kind: :business,
        status: :active
      })

    {:ok, agreement} =
      Commercial.create_agreement(%{
        organization_id: organization.id,
        name: "Summit Project Agreement",
        agreement_type: :project
      })

    {:ok, active_agreement} = Commercial.activate_agreement(agreement)

    {:ok, project} =
      Execution.create_project(%{
        organization_id: organization.id,
        agreement_id: active_agreement.id,
        name: "Summit Line Upgrade",
        project_type: :upgrade
      })

    {:ok, _index_view, _index_html} = live(conn, ~p"/execution/projects")

    {:ok, show_view, _show_html} = live(conn, ~p"/execution/projects/#{project}")
    assert render(show_view) =~ project.name

    {:ok, form_view, _form_html} =
      live(conn, ~p"/execution/projects/new?agreement_id=#{active_agreement.id}")

    assert has_element?(form_view, "#project-form")
  end

  test "work item routes render", %{conn: conn} do
    {:ok, organization} =
      Operations.create_organization(%{
        name: "Northwind Automation",
        organization_kind: :business,
        status: :active
      })

    {:ok, agreement} =
      Commercial.create_agreement(%{
        organization_id: organization.id,
        name: "Northwind Delivery Agreement",
        agreement_type: :project
      })

    {:ok, project} =
      Execution.create_project(%{
        organization_id: organization.id,
        agreement_id: agreement.id,
        name: "Northwind Controls Upgrade",
        project_type: :upgrade
      })

    {:ok, work_item} =
      Execution.create_work_item(%{
        project_id: project.id,
        title: "Panel design review",
        kind: :task,
        discipline: :automation
      })

    {:ok, _index_view, _index_html} = live(conn, ~p"/execution/work-items")

    {:ok, show_view, _show_html} = live(conn, ~p"/execution/work-items/#{work_item}")
    assert render(show_view) =~ work_item.title

    {:ok, form_view, _form_html} =
      live(conn, ~p"/execution/work-items/new?project_id=#{project.id}")

    assert has_element?(form_view, "#work-item-form")
  end

  test "assignment routes render", %{conn: conn, current_team_member: team_member} do
    {:ok, organization} =
      Operations.create_organization(%{
        name: "Atlas Dispatch",
        organization_kind: :business,
        status: :active
      })

    {:ok, agreement} =
      Commercial.create_agreement(%{
        organization_id: organization.id,
        name: "Atlas Dispatch Agreement",
        agreement_type: :project
      })

    {:ok, project} =
      Execution.create_project(%{
        organization_id: organization.id,
        agreement_id: agreement.id,
        name: "Atlas Site Upgrade",
        project_type: :upgrade
      })

    {:ok, work_item} =
      Execution.create_work_item(%{
        project_id: project.id,
        title: "Commissioning prep",
        kind: :task,
        discipline: :commissioning
      })

    {:ok, assignment} =
      Execution.create_assignment(%{
        organization_id: organization.id,
        project_id: project.id,
        work_item_id: work_item.id,
        assigned_team_member_id: team_member.id,
        title: "Commissioning visit",
        scheduled_start_at: ~U[2026-04-21 17:00:00Z]
      })

    {:ok, _index_view, _index_html} = live(conn, ~p"/execution/assignments")

    {:ok, show_view, _show_html} = live(conn, ~p"/execution/assignments/#{assignment}")
    assert render(show_view) =~ assignment.title

    {:ok, form_view, _form_html} =
      live(
        conn,
        ~p"/execution/assignments/new?organization_id=#{organization.id}&project_id=#{project.id}&work_item_id=#{work_item.id}"
      )

    assert has_element?(form_view, "#assignment-form")
  end

  test "change order routes render", %{conn: conn} do
    {:ok, organization} =
      Operations.create_organization(%{
        name: "Cedar Robotics",
        organization_kind: :business,
        status: :active
      })

    {:ok, agreement} =
      Commercial.create_agreement(%{
        organization_id: organization.id,
        name: "Cedar Upgrade Agreement",
        agreement_type: :project
      })

    {:ok, change_order} =
      Commercial.create_change_order(%{
        agreement_id: agreement.id,
        organization_id: organization.id,
        change_order_number: "CO-100",
        title: "Panel scope increase"
      })

    {:ok, _index_view, _index_html} = live(conn, ~p"/commercial/change-orders")

    {:ok, show_view, _show_html} = live(conn, ~p"/commercial/change-orders/#{change_order}")
    assert render(show_view) =~ change_order.change_order_number

    {:ok, form_view, _form_html} =
      live(conn, ~p"/commercial/change-orders/new?agreement_id=#{agreement.id}")

    assert has_element?(form_view, "#change-order-form")
  end

  test "invoice routes render", %{conn: conn} do
    {:ok, organization} =
      Operations.create_organization(%{
        name: "Blue Mesa Systems",
        organization_kind: :business,
        status: :active
      })

    {:ok, agreement} =
      Commercial.create_agreement(%{
        organization_id: organization.id,
        name: "Blue Mesa Support Agreement",
        agreement_type: :service
      })

    {:ok, invoice} =
      Finance.create_invoice(%{
        organization_id: organization.id,
        agreement_id: agreement.id,
        invoice_number: "INV-100",
        due_on: ~D[2026-05-01],
        subtotal: Decimal.new("1000.00"),
        tax_total: Decimal.new("0.00"),
        total_amount: Decimal.new("1000.00"),
        balance_amount: Decimal.new("1000.00")
      })

    {:ok, _index_view, _index_html} = live(conn, ~p"/finance/invoices")

    {:ok, show_view, _show_html} = live(conn, ~p"/finance/invoices/#{invoice}")
    assert render(show_view) =~ invoice.invoice_number

    {:ok, form_view, _form_html} = live(conn, ~p"/finance/invoices/new")
    assert has_element?(form_view, "#invoice-form")
  end
end
