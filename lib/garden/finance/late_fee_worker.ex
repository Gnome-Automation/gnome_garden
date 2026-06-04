defmodule GnomeGarden.Finance.LateFeeWorker do
  @moduledoc """
  Oban cron worker that applies a one-time late fee line item to overdue invoices.

  Runs daily at 9am UTC. Reads late fee config from BillingSettings via
  Finance.get_late_fee_settings/0. Skips if late_fee_enabled is false.
  Only fires on invoices where late_fee_applied_on is nil (idempotency guard).
  Skips invoices where the calculated fee is $0.00 or less.
  """

  use Oban.Worker, queue: :finance, max_attempts: 3, unique: [period: 86_400]

  require Logger
  require Ash.Query

  alias GnomeGarden.Finance
  alias GnomeGarden.Finance.Invoice

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    settings = Finance.get_late_fee_settings()

    if settings.late_fee_enabled do
      today = Date.utc_today()

      Invoice
      |> Ash.Query.for_read(:overdue)
      |> Ash.Query.filter(is_nil(late_fee_applied_on))
      |> Ash.read!(domain: Finance, authorize?: false)
      |> Enum.filter(fn inv -> Date.diff(today, inv.due_on) >= settings.late_fee_days end)
      |> Enum.each(&apply_late_fee(&1, settings))
    end

    :ok
  end

  defp apply_late_fee(invoice, settings) do
    fee_amount = calculate_fee(invoice, settings)

    if Decimal.compare(fee_amount, Decimal.new("0")) == :gt do
      line_number = next_line_number(invoice)

      case Finance.create_invoice_line(%{
             invoice_id: invoice.id,
             organization_id: invoice.organization_id,
             line_kind: :adjustment,
             description: late_fee_description(settings),
             quantity: Decimal.new("1"),
             unit_price: fee_amount,
             line_total: fee_amount,
             line_number: line_number
           }, authorize?: false) do
        {:ok, _} ->
          invoice
          |> Ash.Changeset.for_update(:apply_late_fee, %{fee_amount: fee_amount},
            domain: Finance,
            authorize?: false
          )
          |> Ash.update!(domain: Finance, authorize?: false)

          Logger.info(
            "LateFeeWorker: applied late fee #{fee_amount} to #{invoice.invoice_number}"
          )

        {:error, reason} ->
          Logger.warning(
            "LateFeeWorker: failed to create line item for #{invoice.invoice_number}: #{inspect(reason)}"
          )
      end
    else
      Logger.info(
        "LateFeeWorker: skipping #{invoice.invoice_number} — fee would be $0.00"
      )
    end
  end

  defp calculate_fee(_invoice, %{late_fee_type: :flat, late_fee_value: value}), do: value

  defp calculate_fee(invoice, %{late_fee_type: :percent, late_fee_value: pct}) do
    Decimal.mult(invoice.balance_amount, Decimal.div(pct, Decimal.new("100")))
    |> Decimal.round(2)
  end

  defp late_fee_description(%{late_fee_type: :flat, late_fee_value: v}),
    do: "Late Fee ($#{Decimal.to_string(Decimal.round(v, 2), :normal)})"

  defp late_fee_description(%{late_fee_type: :percent, late_fee_value: v}),
    do: "Late Fee (#{Decimal.to_string(Decimal.round(v, 2), :normal)}%)"

  defp next_line_number(invoice) do
    (invoice.invoice_lines || [])
    |> Enum.map(& &1.line_number)
    |> Enum.max(fn -> 0 end)
    |> Kernel.+(1)
  end
end
