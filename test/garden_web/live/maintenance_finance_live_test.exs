defmodule GnomeGardenWeb.MaintenanceFinanceLiveTest do
  use GnomeGardenWeb.ConnCase

  import Phoenix.LiveViewTest

  alias GnomeGarden.Commercial
  alias GnomeGarden.Execution
  alias GnomeGarden.Finance
  alias GnomeGarden.Operations
  alias GnomeGarden.Repo

  test "maintenance plan routes render", %{conn: conn} do
    {:ok, organization} =
      Operations.create_organization(%{
        name: "Atlas Service Group",
        organization_kind: :business,
        status: :active
      })

    {:ok, asset} =
      Operations.create_asset(%{
        organization_id: organization.id,
        asset_tag: "AST-300",
        name: "Boiler PLC",
        asset_type: :controller
      })

    {:ok, maintenance_plan} =
      Execution.create_maintenance_plan(%{
        organization_id: organization.id,
        asset_id: asset.id,
        name: "Quarterly PLC Inspection",
        interval_unit: :quarter,
        interval_value: 1
      })

    {:ok, index_view, index_html} = live(conn, ~p"/execution/maintenance-plans")
    assert has_element?(index_view, "#maintenance-plans")
    assert index_html =~ maintenance_plan.name

    {:ok, show_view, _show_html} =
      live(conn, ~p"/execution/maintenance-plans/#{maintenance_plan}")

    assert render(show_view) =~ maintenance_plan.name

    {:ok, form_view, _form_html} =
      live(conn, ~p"/execution/maintenance-plans/new?asset_id=#{asset.id}")

    assert has_element?(form_view, "#maintenance-plan-form")
  end

  test "payment routes render", %{conn: conn} do
    {:ok, organization} =
      Operations.create_organization(%{
        name: "Comet Controls",
        organization_kind: :business,
        status: :active
      })

    {:ok, payment} =
      Finance.create_payment(%{
        organization_id: organization.id,
        payment_number: "PAY-100",
        received_on: ~D[2026-04-18],
        amount: Decimal.new("1200.00")
      })

    {:ok, index_view, index_html} = live(conn, ~p"/finance/payments")
    assert has_element?(index_view, "#payments")
    assert index_html =~ payment.payment_number

    {:ok, show_view, _show_html} = live(conn, ~p"/finance/payments/#{payment}")
    assert render(show_view) =~ payment.payment_number

    {:ok, form_view, _form_html} = live(conn, ~p"/finance/payments/new")
    assert has_element?(form_view, "#payment-form")
  end

  test "payment application routes render", %{conn: conn} do
    {:ok, organization} =
      Operations.create_organization(%{
        name: "Vector Fabrication",
        organization_kind: :business,
        status: :active
      })

    {:ok, agreement} =
      Commercial.create_agreement(%{
        organization_id: organization.id,
        name: "Vector Service Agreement",
        agreement_type: :service
      })

    {:ok, invoice} =
      Finance.create_invoice(%{
        organization_id: organization.id,
        agreement_id: agreement.id,
        invoice_number: "INV-200",
        due_on: ~D[2026-05-10],
        subtotal: Decimal.new("1000.00"),
        tax_total: Decimal.new("0.00"),
        total_amount: Decimal.new("1000.00"),
        balance_amount: Decimal.new("1000.00")
      })

    {:ok, payment} =
      Finance.create_payment(%{
        organization_id: organization.id,
        agreement_id: agreement.id,
        payment_number: "PAY-200",
        received_on: ~D[2026-04-18],
        amount: Decimal.new("1000.00")
      })

    {:ok, payment_application} =
      Finance.create_payment_application(%{
        payment_id: payment.id,
        invoice_id: invoice.id,
        amount: Decimal.new("1000.00"),
        applied_on: ~D[2026-04-18]
      })

    {:ok, index_view, index_html} = live(conn, ~p"/finance/payment-applications")
    assert has_element?(index_view, "#payment-applications")
    assert index_html =~ payment.payment_number

    {:ok, show_view, _show_html} =
      live(conn, ~p"/finance/payment-applications/#{payment_application}")

    assert render(show_view) =~ invoice.invoice_number

    {:ok, form_view, _form_html} =
      live(
        conn,
        ~p"/finance/payment-applications/new?payment_id=#{payment.id}&invoice_id=#{invoice.id}"
      )

    assert has_element?(form_view, "#payment-application-form")
  end

  test "time entry routes render", %{conn: conn} do
    user =
      Repo.insert!(%GnomeGarden.Accounts.User{
        id: Ecto.UUID.generate(),
        email: "timekeeper@example.com"
      })

    {:ok, organization} =
      Operations.create_organization(%{
        name: "Helix Integration",
        organization_kind: :business,
        status: :active
      })

    {:ok, agreement} =
      Commercial.create_agreement(%{
        organization_id: organization.id,
        name: "Helix Support Agreement",
        agreement_type: :service
      })

    {:ok, project} =
      Execution.create_project(%{
        organization_id: organization.id,
        agreement_id: agreement.id,
        name: "Helix Web Portal",
        project_type: :software_delivery
      })

    {:ok, work_item} =
      Execution.create_work_item(%{
        project_id: project.id,
        title: "Portal integration",
        kind: :task,
        discipline: :web
      })

    {:ok, time_entry} =
      Finance.create_time_entry(%{
        organization_id: organization.id,
        agreement_id: agreement.id,
        project_id: project.id,
        work_item_id: work_item.id,
        member_user_id: user.id,
        work_date: ~D[2026-04-18],
        minutes: 120,
        description: "Integration buildout"
      })

    {:ok, index_view, index_html} = live(conn, ~p"/finance/time-entries")
    assert has_element?(index_view, "#time-entries")
    assert index_html =~ time_entry.description

    {:ok, show_view, _show_html} = live(conn, ~p"/finance/time-entries/#{time_entry}")
    assert render(show_view) =~ time_entry.description

    {:ok, form_view, _form_html} =
      live(
        conn,
        ~p"/finance/time-entries/new?organization_id=#{organization.id}&project_id=#{project.id}&work_item_id=#{work_item.id}"
      )

    assert has_element?(form_view, "#time-entry-form")
  end

  test "expense routes render", %{conn: conn} do
    user =
      Repo.insert!(%GnomeGarden.Accounts.User{
        id: Ecto.UUID.generate(),
        email: "expenses@example.com"
      })

    {:ok, organization} =
      Operations.create_organization(%{
        name: "Prairie Controls",
        organization_kind: :business,
        status: :active
      })

    {:ok, agreement} =
      Commercial.create_agreement(%{
        organization_id: organization.id,
        name: "Prairie Field Service",
        agreement_type: :service
      })

    {:ok, work_order} =
      Execution.create_work_order(%{
        organization_id: organization.id,
        agreement_id: agreement.id,
        title: "Field commissioning visit",
        work_type: :commissioning
      })

    {:ok, expense} =
      Finance.create_expense(%{
        organization_id: organization.id,
        agreement_id: agreement.id,
        work_order_id: work_order.id,
        incurred_by_user_id: user.id,
        incurred_on: ~D[2026-04-18],
        category: :travel,
        description: "Mileage and tolls",
        amount: Decimal.new("84.50")
      })

    {:ok, index_view, index_html} = live(conn, ~p"/finance/expenses")
    assert has_element?(index_view, "#expenses")
    assert index_html =~ expense.description

    {:ok, show_view, _show_html} = live(conn, ~p"/finance/expenses/#{expense}")
    assert render(show_view) =~ expense.description

    {:ok, form_view, _form_html} =
      live(
        conn,
        ~p"/finance/expenses/new?organization_id=#{organization.id}&work_order_id=#{work_order.id}"
      )

    assert has_element?(form_view, "#expense-form")
  end
end
