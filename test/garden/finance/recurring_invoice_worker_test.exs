defmodule GnomeGarden.Finance.RecurringInvoiceWorkerTest do
  use ExUnit.Case, async: true

  alias GnomeGarden.Finance.RecurringInvoiceWorker

  describe "advance_date/2" do
    test "daily advances by 1 day" do
      date = ~D[2026-06-01]
      assert RecurringInvoiceWorker.advance_date(date, :daily) == ~D[2026-06-02]
    end

    test "weekly advances by 7 days" do
      date = ~D[2026-06-01]
      assert RecurringInvoiceWorker.advance_date(date, :weekly) == ~D[2026-06-08]
    end

    test "monthly advances by 1 month" do
      date = ~D[2026-01-31]
      assert RecurringInvoiceWorker.advance_date(date, :monthly) == ~D[2026-02-28]
    end

    test "quarterly advances by 3 months" do
      date = ~D[2026-03-01]
      assert RecurringInvoiceWorker.advance_date(date, :quarterly) == ~D[2026-06-01]
    end

    test "semi_annually advances by 6 months" do
      date = ~D[2026-01-01]
      assert RecurringInvoiceWorker.advance_date(date, :semi_annually) == ~D[2026-07-01]
    end

    test "annually advances by 1 year" do
      date = ~D[2026-06-01]
      assert RecurringInvoiceWorker.advance_date(date, :annually) == ~D[2027-06-01]
    end
  end

  describe "compute_totals/2" do
    test "computes subtotal, tax_total, total_amount correctly" do
      lines = [
        %{quantity: Decimal.new("2"), unit_price: Decimal.new("100.00")},
        %{quantity: Decimal.new("1"), unit_price: Decimal.new("50.00")}
      ]
      tax_rate = Decimal.new("10")
      result = RecurringInvoiceWorker.compute_totals(lines, tax_rate)
      assert Decimal.equal?(result.subtotal, Decimal.new("250.00"))
      assert Decimal.equal?(result.tax_total, Decimal.new("25"))
      assert Decimal.equal?(result.total_amount, Decimal.new("275"))
    end

    test "zero tax rate produces zero tax_total" do
      lines = [%{quantity: Decimal.new("1"), unit_price: Decimal.new("500.00")}]
      result = RecurringInvoiceWorker.compute_totals(lines, Decimal.new("0"))
      assert Decimal.equal?(result.tax_total, Decimal.new("0"))
      assert Decimal.equal?(result.total_amount, Decimal.new("500.00"))
    end
  end
end
