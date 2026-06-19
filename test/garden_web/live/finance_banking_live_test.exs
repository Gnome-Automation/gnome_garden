defmodule GnomeGardenWeb.FinanceBankingLiveTest do
  @moduledoc """
  Smoke tests: every finance/banking LiveView mounts and renders without
  crashing (catches HEEX field/enum mismatches that aren't compile-checked).
  """
  use GnomeGardenWeb.ConnCase

  setup :register_and_log_in_user

  import Phoenix.LiveViewTest

  alias GnomeGarden.Banking

  describe "index / dashboard routes render with empty data" do
    test "finance overview", %{conn: conn} do
      assert {:ok, _view, _html} = live(conn, ~p"/finance")
    end

    test "banking dashboard", %{conn: conn} do
      assert {:ok, _view, _html} = live(conn, ~p"/finance/banking")
    end

    test "banking review queue", %{conn: conn} do
      assert {:ok, _view, _html} = live(conn, ~p"/finance/banking/review")
    end

    test "bank rules", %{conn: conn} do
      assert {:ok, _view, _html} = live(conn, ~p"/finance/banking/rules")
    end

    test "banking sync runs", %{conn: conn} do
      assert {:ok, _view, _html} = live(conn, ~p"/finance/banking/sync-runs")
    end

    test "receivables", %{conn: conn} do
      assert {:ok, _view, _html} = live(conn, ~p"/finance/receivables")
    end

    test "work to bill", %{conn: conn} do
      assert {:ok, _view, _html} = live(conn, ~p"/finance/work-to-bill")
    end
  end

  describe "detail routes render with a synced account + transaction" do
    setup do
      {:ok, conn} = Banking.create_bank_connection(%{provider: :mercury, environment: :sandbox, name: "M"})

      {:ok, account} =
        Banking.upsert_bank_account(%{
          bank_connection_id: conn.id, provider: :mercury,
          provider_account_id: "x#{System.unique_integer([:positive])}",
          name: "Checking", kind: :checking, current_balance: Money.new!(:USD, "1000")
        })

      {:ok, txn} =
        Banking.upsert_bank_transaction(%{
          bank_account_id: account.id, provider: :mercury,
          provider_transaction_id: "t#{System.unique_integer([:positive])}",
          amount: Money.new!(:USD, "250"), direction: :credit, status: :sent,
          counterparty_name: "ACME CORP", occurred_at: DateTime.utc_now()
        })

      %{account: account, txn: txn}
    end

    test "bank account detail", %{conn: conn, account: account} do
      assert {:ok, _view, _html} = live(conn, ~p"/finance/banking/accounts/#{account.id}")
    end

    test "bank transaction detail", %{conn: conn, txn: txn} do
      assert {:ok, _view, _html} = live(conn, ~p"/finance/banking/transactions/#{txn.id}")
    end
  end
end
