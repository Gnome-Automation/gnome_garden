defmodule GnomeGarden.Finance.RecurringVendorBillWorker do
  @moduledoc """
  Oban cron worker that generates draft vendor bills from active recurring templates.

  Runs daily at 6am UTC. For each active RecurringVendorBill where next_due_on
  <= today, creates a draft VendorBill, then advances next_due_on by the interval.

  If an end_date is set and the new next_due_on exceeds it, sets status :stopped.
  """

  use Oban.Worker, queue: :finance, max_attempts: 3

  require Logger
  require Ash.Query

  alias GnomeGarden.Finance
  alias GnomeGarden.Finance.RecurringVendorBill

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    today = Date.utc_today()

    RecurringVendorBill
    |> Ash.Query.filter(status == :active)
    |> Ash.Query.filter(next_due_on <= ^today)
    |> Ash.Query.load([:vendor])
    |> Ash.read!(domain: Finance, authorize?: false)
    |> Enum.each(&generate_bill(&1, today))

    :ok
  end

  defp generate_bill(template, today) do
    due_on = Date.add(today, 30)

    attrs = %{
      vendor_id: template.vendor_id,
      description: template.description,
      amount: template.amount,
      issued_on: today,
      due_on: due_on,
      notes: template.notes
    }

    case Finance.create_vendor_bill(attrs, authorize?: false) do
      {:ok, bill} ->
        Logger.info("RecurringVendorBillWorker: created bill #{bill.bill_number} for vendor #{template.vendor_id}")
        advance_schedule(template, today)

      {:error, reason} ->
        Logger.error("RecurringVendorBillWorker: failed to create bill for template #{template.id}: #{inspect(reason)}")
    end
  end

  defp advance_schedule(template, _today) do
    new_date = advance_date(template.next_due_on, template.interval)

    new_status =
      if template.end_date && Date.compare(new_date, template.end_date) == :gt,
        do: :stopped,
        else: template.status

    Finance.advance_recurring_vendor_bill_schedule(
      template,
      %{next_due_on: new_date, status: new_status},
      authorize?: false
    )
  end

  def advance_date(date, :weekly), do: Date.add(date, 7)
  def advance_date(date, :monthly), do: Date.shift(date, month: 1)
  def advance_date(date, :quarterly), do: Date.shift(date, month: 3)
  def advance_date(date, :semi_annually), do: Date.shift(date, month: 6)
  def advance_date(date, :annually), do: Date.shift(date, year: 1)
end
