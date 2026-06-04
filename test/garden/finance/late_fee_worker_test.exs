defmodule GnomeGarden.Finance.LateFeeWorkerTest do
  use GnomeGarden.DataCase, async: false

  alias GnomeGarden.Finance
  alias GnomeGarden.Finance.LateFeeWorker
  alias GnomeGarden.Operations

  # Helper: create an org (needed as invoice FK)
  defp create_org do
    {:ok, org} =
      Operations.create_organization(%{
        name: "Test Org #{System.unique_integer([:positive])}",
        organization_kind: :business
      })

    org
  end

  # Helper: create and issue an overdue invoice
  defp create_overdue_invoice(org, days_ago, opts \\ []) do
    due_on = Date.add(Date.utc_today(), -days_ago)
    balance = Keyword.get(opts, :balance, Decimal.new("500.00"))

    {:ok, invoice} =
      Finance.create_invoice(%{
        organization_id: org.id,
        invoice_number: "INV-LF-#{System.unique_integer([:positive])}",
        currency_code: "USD",
        total_amount: balance,
        balance_amount: balance,
        due_on: due_on
      })

    {:ok, issued} = Finance.issue_invoice(invoice)
    issued
  end

  # Helper: set up BillingSettings with late fee config
  defp enable_late_fees(opts \\ []) do
    Finance.upsert_billing_settings(%{
      reminder_days: [7, 14, 30],
      late_fee_enabled: Keyword.get(opts, :enabled, true),
      late_fee_days: Keyword.get(opts, :days, 30),
      late_fee_type: Keyword.get(opts, :type, :percent),
      late_fee_value: Keyword.get(opts, :value, Decimal.new("1.5"))
    })
  end

  setup do
    # Include all new late fee fields to avoid nil-field upsert failures on subsequent runs
    {:ok, _} =
      Finance.upsert_billing_settings(%{
        reminder_days: [7, 14, 30],
        late_fee_enabled: false,
        late_fee_days: 30,
        late_fee_type: :percent,
        late_fee_value: Decimal.new("1.5")
      })

    :ok
  end

  test "does nothing when late_fee_enabled is false" do
    org = create_org()
    invoice = create_overdue_invoice(org, 35)

    assert :ok = LateFeeWorker.perform(%Oban.Job{args: %{}})

    {:ok, reloaded} = Finance.get_invoice(invoice.id, load: [:invoice_lines])
    assert reloaded.late_fee_applied_on == nil
    assert Enum.empty?(Enum.filter(reloaded.invoice_lines, &(&1.line_kind == :adjustment)))
  end

  test "applies flat fee to invoice past the threshold" do
    {:ok, _} = enable_late_fees(type: :flat, value: Decimal.new("25.00"), days: 30)
    org = create_org()
    invoice = create_overdue_invoice(org, 35)

    assert :ok = LateFeeWorker.perform(%Oban.Job{args: %{}})

    {:ok, reloaded} = Finance.get_invoice(invoice.id, load: [:invoice_lines])
    assert reloaded.late_fee_applied_on == Date.utc_today()

    late_fee_line = Enum.find(reloaded.invoice_lines, &(&1.line_kind == :adjustment))
    assert late_fee_line != nil
    assert Decimal.equal?(late_fee_line.line_total, Decimal.new("25.00"))
    assert late_fee_line.description =~ "Late Fee"

    assert Decimal.equal?(reloaded.total_amount, Decimal.new("525.00"))
    assert Decimal.equal?(reloaded.balance_amount, Decimal.new("525.00"))
  end

  test "applies percent fee calculated from balance_amount" do
    {:ok, _} = enable_late_fees(type: :percent, value: Decimal.new("2.0"), days: 30)
    org = create_org()
    invoice = create_overdue_invoice(org, 35, balance: Decimal.new("1000.00"))

    assert :ok = LateFeeWorker.perform(%Oban.Job{args: %{}})

    {:ok, reloaded} = Finance.get_invoice(invoice.id, load: [:invoice_lines])
    assert reloaded.late_fee_applied_on == Date.utc_today()

    late_fee_line = Enum.find(reloaded.invoice_lines, &(&1.line_kind == :adjustment))
    assert late_fee_line != nil
    # 2% of 1000.00 = 20.00
    assert Decimal.equal?(late_fee_line.line_total, Decimal.new("20.00"))
  end

  test "does not re-apply to an already-applied invoice" do
    {:ok, _} = enable_late_fees(type: :flat, value: Decimal.new("25.00"), days: 30)
    org = create_org()
    invoice = create_overdue_invoice(org, 35)

    assert :ok = LateFeeWorker.perform(%Oban.Job{args: %{}})
    assert :ok = LateFeeWorker.perform(%Oban.Job{args: %{}})

    {:ok, reloaded} = Finance.get_invoice(invoice.id, load: [:invoice_lines])
    adjustment_lines = Enum.filter(reloaded.invoice_lines, &(&1.line_kind == :adjustment))
    assert length(adjustment_lines) == 1
    # Total should only have one $25 fee applied
    assert Decimal.equal?(reloaded.total_amount, Decimal.new("525.00"))
  end

  test "does not apply to invoice not yet past threshold" do
    {:ok, _} = enable_late_fees(days: 30)
    org = create_org()
    invoice = create_overdue_invoice(org, 10)  # only 10 days overdue, threshold is 30

    assert :ok = LateFeeWorker.perform(%Oban.Job{args: %{}})

    {:ok, reloaded} = Finance.get_invoice(invoice.id)
    assert reloaded.late_fee_applied_on == nil
  end

  test "skips invoice when balance_amount is zero" do
    {:ok, _} = enable_late_fees(type: :percent, value: Decimal.new("1.5"), days: 30)
    org = create_org()
    invoice = create_overdue_invoice(org, 35, balance: Decimal.new("0.00"))

    assert :ok = LateFeeWorker.perform(%Oban.Job{args: %{}})

    {:ok, reloaded} = Finance.get_invoice(invoice.id, load: [:invoice_lines])
    assert reloaded.late_fee_applied_on == nil
    assert Enum.empty?(Enum.filter(reloaded.invoice_lines, &(&1.line_kind == :adjustment)))
  end
end
