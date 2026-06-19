defmodule GnomeGarden.Finance.InvoiceSchedulerWorker do
  @moduledoc """
  Oban cron worker that generates and issues invoices for Agreements that are
  due for billing. Runs daily at 6am UTC.

  Each execution records a durable `BillingRun` (with a `BillingRunItem` per
  agreement) so an operator can answer "what happened this morning, what failed,
  and what do I need to touch?".

  For each active Agreement where `next_billing_date <= today` it:
  1. Creates a draft invoice from approved, unbilled time entries and expenses.
  2. Issues the invoice (draft → issued) and posts the ledger entry.
  3. Advances `next_billing_date` by one billing cycle — only after a successful
     issue (or when there was nothing to bill).
  4. Attempts to email the invoice as a SEPARATE side effect: a failed or
     undeliverable email leaves the invoice issued (and posted) with
     `email_status: :failed` for an operator to retry — it never undoes
     issuance or the ledger posting.

  The run finishes as `:succeeded`, `:partial_failure` (some agreement failed,
  or an invoice issued but its email did not), or `:failed` (nothing issued).
  """

  use Oban.Worker, queue: :default, max_attempts: 3

  require Logger
  require Ash.Query

  import Swoosh.Email

  alias GnomeGarden.Finance
  alias GnomeGarden.Commercial
  alias GnomeGarden.Operations
  alias GnomeGarden.Mailer

  @empty_counts %{scanned: 0, drafted: 0, issued: 0, emailed: 0, failed: 0, skipped: 0}

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    {:ok, run} = Finance.start_billing_run(%{source: :scheduled})

    try do
      agreements = due_agreements()

      counts =
        Enum.reduce(agreements, %{@empty_counts | scanned: length(agreements)}, fn agreement, acc ->
          merge_counts(acc, process_agreement(agreement, run))
        end)

      finish_run(run, counts)
      :ok
    rescue
      error ->
        Logger.error("InvoiceSchedulerWorker crashed: #{inspect(error)}")
        Finance.finish_billing_run_failure(run, %{error_summary: Exception.message(error)})
        {:error, error}
    end
  end

  defp due_agreements do
    today = Date.utc_today()

    GnomeGarden.Commercial.Agreement
    |> Ash.Query.filter(
      status == :active and
        billing_cycle != :none and
        not is_nil(next_billing_date) and
        next_billing_date <= ^today
    )
    |> Ash.read!(domain: Commercial)
  end

  # Processes one due agreement, records a BillingRunItem, and returns the count
  # deltas it contributes to the run.
  defp process_agreement(agreement, run) do
    Logger.info("InvoiceSchedulerWorker: processing agreement #{agreement.id}")

    case Finance.create_invoice_from_agreement_sources(agreement.id) do
      {:ok, invoice} ->
        handle_issue(agreement, invoice, run)

      {:error, %Ash.Error.Invalid{errors: errors}} ->
        if no_billable_sources?(errors) do
          advance_billing_date(agreement)
          record_item(run, agreement, nil, :skipped, :not_attempted, "no billable sources")
          %{@empty_counts | skipped: 1}
        else
          Logger.error("InvoiceSchedulerWorker: create failed", agreement_id: agreement.id, errors: inspect(errors))
          record_item(run, agreement, nil, :failed, :not_attempted, "create failed: #{inspect(errors)}")
          %{@empty_counts | failed: 1}
        end

      {:error, reason} ->
        Logger.error("InvoiceSchedulerWorker: create failed", agreement_id: agreement.id, reason: inspect(reason))
        record_item(run, agreement, nil, :failed, :not_attempted, "create failed: #{inspect(reason)}")
        %{@empty_counts | failed: 1}
    end
  end

  defp handle_issue(agreement, invoice, run) do
    case Finance.issue_invoice(invoice) do
      {:ok, issued} ->
        # Accounting state is now committed; advance the billing date.
        advance_billing_date(agreement)

        # Email is a separate side effect — its failure must not undo issuance.
        {email_outcome, email_delta, detail} = attempt_email(issued)
        record_item(run, agreement, issued.id, :issued, email_outcome, detail)
        merge_counts(%{@empty_counts | drafted: 1, issued: 1}, email_delta)

      {:error, reason} ->
        # A draft exists but could not be issued; do NOT advance the date.
        Logger.error("InvoiceSchedulerWorker: issue failed", agreement_id: agreement.id, reason: inspect(reason))
        record_item(run, agreement, invoice.id, :failed, :not_attempted, "issue failed: #{inspect(reason)}")
        %{@empty_counts | drafted: 1, failed: 1}
    end
  end

  defp attempt_email(invoice) do
    case send_invoice_email(invoice) do
      :ok ->
        Finance.mark_invoice_email_sent(invoice)
        {:sent, %{@empty_counts | emailed: 1}, nil}

      {:error, reason} ->
        Logger.warning("InvoiceSchedulerWorker: email failed for invoice #{invoice.id}: #{reason}")
        Finance.mark_invoice_email_failed(invoice, %{email_failure_reason: reason})
        # The invoice stays issued/posted; this is an email-delivery failure only.
        {:failed, %{@empty_counts | failed: 1}, "email failed: #{reason}"}
    end
  end

  defp record_item(run, agreement, invoice_id, outcome, email_outcome, detail) do
    Finance.create_billing_run_item(%{
      billing_run_id: run.id,
      agreement_id: agreement.id,
      invoice_id: invoice_id,
      outcome: outcome,
      email_outcome: email_outcome,
      detail: detail
    })
  end

  defp finish_run(run, counts) do
    attrs = %{
      scanned_count: counts.scanned,
      drafted_count: counts.drafted,
      issued_count: counts.issued,
      emailed_count: counts.emailed,
      failed_count: counts.failed,
      skipped_count: counts.skipped
    }

    cond do
      counts.issued == 0 and counts.failed > 0 ->
        Finance.finish_billing_run_failure(run, Map.put(attrs, :error_summary, summary(counts)))

      counts.failed > 0 or counts.issued > counts.emailed ->
        Finance.finish_billing_run_partial_failure(run, Map.put(attrs, :error_summary, summary(counts)))

      true ->
        Finance.finish_billing_run_success(run, attrs)
    end
  end

  defp summary(counts) do
    "scanned #{counts.scanned}, issued #{counts.issued}, emailed #{counts.emailed}, " <>
      "failed #{counts.failed}, skipped #{counts.skipped}"
  end

  defp merge_counts(a, b), do: Map.merge(a, b, fn _key, v1, v2 -> v1 + v2 end)

  defp no_billable_sources?(errors) do
    Enum.any?(errors, fn
      %{message: msg} when is_binary(msg) -> msg =~ "approved billable source records"
      _ -> false
    end)
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

  # Sends the invoice email. Returns :ok or {:error, reason} — never raises into
  # the caller, so a delivery problem stays a delivery problem.
  defp send_invoice_email(invoice) do
    {:ok, loaded} = Finance.get_invoice(invoice.id, load: [:invoice_lines, :organization])

    case contact_email(loaded.organization_id) do
      nil ->
        {:error, "no contact email for organization"}

      email ->
        new()
        |> from({"GnomeGarden Billing", "billing@gnomegarden.io"})
        |> to(email)
        |> subject("Invoice #{loaded.invoice_number} — #{loaded.currency_code} #{loaded.total_amount}")
        |> html_body(invoice_email_body(loaded))
        |> Mailer.deliver()
        |> case do
          {:ok, _} -> :ok
          {:error, reason} -> {:error, inspect(reason)}
        end
    end
  end

  defp contact_email(organization_id) do
    case Operations.list_people_for_organization(organization_id) do
      {:ok, people} ->
        Enum.find_value(people, fn person ->
          if person.email && !person.do_not_email, do: to_string(person.email)
        end)

      {:error, _} ->
        nil
    end
  end

  defp invoice_email_body(invoice) do
    lines_html =
      invoice.invoice_lines
      |> Enum.map(fn line ->
        "<tr><td>#{line.description}</td><td>#{line.line_total}</td></tr>"
      end)
      |> Enum.join("\n")

    """
    <p>Dear #{invoice.organization.name},</p>
    <p>Please find your invoice <strong>#{invoice.invoice_number}</strong> attached.</p>
    <p><strong>Total due: #{invoice.currency_code} #{invoice.total_amount}</strong><br>
    Due date: #{invoice.due_on}</p>
    <table border="1" cellpadding="4">
      <thead><tr><th>Description</th><th>Amount</th></tr></thead>
      <tbody>#{lines_html}</tbody>
    </table>
    <p>Please remit payment via wire or ACH per the instructions on file.</p>
    """
  end
end
