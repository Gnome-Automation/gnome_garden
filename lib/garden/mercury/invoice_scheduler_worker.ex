defmodule GnomeGarden.Mercury.InvoiceSchedulerWorker do
  @moduledoc """
  Oban cron worker that generates and issues invoices for Agreements
  that are due for billing.

  Runs daily at 6am UTC. For each active Agreement where
  `next_billing_date <= today`, it:
  1. Calls create_invoice_from_agreement_sources — creates a draft invoice
     from all approved, unbilled TimeEntries and Expenses.
  2. Issues the invoice (draft → issued).
  3. Sends invoice email to client via Swoosh.
  4. Advances next_billing_date by one billing cycle.

  If there are no billable entries, the invoice is not created but
  next_billing_date is still advanced.
  """

  use Oban.Worker, queue: :mercury, max_attempts: 3

  require Logger
  require Ash.Query

  alias GnomeGarden.Finance
  alias GnomeGarden.Commercial
  alias GnomeGarden.Mailer
  alias GnomeGarden.Mailer.InvoiceEmail

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    today = Date.utc_today()

    GnomeGarden.Commercial.Agreement
    |> Ash.Query.filter(
      status == :active and
        billing_cycle != :none and
        not is_nil(next_billing_date) and
        next_billing_date <= ^today
    )
    |> Ash.read!(domain: Commercial)
    |> Enum.each(&process_agreement/1)

    :ok
  end

  defp process_agreement(agreement) do
    Logger.info("InvoiceSchedulerWorker: processing agreement #{agreement.id}")

    case Finance.create_invoice_from_agreement_sources(agreement.id) do
      {:ok, invoice} ->
        case Finance.issue_invoice(invoice) do
          {:ok, issued} ->
            send_invoice_email(issued)
            advance_billing_date(agreement)

            Logger.info(
              "InvoiceSchedulerWorker: issued invoice #{invoice.id} for agreement #{agreement.id}"
            )

          {:error, reason} ->
            Logger.error("InvoiceSchedulerWorker: failed to issue invoice",
              agreement_id: agreement.id,
              reason: inspect(reason)
            )
        end

      {:error, %Ash.Error.Invalid{errors: errors}} ->
        if Enum.any?(errors, fn
             %{message: msg} when is_binary(msg) ->
               msg =~ "approved billable source records"

             _ ->
               false
           end) do
          Logger.info(
            "InvoiceSchedulerWorker: no billable entries for agreement #{agreement.id}, advancing date"
          )

          advance_billing_date(agreement)
        else
          Logger.error("InvoiceSchedulerWorker: unexpected error creating invoice",
            agreement_id: agreement.id,
            errors: inspect(errors)
          )
        end

      {:error, reason} ->
        Logger.error("InvoiceSchedulerWorker: failed to create invoice",
          agreement_id: agreement.id,
          reason: inspect(reason)
        )
    end
  end

  defp advance_billing_date(agreement) do
    new_date =
      case agreement.billing_cycle do
        :weekly -> Date.add(agreement.next_billing_date, 7)
        :monthly -> Date.shift(agreement.next_billing_date, month: 1)
      end

    agreement
    |> Ash.Changeset.for_update(:update, %{next_billing_date: new_date})
    |> Ash.update!(domain: Commercial)
  end

  defp send_invoice_email(invoice) do
    {:ok, loaded} =
      Ash.get(
        GnomeGarden.Finance.Invoice,
        invoice.id,
        domain: GnomeGarden.Finance,
        load: [:invoice_lines, :organization]
      )

    mercury_info = Application.get_env(:gnome_garden, :mercury_payment_info, [])

    loaded
    |> InvoiceEmail.build(mercury_info)
    |> Mailer.deliver()
    |> case do
      {:ok, _} ->
        :ok

      {:error, reason} ->
        Logger.warning("InvoiceSchedulerWorker: failed to send invoice email",
          invoice_id: invoice.id,
          reason: inspect(reason)
        )
    end
  end
end
