defmodule GnomeGarden.Finance.PaymentReminderWorker do
  @moduledoc """
  Oban cron worker that sends payment reminder emails for overdue invoices.

  Runs daily at 8am UTC. For each issued or partial invoice past its due_on,
  reads configured reminder days from BillingSettings (via Finance.get_reminder_days/0)
  and sends an email for each overdue invoice that exactly matches a threshold day.

  Note: The CC-to-agreement-owner escalation fires only at exactly day 30. If the
  configured thresholds don't include 30, the CC will not trigger.

  Only fires on exact day matches to avoid duplicate sends.
  Skips invoices where the resolved recipient has do_not_email: true.
  """

  use Oban.Worker, queue: :finance, max_attempts: 3

  require Logger
  require Ash.Query

  alias GnomeGarden.Finance
  alias GnomeGarden.Finance.Invoice
  alias GnomeGarden.Mailer
  alias GnomeGarden.Mailer.InvoiceEmail
  alias GnomeGarden.Mailer.PaymentReminderEmail

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    today = Date.utc_today()
    thresholds = Finance.get_reminder_days()

    Invoice
    |> Ash.Query.for_read(:overdue)
    |> Ash.Query.load(organization: [:billing_contact], agreement: [owner_team_member: [:user]])
    |> Ash.read!(domain: Finance, authorize?: false)
    |> Enum.each(&maybe_send_reminder(&1, today, thresholds))

    :ok
  end

  defp maybe_send_reminder(invoice, today, thresholds) do
    days_overdue = Date.diff(today, invoice.due_on)

    if days_overdue in thresholds do
      send_reminder(invoice, threshold_atom(days_overdue))
    end
  end

  defp threshold_atom(days), do: :"day_#{days}"

  defp send_reminder(invoice, threshold) do
    recipient = InvoiceEmail.find_billing_email(invoice.organization || %{})

    if is_nil(recipient) do
      Logger.warning(
        "PaymentReminderWorker: no valid recipient for invoice #{invoice.invoice_number}, skipping"
      )
    else
      opts = build_opts(invoice, threshold)

      invoice
      |> PaymentReminderEmail.build(threshold, opts)
      |> Mailer.deliver()
      |> case do
        {:ok, _} ->
          Logger.info(
            "PaymentReminderWorker: sent #{threshold} reminder for #{invoice.invoice_number}"
          )

        {:error, reason} ->
          Logger.warning(
            "PaymentReminderWorker: failed to send reminder for #{invoice.invoice_number}: #{inspect(reason)}"
          )
      end
    end
  end

  defp build_opts(invoice, :day_30) do
    owner_email =
      invoice.agreement &&
        invoice.agreement.owner_team_member &&
        invoice.agreement.owner_team_member.user &&
        invoice.agreement.owner_team_member.user.email

    if owner_email, do: [cc: to_string(owner_email)], else: []
  end

  defp build_opts(_invoice, _threshold), do: []
end
