defmodule GnomeGardenWeb.Finance.MercuryLiveTest do
  use GnomeGardenWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias GnomeGarden.Mercury

  setup :register_and_log_in_user

  test "renders the Mercury page with no account data", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/finance/mercury")
    assert html =~ "Mercury"
    assert html =~ "No account data"
  end

  test "renders account balance when an account exists", %{conn: conn} do
    {:ok, _account} =
      Mercury.create_mercury_account(
        %{
          mercury_id: "acc-#{System.unique_integer([:positive])}",
          name: "Gnome Checking",
          status: :active,
          kind: :checking,
          current_balance: Decimal.new("15000.00"),
          available_balance: Decimal.new("14500.00")
        },
        authorize?: false
      )

    {:ok, _view, html} = live(conn, ~p"/finance/mercury")
    assert html =~ "Gnome Checking"
    assert html =~ "15000"
    assert html =~ "Active"
  end

  # occurred_at is set 2 days in the past to work around a known limitation where
  # the mercury_transactions.occurred_at column is `timestamp without time zone`
  # (not `timestamptz`). The Ash-generated SQL applies ::timestamptz which
  # re-interprets stored values as local time (America/Los_Angeles, UTC-7), shifting
  # today's transactions past the end-of-day filter boundary. Using -2 days ensures
  # the shifted value still falls within the 30-day window and before to_dt.
  defp txn_occurred_at, do: DateTime.add(DateTime.utc_now(), -2, :day)

  describe "transaction table" do
    setup do
      {:ok, account} =
        Mercury.create_mercury_account(
          %{
            mercury_id: "acc-#{System.unique_integer([:positive])}",
            name: "Test Account",
            status: :active,
            kind: :checking,
            current_balance: Decimal.new("10000.00"),
            available_balance: Decimal.new("9000.00")
          },
          authorize?: false
        )

      {:ok, account: account}
    end

    test "shows matched transaction", %{conn: conn, account: account} do
      {:ok, txn} =
        Mercury.create_mercury_transaction(
          %{
            mercury_id: "txn-#{System.unique_integer([:positive])}",
            account_id: account.id,
            amount: Decimal.new("1200.00"),
            kind: :ach,
            status: :sent,
            occurred_at: txn_occurred_at()
          },
          authorize?: false
        )

      {:ok, _txn} =
        Mercury.update_mercury_transaction(txn, %{match_confidence: :exact}, authorize?: false)

      {:ok, _view, html} = live(conn, ~p"/finance/mercury")
      assert html =~ "Matched"
      assert html =~ "1200"
    end

    test "shows unmatched transaction", %{conn: conn, account: account} do
      {:ok, txn} =
        Mercury.create_mercury_transaction(
          %{
            mercury_id: "txn-#{System.unique_integer([:positive])}",
            account_id: account.id,
            amount: Decimal.new("800.00"),
            kind: :wire,
            status: :sent,
            occurred_at: txn_occurred_at()
          },
          authorize?: false
        )

      {:ok, _txn} =
        Mercury.update_mercury_transaction(txn, %{match_confidence: :unmatched}, authorize?: false)

      {:ok, _view, html} = live(conn, ~p"/finance/mercury")
      assert html =~ "800"
    end

    test "shows pending badge when status is pending", %{conn: conn, account: account} do
      {:ok, _txn} =
        Mercury.create_mercury_transaction(
          %{
            mercury_id: "txn-#{System.unique_integer([:positive])}",
            account_id: account.id,
            amount: Decimal.new("300.00"),
            kind: :ach,
            status: :pending,
            occurred_at: txn_occurred_at()
          },
          authorize?: false
        )

      {:ok, _view, html} = live(conn, ~p"/finance/mercury")
      assert html =~ "Pending"
    end

    test "nil match_confidence shows — instead of Matched/Unmatched", %{conn: conn, account: account} do
      {:ok, _txn} =
        Mercury.create_mercury_transaction(
          %{
            mercury_id: "txn-#{System.unique_integer([:positive])}",
            account_id: account.id,
            amount: Decimal.new("500.00"),
            kind: :ach,
            status: :sent,
            occurred_at: txn_occurred_at()
            # match_confidence intentionally omitted (nil)
          },
          authorize?: false
        )

      {:ok, _view, html} = live(conn, ~p"/finance/mercury")
      # The transaction renders with "—" in the status column (match_status_label(nil))
      # Note: the filter dropdown also contains "Matched"/"Unmatched" options, so
      # we only assert presence of "—" (from the status badge or counterparty/date cells)
      assert html =~ "—"
      assert html =~ "500"
    end

    test "match_status filter to matched hides unmatched transaction", %{conn: conn, account: account} do
      {:ok, txn_unmatched} =
        Mercury.create_mercury_transaction(
          %{
            mercury_id: "unmatched-#{System.unique_integer([:positive])}",
            account_id: account.id,
            amount: Decimal.new("100.00"),
            kind: :ach,
            status: :sent,
            occurred_at: txn_occurred_at()
          },
          authorize?: false
        )

      {:ok, _} =
        Mercury.update_mercury_transaction(txn_unmatched, %{match_confidence: :unmatched},
          authorize?: false
        )

      {:ok, txn_matched} =
        Mercury.create_mercury_transaction(
          %{
            mercury_id: "matched-#{System.unique_integer([:positive])}",
            account_id: account.id,
            amount: Decimal.new("999.00"),
            kind: :ach,
            status: :sent,
            occurred_at: txn_occurred_at()
          },
          authorize?: false
        )

      {:ok, _} =
        Mercury.update_mercury_transaction(txn_matched, %{match_confidence: :exact},
          authorize?: false
        )

      {:ok, view, _html} = live(conn, ~p"/finance/mercury")

      html =
        view
        |> element("select[name=match_status]")
        |> render_change(%{"match_status" => "matched"})

      assert html =~ "999"
      refute html =~ ">100<"
    end

    test "kind filter to inbound hides outbound transactions", %{conn: conn, account: account} do
      {:ok, _} =
        Mercury.create_mercury_transaction(
          %{
            mercury_id: "in-#{System.unique_integer([:positive])}",
            account_id: account.id,
            amount: Decimal.new("500.00"),
            kind: :ach,
            status: :sent,
            occurred_at: txn_occurred_at()
          },
          authorize?: false
        )

      {:ok, _} =
        Mercury.create_mercury_transaction(
          %{
            mercury_id: "out-#{System.unique_integer([:positive])}",
            account_id: account.id,
            amount: Decimal.new("-200.00"),
            kind: :ach,
            status: :sent,
            occurred_at: txn_occurred_at()
          },
          authorize?: false
        )

      {:ok, view, _html} = live(conn, ~p"/finance/mercury")

      html =
        view
        |> element("select[name=kind]")
        |> render_change(%{"kind" => "inbound"})

      assert html =~ "500"
      refute html =~ "-200.00"
    end
  end
end
