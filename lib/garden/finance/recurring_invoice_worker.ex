defmodule GnomeGarden.Finance.RecurringInvoiceWorker do
  @moduledoc """
  Oban cron worker that generates invoices from active recurring invoice templates.

  Runs daily at 7am UTC. For each active RecurringInvoice where next_generation_date
  <= today, creates a Finance.Invoice (and its lines), optionally issues it, then
  advances next_generation_date by the template's interval.

  If an end_date is set and the new next_generation_date exceeds it, sets status :stopped.
  """

  use Oban.Worker, queue: :finance, max_attempts: 3

  require Logger
  require Ash.Query

  alias GnomeGarden.Finance
  alias GnomeGarden.Finance.RecurringInvoice
  alias GnomeGarden.Mailer
  alias GnomeGarden.Mailer.InvoiceEmail

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    today = Date.utc_today()

    RecurringInvoice
    |> Ash.Query.filter(status == :active)
    |> Ash.Query.filter(next_generation_date <= ^today)
    |> Ash.Query.load([:recurring_invoice_lines])
    |> Ash.read!(domain: Finance, authorize?: false)
    |> Enum.each(&generate_invoice(&1, today))

    :ok
  end

  defp generate_invoice(template, today) do
    lines = template.recurring_invoice_lines
    totals = compute_totals(lines, template.tax_rate)
    due_on = Date.add(today, template.net_terms_days)

    invoice_attrs = %{
      organization_id: template.organization_id,
      agreement_id: template.agreement_id,
      tax_rate: template.tax_rate,
      notes: template.notes,
      due_on: due_on,
      recurring_invoice_id: template.id,
      subtotal: totals.subtotal,
      tax_total: totals.tax_total,
      total_amount: totals.total_amount
    }

    case Finance.create_invoice(invoice_attrs, authorize?: false) do
      {:ok, invoice} ->
        create_lines(invoice, lines)
        maybe_issue(invoice, template.delivery_mode)
        advance_schedule(template, today)

      {:error, reason} ->
        Logger.error(
          "RecurringInvoiceWorker: failed to create invoice for template #{template.id}: #{inspect(reason)}"
        )
    end
  end

  defp create_lines(invoice, lines) do
    Enum.each(lines, fn line ->
      attrs = %{
        invoice_id: invoice.id,
        organization_id: invoice.organization_id,
        description: line.description,
        quantity: line.quantity,
        unit_price: line.unit_price,
        line_total: line.line_total,
        line_kind: line.line_kind,
        line_number: line.line_number
      }

      case Finance.create_invoice_line(attrs, authorize?: false) do
        {:ok, _} -> :ok
        {:error, reason} -> Logger.error("RecurringInvoiceWorker: failed to create line: #{inspect(reason)}")
      end
    end)
  end

  defp maybe_issue(invoice, :auto_issue) do
    case Finance.issue_invoice(invoice, authorize?: false) do
      {:ok, issued} ->
        Logger.info("RecurringInvoiceWorker: issued invoice #{invoice.id}")
        send_invoice_email(issued)

      {:error, reason} ->
        Logger.error("RecurringInvoiceWorker: failed to issue invoice #{invoice.id}: #{inspect(reason)}")
    end
  end

  defp maybe_issue(_invoice, :draft), do: :ok

  defp send_invoice_email(invoice) do
    {:ok, loaded} =
      Finance.get_invoice(invoice.id,
        actor: nil,
        authorize?: false,
        load: [:invoice_lines, :organization]
      )

    mercury_info = Application.get_env(:gnome_garden, :mercury_payment_info, [])

    loaded
    |> InvoiceEmail.build(mercury_info)
    |> Mailer.deliver()
    |> case do
      {:ok, _} ->
        Logger.info("RecurringInvoiceWorker: sent invoice email for #{invoice.invoice_number}")

      {:error, reason} ->
        Logger.warning("RecurringInvoiceWorker: failed to send invoice email for #{invoice.id}: #{inspect(reason)}")
    end
  end

  defp advance_schedule(template, _today) do
    new_date = advance_date(template.next_generation_date, template.interval)

    new_status =
      if template.end_date && Date.compare(new_date, template.end_date) == :gt,
        do: :stopped,
        else: template.status

    Finance.advance_recurring_invoice_schedule(template,
      %{next_generation_date: new_date, status: new_status},
      authorize?: false
    )
  end

  # Public so it can be unit-tested without a database
  def advance_date(date, :daily), do: Date.add(date, 1)
  def advance_date(date, :weekly), do: Date.add(date, 7)
  def advance_date(date, :monthly), do: Date.shift(date, month: 1)
  def advance_date(date, :quarterly), do: Date.shift(date, month: 3)
  def advance_date(date, :semi_annually), do: Date.shift(date, month: 6)
  def advance_date(date, :annually), do: Date.shift(date, year: 1)

  def compute_totals(lines, tax_rate) do
    subtotal =
      Enum.reduce(lines, Decimal.new("0"), fn line, acc ->
        Decimal.add(acc, Decimal.mult(line.quantity, line.unit_price))
      end)

    tax_total = Decimal.mult(subtotal, Decimal.div(tax_rate, Decimal.new("100")))
    total_amount = Decimal.add(subtotal, tax_total)

    %{subtotal: subtotal, tax_total: tax_total, total_amount: total_amount}
  end
end
