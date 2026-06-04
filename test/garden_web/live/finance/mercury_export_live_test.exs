defmodule GnomeGardenWeb.Finance.MercuryExportLiveTest do
  use GnomeGardenWeb.ConnCase

  import Phoenix.LiveViewTest

  alias GnomeGarden.Mercury

  setup :register_and_log_in_user

  describe "Mercury export UI" do
    test "Export button renders on Mercury page", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/finance/mercury")
      assert html =~ "Export"
    end

    test "export form is hidden by default", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/finance/mercury")
      refute html =~ "batch-export"
    end

    test "clicking Export button shows the batch export form", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/finance/mercury")
      html = view |> element("button", "Export") |> render_click()
      assert html =~ "batch-export"
    end

    test "batch export form has from, to, status_filter, kind, and format inputs", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/finance/mercury")
      view |> element("button", "Export") |> render_click()
      html = render(view)
      assert html =~ ~s(name="from")
      assert html =~ ~s(name="to")
      assert html =~ ~s(name="status_filter")
      assert html =~ ~s(name="kind")
      assert html =~ ~s(name="format")
    end

    test "per-row export links appear for each transaction", %{conn: conn} do
      txn = insert_transaction()
      {:ok, _view, html} = live(conn, ~p"/finance/mercury")
      assert html =~ "/finance/mercury/transactions/#{txn.id}/export?format=csv"
    end
  end

  # --- Helpers ---

  # occurred_at is set 2 days in the past to work around a known limitation where
  # the mercury_transactions.occurred_at column is `timestamp without time zone`
  # (not `timestamptz`). The Ash-generated SQL applies ::timestamptz which
  # re-interprets stored values as local time, shifting today's transactions past
  # the end-of-day filter boundary. Using -2 days ensures the shifted value still
  # falls within the 30-day window and before to_dt.
  defp insert_transaction do
    {:ok, account} =
      Mercury.create_mercury_account(%{
        name: "Test Checking #{System.unique_integer([:positive])}",
        mercury_id: "acc-#{System.unique_integer([:positive])}",
        kind: :checking,
        status: :active,
        current_balance: Decimal.new("1000.00"),
        available_balance: Decimal.new("1000.00")
      }, authorize?: false)

    {:ok, txn} =
      Mercury.create_mercury_transaction(%{
        account_id: account.id,
        mercury_id: "txn-#{System.unique_integer([:positive])}",
        amount: Decimal.new("500.00"),
        kind: :ach,
        status: :sent,
        counterparty_name: "Test Client",
        occurred_at: DateTime.add(DateTime.utc_now(), -2, :day)
      }, authorize?: false)

    txn
  end
end
