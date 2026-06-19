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
  alias GnomeGarden.Finance
  alias GnomeGarden.Ledger

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

  # Regression: work-to-bill rendered an approved billable time entry's labor value
  # via `Decimal.mult(decimal, %Money{})`, which raised. Labor value now comes from
  # the TimeEntry.billable_amount calculation. 60 min @ $100/hr == $100.00.
  test "work-to-bill shows billable labor value without crashing", %{conn: conn} do
    org =
      GnomeGarden.Operations.Organization
      |> Ash.Changeset.for_create(:create, %{
        name: "WTB Org #{System.unique_integer([:positive])}",
        organization_kind: :business
      })
      |> Ash.create!(domain: GnomeGarden.Operations)

    agreement =
      GnomeGarden.Commercial.Agreement
      |> Ash.Changeset.for_create(:create, %{
        organization_id: org.id,
        name: "WTB Agreement #{System.unique_integer([:positive])}",
        billing_cycle: :monthly,
        next_billing_date: Date.utc_today()
      })
      |> Ash.create!(domain: GnomeGarden.Commercial)
      |> Ash.Changeset.for_update(:activate, %{})
      |> Ash.update!(domain: GnomeGarden.Commercial)

    {:ok, user} =
      GnomeGarden.Accounts.create_user_with_password(%{
        email: "wtb-#{System.unique_integer([:positive])}@example.com",
        password: "valid-password-1234",
        password_confirmation: "valid-password-1234"
      })

    tm =
      Ash.Seed.seed!(GnomeGarden.Operations.TeamMember, %{
        user_id: user.id,
        display_name: "WTB Member #{System.unique_integer([:positive])}",
        role: :admin,
        status: :active
      })

    GnomeGarden.Finance.TimeEntry
    |> Ash.Changeset.for_create(:create, %{
      organization_id: org.id,
      agreement_id: agreement.id,
      member_team_member_id: tm.id,
      work_date: Date.utc_today(),
      description: "Billable work",
      minutes: 60,
      billable: true,
      bill_rate: Money.new!(:USD, "100.00")
    })
    |> Ash.create!(domain: Finance)
    |> Ash.Changeset.for_update(:submit, %{})
    |> Ash.update!(domain: Finance)
    |> Ash.Changeset.for_update(:approve, %{})
    |> Ash.update!(domain: Finance)

    {:ok, _view, html} = live(conn, ~p"/finance/work-to-bill")
    assert html =~ "$100.00"
  end

  # Regression: the match card referenced fields that do not exist on
  # BankTransactionMatch (payment/invoice/match_source/notes) and gated the
  # accept/reject buttons on :suggested rather than the real :proposed status,
  # so a proposed match crashed the page and its buttons never rendered.
  test "bank transaction detail renders a proposed match with accept/reject + confidence",
       %{conn: conn, txn: txn} do
    {:ok, cash} = Ledger.get_account_by_number("1000")
    {:ok, ar} = Ledger.get_account_by_number("1100")

    {:ok, entry} =
      Ledger.post_journal_entry(%{
        date: Date.utc_today(),
        description: "Client deposit",
        entry_type: :payment_received,
        lines: [
          %{account_id: cash.id, debit: Money.new!(:USD, "250")},
          %{account_id: ar.id, credit: Money.new!(:USD, "250")}
        ]
      })

    {:ok, _match} =
      Banking.create_bank_transaction_match(%{
        bank_transaction_id: txn.id,
        journal_entry_id: entry.id,
        amount: Money.new!(:USD, "250"),
        confidence: Decimal.new("1.0")
      })

    {:ok, view, html} = live(conn, ~p"/finance/banking/transactions/#{txn.id}")

    assert html =~ "Accept"
    assert html =~ "Reject"
    assert html =~ "100% match"
    assert html =~ "Client deposit"

    # The accept button is now reachable and the handler works end to end.
    {:ok, [proposed]} = Banking.list_bank_transaction_matches_for_transaction(txn.id)
    render_click(view, "accept_match", %{"id" => proposed.id})

    {:ok, [accepted]} = Banking.list_bank_transaction_matches_for_transaction(txn.id)
    assert accepted.status == :accepted
  end
end
