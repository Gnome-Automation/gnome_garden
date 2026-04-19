defmodule GnomeGardenWeb.CommercialExecutionLiveTest do
  use GnomeGardenWeb.ConnCase

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

    {:ok, index_view, index_html} = live(conn, ~p"/commercial/proposals")
    assert has_element?(index_view, "#proposals")
    assert index_html =~ proposal.name

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

    {:ok, index_view, index_html} = live(conn, ~p"/commercial/agreements")
    assert has_element?(index_view, "#agreements")
    assert index_html =~ agreement.name

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

    {:ok, index_view, index_html} = live(conn, ~p"/execution/projects")
    assert has_element?(index_view, "#projects")
    assert index_html =~ project.name

    {:ok, show_view, _show_html} = live(conn, ~p"/execution/projects/#{project}")
    assert render(show_view) =~ project.name

    {:ok, form_view, _form_html} =
      live(conn, ~p"/execution/projects/new?agreement_id=#{active_agreement.id}")

    assert has_element?(form_view, "#project-form")
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

    {:ok, index_view, index_html} = live(conn, ~p"/commercial/change-orders")
    assert has_element?(index_view, "#change-orders")
    assert index_html =~ change_order.title

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

    {:ok, index_view, index_html} = live(conn, ~p"/finance/invoices")
    assert has_element?(index_view, "#invoices")
    assert index_html =~ invoice.invoice_number

    {:ok, show_view, _show_html} = live(conn, ~p"/finance/invoices/#{invoice}")
    assert render(show_view) =~ invoice.invoice_number

    {:ok, form_view, _form_html} = live(conn, ~p"/finance/invoices/new")
    assert has_element?(form_view, "#invoice-form")
  end
end
