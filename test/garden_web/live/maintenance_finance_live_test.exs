defmodule GnomeGardenWeb.MaintenanceFinanceLiveTest do
  use GnomeGardenWeb.ConnCase

  import Phoenix.LiveViewTest

  alias GnomeGarden.Commercial
  alias GnomeGarden.Execution
  alias GnomeGarden.Finance
  alias GnomeGarden.Operations

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
end
