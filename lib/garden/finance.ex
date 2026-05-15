defmodule GnomeGarden.Finance do
  @moduledoc """
  Operational finance domain.

  Owns billable and cost-bearing records that support project, service, and
  agreement reporting without attempting to replace a full accounting ledger.
  """

  use Ash.Domain,
    otp_app: :gnome_garden,
    extensions: [AshAdmin.Domain]

  admin do
    show? true
  end

  resources do
    resource GnomeGarden.Finance.TimeEntry do
      define :list_time_entries, action: :read
      define :get_time_entry, action: :read, get_by: [:id]
      define :create_time_entry, action: :create
      define :update_time_entry, action: :update
      define :submit_time_entry, action: :submit
      define :approve_time_entry, action: :approve
      define :reject_time_entry, action: :reject
      define :bill_time_entry, action: :mark_billed
      define :reopen_time_entry, action: :reopen
      define :list_open_time_entries, action: :open
      define :list_unbilled_approved_time_entries, action: :approved_unbilled

      define :list_billable_time_entries_for_agreement,
        action: :billable_for_agreement,
        args: [:agreement_id]
    end

    resource GnomeGarden.Finance.Expense do
      define :list_expenses, action: :read
      define :get_expense, action: :read, get_by: [:id]
      define :create_expense, action: :create
      define :update_expense, action: :update
      define :submit_expense, action: :submit
      define :approve_expense, action: :approve
      define :reject_expense, action: :reject
      define :bill_expense, action: :mark_billed
      define :reopen_expense, action: :reopen
      define :list_open_expenses, action: :open
      define :list_unbilled_approved_expenses, action: :approved_unbilled

      define :list_billable_expenses_for_agreement,
        action: :billable_for_agreement,
        args: [:agreement_id]
    end

    resource GnomeGarden.Finance.Invoice do
      define :list_invoices, action: :read
      define :get_invoice, action: :read, get_by: [:id]
      define :create_invoice, action: :create
      define :create_invoice_from_agreement_sources,
        action: :create_from_agreement_sources,
        args: [:agreement_id]
      define :update_invoice, action: :update
      define :issue_invoice, action: :issue
      define :pay_invoice, action: :mark_paid
      define :partial_invoice, action: :partial
      define :write_off_invoice, action: :write_off
      define :void_invoice, action: :void
      define :reopen_invoice, action: :reopen
      define :list_open_invoices, action: :open
      define :list_overdue_invoices, action: :overdue
      define :list_portal_invoices, action: :portal_index
      define :get_portal_invoice, action: :portal_show, get_by: [:id]
    end

    resource GnomeGarden.Finance.InvoiceLine do
      define :list_invoice_lines, action: :read
      define :get_invoice_line, action: :read, get_by: [:id]
      define :create_invoice_line, action: :create
      define :update_invoice_line, action: :update
      define :list_invoice_lines_for_invoice, action: :for_invoice, args: [:invoice_id]
    end

    resource GnomeGarden.Finance.Payment do
      define :list_payments, action: :read
      define :get_payment, action: :read, get_by: [:id]
      define :create_payment, action: :create
      define :update_payment, action: :update
      define :deposit_payment, action: :deposit
      define :reverse_payment, action: :reverse
      define :list_open_payments, action: :open
    end

    resource GnomeGarden.Finance.PaymentScheduleItem

    resource GnomeGarden.Finance.PaymentApplication do
      define :list_payment_applications, action: :read
      define :get_payment_application, action: :read, get_by: [:id]
      define :create_payment_application, action: :create
      define :update_payment_application, action: :update
      define :list_payment_applications_for_invoice, action: :for_invoice, args: [:invoice_id]
      define :list_payment_applications_for_payment, action: :for_payment, args: [:payment_id]
    end

    resource GnomeGarden.Finance.FinanceSequence do
      define :list_finance_sequences, action: :read
    end

    resource GnomeGarden.Finance.CreditNote do
      define :list_credit_notes, action: :read
      define :get_credit_note, action: :read, get_by: [:id]
      define :create_credit_note, action: :create
      define :issue_credit_note, action: :issue
      define :update_credit_note, action: :update
    end

    resource GnomeGarden.Finance.CreditNoteLine do
      define :list_credit_note_lines, action: :read
      define :create_credit_note_line, action: :create
    end

    resource GnomeGarden.Finance.BillingSettings do
      define :get_billing_settings, action: :read
      define :upsert_billing_settings, action: :upsert
    end
  end

  def create_payment_schedule_item(attrs, _opts \\ []) do
    GnomeGarden.Finance.PaymentScheduleItem
    |> Ash.Changeset.for_create(:create, attrs)
    |> Ash.create(domain: __MODULE__, authorize?: false)
  end

  def list_payment_schedule_items_for_agreement(agreement_id, _opts \\ []) do
    require Ash.Query

    GnomeGarden.Finance.PaymentScheduleItem
    |> Ash.Query.filter(agreement_id == ^agreement_id)
    |> Ash.Query.sort(position: :asc)
    |> Ash.read(domain: __MODULE__, authorize?: false)
  end

  def get_payment_schedule_item(id, _opts \\ []) do
    GnomeGarden.Finance.PaymentScheduleItem
    |> Ash.get(id, domain: __MODULE__, authorize?: false)
  end

  def delete_payment_schedule_item(item, _opts \\ []) do
    Ash.destroy(item, domain: __MODULE__, authorize?: false)
  end

  def create_invoices_from_fixed_fee_schedule(agreement_id, selected_expense_ids \\ [], _opts \\ []) do
    GnomeGarden.Finance.Changes.CreateInvoiceFromFixedFeeSchedule.generate(
      agreement_id,
      selected_expense_ids
    )
  end

  @doc """
  Creates a draft invoice from approved billable time entries and expenses for a T&M agreement.

  Accepts `expense_ids: [string]` to selectively include only those expenses.
  If omitted or empty, no expense lines are added.
  """
  def draft_invoice_from_agreement_sources(agreement_id, opts \\ []) do
    {expense_ids, ash_opts} = Keyword.pop(opts, :expense_ids, [])

    GnomeGarden.Finance.Invoice
    |> Ash.Changeset.for_create(
      :create_from_agreement_sources,
      %{agreement_id: agreement_id, expense_ids: expense_ids},
      Keyword.merge([domain: __MODULE__], ash_opts)
    )
    |> Ash.create(Keyword.merge([domain: __MODULE__], ash_opts))
  end

  @doc """
  Atomically increments the named sequence and returns the new integer value.
  Uses a raw SQL UPDATE ... RETURNING — safe under concurrency.
  """
  def next_sequence_value(name) do
    {:ok, %{rows: [[val]]}} =
      GnomeGarden.Repo.query(
        "UPDATE finance_sequences SET last_value = last_value + 1 WHERE name = $1 RETURNING last_value",
        [name]
      )

    val
  end

  @doc """
  Formats a sequence integer as a credit note number string.
  Example: 1 → "CN-0001"
  """
  def format_credit_note_number(n) do
    "CN-" <> String.pad_leading("#{n}", 4, "0")
  end

  @doc """
  Returns the configured reminder threshold days from BillingSettings.
  Falls back to [7, 14, 30] if no settings row exists yet.
  """
  def get_reminder_days do
    case get_billing_settings() do
      {:ok, [settings | _]} -> settings.reminder_days
      _ -> [7, 14, 30]
    end
  end
end
