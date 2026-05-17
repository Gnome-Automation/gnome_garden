defmodule GnomeGardenWeb.ClientPortal.InvoiceLiveTest do
  use GnomeGardenWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias GnomeGarden.Finance

  setup :register_and_log_in_client_user

  setup %{organization: org} do
    invoice = Ash.Seed.seed!(GnomeGarden.Finance.Invoice, %{
      organization_id: org.id,
      invoice_number: "INV-0042",
      status: :issued,
      total_amount: Decimal.new("500.00"),
      balance_amount: Decimal.new("500.00")
    })
    {:ok, invoice: invoice}
  end

  test "invoice list shows invoices for client's org", %{conn: conn, invoice: inv} do
    {:ok, _view, html} = live(conn, ~p"/portal/invoices")
    assert html =~ "INV-0042"
  end

  test "invoice detail shows ACH payment instructions", %{conn: conn, invoice: inv} do
    {:ok, _view, html} = live(conn, ~p"/portal/invoices/#{inv.id}")
    assert html =~ "INV-0042"
    assert html =~ "ACH"
  end

  test "cannot access another org's invoice", %{conn: conn} do
    other_org = Ash.Seed.seed!(GnomeGarden.Operations.Organization, %{name: "Other"})
    other_invoice = Ash.Seed.seed!(GnomeGarden.Finance.Invoice, %{
      organization_id: other_org.id,
      invoice_number: "INV-9999",
      status: :issued,
      total_amount: Decimal.new("100.00"),
      balance_amount: Decimal.new("100.00")
    })

    assert {:error, _} = live(conn, ~p"/portal/invoices/#{other_invoice.id}")
  end
end
