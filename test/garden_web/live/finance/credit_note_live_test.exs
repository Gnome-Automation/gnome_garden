defmodule GnomeGardenWeb.Finance.CreditNoteLiveTest do
  use GnomeGardenWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias GnomeGarden.Finance
  alias GnomeGarden.Operations

  setup do
    {:ok, org} =
      Operations.create_organization(%{
        name: "CN Live Org #{System.unique_integer([:positive])}",
        organization_kind: :business
      })

    {:ok, person} =
      Operations.create_person(%{
        first_name: "Bill",
        last_name: "Payer",
        email: "live@acme.com"
      })

    Operations.create_organization_affiliation(%{
      organization_id: org.id,
      person_id: person.id
    })

    {:ok, invoice} =
      Finance.create_invoice(%{
        organization_id: org.id,
        invoice_number: "INV-LIVE-#{System.unique_integer([:positive])}",
        currency_code: "USD",
        total_amount: Decimal.new("750.00"),
        balance_amount: Decimal.new("750.00")
      })

    {:ok, invoice} = Finance.issue_invoice(invoice)
    {:ok, invoice} = Finance.void_invoice(invoice)

    %{org: org, invoice: invoice}
  end

  test "voided invoice show page displays Create Credit Note button", %{conn: conn, invoice: invoice} do
    {:ok, _view, html} = live(conn, ~p"/finance/invoices/#{invoice.id}")
    assert html =~ "Create Credit Note"
  end

  test "clicking Create Credit Note redirects to credit note show page", %{conn: conn, invoice: invoice} do
    {:ok, view, _html} = live(conn, ~p"/finance/invoices/#{invoice.id}")

    # push_navigate triggers a live_redirect — capture it and assert on the path
    {:error, {:live_redirect, %{to: path}}} =
      view |> element("button", "Create Credit Note") |> render_click()

    assert path =~ "/finance/credit-notes/"
  end

  test "credit note show page renders CN number", %{conn: conn, org: org, invoice: invoice} do
    n = Finance.next_sequence_value("credit_notes")
    cn_number = Finance.format_credit_note_number(n)

    {:ok, cn} =
      Finance.create_credit_note(%{
        credit_note_number: cn_number,
        invoice_id: invoice.id,
        organization_id: org.id,
        total_amount: Decimal.new("-750.00"),
        currency_code: "USD"
      })

    {:ok, _view, html} = live(conn, ~p"/finance/credit-notes/#{cn.id}")
    assert html =~ cn_number
  end

  test "credit note index page renders", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/finance/credit-notes")
    assert html =~ "Credit Notes"
  end
end
