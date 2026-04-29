defmodule GnomeGarden.Mercury.PaymentMatcherWorkerTest do
  use GnomeGarden.DataCase, async: true
  use Oban.Testing, repo: GnomeGarden.Repo

  alias GnomeGarden.Mercury
  alias GnomeGarden.Finance
  alias GnomeGarden.Operations
  alias GnomeGarden.Mercury.PaymentMatcherWorker

  setup do
    {:ok, org} =
      Operations.create_organization(%{
        name: "Client Co #{System.unique_integer([:positive])}",
        organization_kind: :business
      })

    {:ok, account} =
      Mercury.create_mercury_account(%{
        mercury_id: "acct-matcher-#{System.unique_integer([:positive])}",
        name: "GnomeGarden Checking",
        status: :active,
        kind: :checking
      })

    %{org: org, account: account}
  end

  defp issued_invoice(org, amount, invoice_number \\ nil) do
    inv_number = invoice_number || "INV-#{System.unique_integer([:positive])}"

    {:ok, invoice} =
      Finance.create_invoice(%{
        organization_id: org.id,
        invoice_number: inv_number,
        currency_code: "USD",
        total_amount: amount,
        balance_amount: amount
      })

    {:ok, issued} = Finance.issue_invoice(invoice)
    issued
  end

  defp mercury_transaction(account, amount, memo \\ "") do
    {:ok, txn} =
      Mercury.create_mercury_transaction(%{
        account_id: account.id,
        mercury_id: "txn-#{System.unique_integer([:positive])}",
        amount: amount,
        kind: :wire,
        status: :sent,
        external_memo: memo,
        occurred_at: DateTime.utc_now()
      })

    txn
  end

  defp run_worker(txn) do
    PaymentMatcherWorker.perform(%Oban.Job{args: %{"transaction_id" => txn.id}})
  end

  # --- Exact match via invoice number ---

  test "exact match via invoice number in memo marks invoice paid", %{org: org, account: account} do
    invoice = issued_invoice(org, Decimal.new("1000.00"), "INV-2026-TEST-001")
    txn = mercury_transaction(account, Decimal.new("1000.00"), "Payment for INV-2026-TEST-001")

    assert :ok = run_worker(txn)

    {:ok, updated_invoice} = Finance.get_invoice(invoice.id)
    assert updated_invoice.status == :paid

    {:ok, updated_txn} = Mercury.get_mercury_transaction(txn.id)
    assert updated_txn.match_confidence == :exact
  end

  # --- Exact match via amount + client alias ---

  test "exact match via amount and client alias marks invoice paid", %{org: org, account: account} do
    {:ok, _alias} =
      Mercury.create_client_bank_alias(%{
        counterparty_name_fragment: "CLIENT CO",
        organization_id: org.id
      })

    invoice = issued_invoice(org, Decimal.new("500.00"))

    {:ok, txn} =
      Mercury.create_mercury_transaction(%{
        account_id: account.id,
        mercury_id: "txn-alias-#{System.unique_integer([:positive])}",
        amount: Decimal.new("500.00"),
        kind: :wire,
        status: :sent,
        counterparty_name: "CLIENT CO INC",
        occurred_at: DateTime.utc_now()
      })

    assert :ok = run_worker(txn)

    {:ok, updated} = Finance.get_invoice(invoice.id)
    assert updated.status == :paid
  end

  # --- Partial payment ---

  test "partial payment transitions invoice to :partial", %{org: org, account: account} do
    invoice = issued_invoice(org, Decimal.new("1000.00"), "INV-PARTIAL-001")
    txn = mercury_transaction(account, Decimal.new("600.00"), "Partial INV-PARTIAL-001")

    assert :ok = run_worker(txn)

    {:ok, updated} = Finance.get_invoice(invoice.id, load: [:applied_amount])
    assert updated.status == :partial
    assert Decimal.equal?(updated.balance_amount, Decimal.new("400.00"))
  end

  # --- Underpayment tolerance ---

  test "payment within tolerance marks invoice paid", %{org: org, account: account} do
    Application.put_env(:gnome_garden, :payment_matching, underpayment_tolerance: "1.00")
    on_exit(fn -> Application.delete_env(:gnome_garden, :payment_matching) end)

    invoice = issued_invoice(org, Decimal.new("1000.00"), "INV-TOLERANCE-001")
    # $0.50 short — within $1.00 tolerance
    txn = mercury_transaction(account, Decimal.new("999.50"), "INV-TOLERANCE-001")

    assert :ok = run_worker(txn)

    {:ok, updated} = Finance.get_invoice(invoice.id)
    assert updated.status == :paid
  end

  # --- No match ---

  test "unmatched transaction sets match_confidence to :unmatched", %{account: account} do
    txn = mercury_transaction(account, Decimal.new("9999.00"))

    assert :ok = run_worker(txn)

    {:ok, updated} = Mercury.get_mercury_transaction(txn.id)
    assert updated.match_confidence == :unmatched
  end

  test "non-existent transaction_id returns :ok without crashing" do
    job = %Oban.Job{args: %{"transaction_id" => Ash.UUID.generate()}}
    assert :ok = PaymentMatcherWorker.perform(job)
  end
end
