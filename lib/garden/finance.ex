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
    resource GnomeGarden.Finance.BankConnection do
      define :list_bank_connections, action: :read
      define :list_active_bank_connections, action: :active
      define :get_bank_connection, action: :read, get_by: [:id]

      define :get_bank_connection_by_provider_environment,
        action: :read,
        get_by: [:provider, :environment]

      define :create_bank_connection, action: :create
      define :update_bank_connection, action: :update
      define :sync_bank_connection, action: :sync, args: [:bank_connection_id, :source]
      define :sync_bank_provider, action: :sync_provider, args: [:provider, :environment, :source]
      define :get_banking_workspace, action: :banking_workspace
      define :activate_bank_connection, action: :activate
      define :pause_bank_connection, action: :pause
      define :archive_bank_connection, action: :archive
      define :mark_bank_connection_sync_succeeded, action: :mark_sync_succeeded
      define :mark_bank_connection_sync_failed, action: :mark_sync_failed
    end

    resource GnomeGarden.Finance.BankAccount do
      define :list_bank_accounts, action: :read
      define :get_bank_account, action: :read, get_by: [:id]

      define :get_bank_account_by_provider_id,
        action: :read,
        get_by: [:provider, :provider_account_id]

      define :create_bank_account, action: :create
      define :update_bank_account, action: :update
      define :rename_bank_account, action: :rename
      define :mark_bank_account_inactive, action: :mark_inactive
    end

    resource GnomeGarden.Finance.BankTransaction do
      define :list_bank_transactions, action: :read
      define :list_bank_transactions_needing_review, action: :needs_review
      define :get_bank_transaction, action: :read, get_by: [:id]

      define :get_bank_transaction_by_provider_id,
        action: :read,
        get_by: [:provider, :provider_transaction_id]

      define :create_bank_transaction, action: :create
      define :update_bank_transaction, action: :update
      define :categorize_bank_transaction, action: :categorize
      define :apply_bank_rule_to_transaction, action: :apply_rule
      define :mark_bank_transaction_reviewed, action: :mark_reviewed
      define :mark_bank_transaction_matched, action: :mark_matched
      define :mark_bank_transaction_unmatched, action: :mark_unmatched
      define :ignore_bank_transaction, action: :ignore
      define :reopen_bank_transaction_review, action: :reopen_review
    end

    resource GnomeGarden.Finance.BankTransactionMatch do
      define :list_bank_transaction_matches, action: :read

      define :list_bank_transaction_matches_for_transaction,
        action: :for_transaction,
        args: [:bank_transaction_id]

      define :get_bank_transaction_match, action: :read, get_by: [:id]
      define :create_bank_transaction_match, action: :create
      define :accept_bank_transaction_match, action: :accept
      define :reject_bank_transaction_match, action: :reject
      define :supersede_bank_transaction_match, action: :supersede

      define :delete_bank_transaction_match,
        action: :destroy,
        default_options: [return_destroyed?: true]
    end

    resource GnomeGarden.Finance.BankRule do
      define :list_bank_rules, action: :sorted
      define :get_bank_rule, action: :read, get_by: [:id]
      define :create_bank_rule, action: :create
      define :update_bank_rule, action: :update
      define :enable_bank_rule, action: :enable
      define :disable_bank_rule, action: :disable
      define :reorder_bank_rule, action: :reorder
      define :delete_bank_rule, action: :destroy, default_options: [return_destroyed?: true]
    end

    resource GnomeGarden.Finance.BankCounterpartyAlias do
      define :list_bank_counterparty_aliases, action: :read
      define :get_bank_counterparty_alias, action: :read, get_by: [:id]
      define :create_bank_counterparty_alias, action: :create
      define :confirm_bank_counterparty_alias, action: :confirm
      define :ignore_bank_counterparty_alias, action: :ignore
      define :merge_bank_counterparty_alias, action: :merge

      define :list_bank_counterparty_aliases_for_counterparty,
        action: :matching_counterparty,
        args: [:counterparty_name]
    end

    resource GnomeGarden.Finance.BankIntegrationEvent do
      define :list_bank_integration_events, action: :read
      define :list_recent_bank_integration_events, action: :recent
      define :get_bank_integration_event, action: :read, get_by: [:id]
      define :record_bank_integration_event, action: :record
      define :process_bank_integration_event, action: :process
      define :mark_bank_integration_event_processed, action: :mark_processed
      define :mark_bank_integration_event_failed, action: :mark_failed
      define :ignore_bank_integration_event, action: :ignore
      define :retry_bank_integration_event, action: :retry
    end

    resource GnomeGarden.Finance.BankTransactionEvent do
      define :list_bank_transaction_events, action: :read

      define :list_bank_transaction_events_for_transaction,
        action: :for_transaction,
        args: [:bank_transaction_id]

      define :record_bank_transaction_event, action: :record
    end

    resource GnomeGarden.Finance.BankSyncRun do
      define :list_bank_sync_runs, action: :read
      define :list_recent_bank_sync_runs, action: :recent
      define :get_bank_sync_run, action: :read, get_by: [:id]
      define :start_bank_sync_run, action: :start
      define :finish_bank_sync_run_success, action: :finish_success
      define :finish_bank_sync_run_failure, action: :finish_failure
    end

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
      define :get_receivables_workspace, action: :receivables_workspace
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

    resource GnomeGarden.Finance.PaymentApplication do
      define :list_payment_applications, action: :read
      define :get_payment_application, action: :read, get_by: [:id]
      define :create_payment_application, action: :create
      define :update_payment_application, action: :update
      define :list_payment_applications_for_invoice, action: :for_invoice, args: [:invoice_id]
      define :list_payment_applications_for_payment, action: :for_payment, args: [:payment_id]
    end
  end
end
