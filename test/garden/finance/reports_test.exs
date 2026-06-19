defmodule GnomeGarden.Finance.ReportsTest do
  use GnomeGarden.DataCase, async: true

  alias GnomeGarden.{Finance, Ledger, Operations}

  setup do
    {:ok, org} = Operations.create_organization(%{name: "Rpt Org #{System.unique_integer([:positive])}"})
    today = Date.utc_today()

    # Two issued invoices (1000 due today, 500 due 45 days ago) + a $300 payment on inv1.
    {:ok, inv1} =
      Finance.create_invoice(%{organization_id: org.id, invoice_number: "R1-#{System.unique_integer([:positive])}",
        currency_code: "USD", total_amount: Money.new!(:USD, "1000"), balance_amount: Money.new!(:USD, "1000"), due_on: today})

    {:ok, inv1} = Finance.issue_invoice(inv1)

    {:ok, inv2} =
      Finance.create_invoice(%{organization_id: org.id, invoice_number: "R2-#{System.unique_integer([:positive])}",
        currency_code: "USD", total_amount: Money.new!(:USD, "500"), balance_amount: Money.new!(:USD, "500"), due_on: Date.add(today, -45)})

    {:ok, _inv2} = Finance.issue_invoice(inv2)

    {:ok, payment} = Finance.create_payment(%{organization_id: org.id, received_on: today, amount: Money.new!(:USD, "300")})
    {:ok, _} = Finance.create_payment_application(%{payment_id: payment.id, invoice_id: inv1.id, amount: Money.new!(:USD, "300"), applied_on: today})

    %{today: today}
  end

  test "trial balance is balanced", %{today: today} do
    {:ok, tb} = Ledger.build_trial_balance(%{as_of: today})
    assert tb.balanced?
    assert Decimal.equal?(tb.total_debit, tb.total_credit)
    # Cash 300 + AR 1200 = debits 1500; Revenue 1500 = credits.
    assert Decimal.equal?(tb.total_debit, Decimal.new("1500"))
  end

  test "balance sheet balances (assets = liabilities + equity incl retained earnings)", %{today: today} do
    {:ok, bs} = Ledger.build_balance_sheet(%{as_of: today})
    assert bs.balanced?
    assert Decimal.equal?(bs.assets, Decimal.new("1500"))
    assert Decimal.equal?(bs.liabilities_and_equity, Decimal.new("1500"))
    assert Decimal.equal?(bs.retained_earnings, Decimal.new("1500"))
  end

  test "income statement shows revenue and net income", %{today: today} do
    {:ok, is} = Ledger.build_income_statement(today, today)
    assert Decimal.equal?(is.revenue, Decimal.new("1500"))
    assert Decimal.equal?(is.expenses, Decimal.new("0"))
    assert Decimal.equal?(is.net_income, Decimal.new("1500"))
  end

  test "AR aging buckets open invoices by age", %{today: today} do
    {:ok, aging} = Finance.build_ar_aging(%{as_of: today})
    assert aging.invoice_count == 2
    # inv1 ($700 remaining after $300 payment) is current; inv2 ($500) is 31-60 days overdue.
    assert Decimal.equal?(aging.current, Decimal.new("700"))
    assert Decimal.equal?(aging.d31_60, Decimal.new("500"))
    assert Decimal.equal?(aging.total, Decimal.new("1200"))
  end
end
