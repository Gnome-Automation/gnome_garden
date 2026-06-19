defmodule GnomeGardenWeb.FinanceBankingLiveTest do
  @moduledoc """
  Smoke tests: every finance/banking LiveView mounts and renders without
  crashing — with real data seeded (a rule, a completed sync run, an account and
  transaction) so render paths that only fire on non-empty data are exercised.
  """
  use GnomeGardenWeb.ConnCase

  setup :register_and_log_in_user

  import Phoenix.LiveViewTest

  alias GnomeGarden.Banking

  setup do
    {:ok, conn} = Banking.create_bank_connection(%{provider: :mercury, environment: :sandbox, name: "M"})

    {:ok, account} =
      Banking.upsert_bank_account(%{
        bank_connection_id: conn.id, provider: :mercury,
        provider_account_id: "x#{System.unique_integer([:positive])}",
        name: "Checking", kind: :checking,
        current_balance: Money.new!(:USD, "1000"), available_balance: Money.new!(:USD, "1000"),
        account_number_last4: "3337"
      })

    {:ok, txn} =
      Banking.upsert_bank_transaction(%{
        bank_account_id: account.id, provider: :mercury,
        provider_transaction_id: "t#{System.unique_integer([:positive])}",
        amount: Money.new!(:USD, "250"), direction: :credit, status: :sent,
        counterparty_name: "ACME CORP", occurred_at: DateTime.utc_now()
      })

    {:ok, _rule} =
      Banking.create_bank_rule(%{name: "Client deposits", counterparty_contains: "ACME",
        direction: :credit, category: :customer_payment, match_behavior: :suggest})

    # A completed sync run with counts, and a failed one (exercises both render paths).
    {:ok, run} = Banking.start_bank_sync_run(%{bank_connection_id: conn.id, source: :scheduled})
    {:ok, _} = Banking.finish_bank_sync_run_success(run, %{accounts_synced: 1, transactions_synced: 1, accounts_seen_count: 1, transactions_seen_count: 1, transactions_created_count: 1})
    {:ok, failed} = Banking.start_bank_sync_run(%{bank_connection_id: conn.id, source: :scheduled})
    {:ok, _} = Banking.finish_bank_sync_run_failure(failed, %{error_message: ":unauthorized"})

    %{account: account, txn: txn}
  end

  for {label, path} <- [
        {"finance overview", "/finance"},
        {"banking dashboard", "/finance/banking"},
        {"banking review queue", "/finance/banking/review"},
        {"bank rules", "/finance/banking/rules"},
        {"banking sync runs", "/finance/banking/sync-runs"},
        {"receivables", "/finance/receivables"},
        {"work to bill", "/finance/work-to-bill"}
      ] do
    test "#{label} renders", %{conn: conn} do
      assert {:ok, _view, _html} = live(conn, unquote(path))
    end
  end

  test "bank account detail renders", %{conn: conn, account: account} do
    assert {:ok, _view, _html} = live(conn, ~p"/finance/banking/accounts/#{account.id}")
  end

  test "bank transaction detail renders", %{conn: conn, txn: txn} do
    assert {:ok, _view, _html} = live(conn, ~p"/finance/banking/transactions/#{txn.id}")
  end
end
