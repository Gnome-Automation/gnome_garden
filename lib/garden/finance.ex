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

  def create_invoices_from_fixed_fee_schedule(agreement_id, _opts \\ []) do
    GnomeGarden.Finance.Changes.CreateInvoiceFromFixedFeeSchedule.generate(agreement_id)
  end
end
