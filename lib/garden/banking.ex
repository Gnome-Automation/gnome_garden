defmodule GnomeGarden.Banking do
  @moduledoc """
  Provider-neutral banking domain: bank connections, accounts, and transactions
  synced from providers (Mercury first), plus reconciliation matching of those
  transactions against the general ledger (`GnomeGarden.Ledger`).

  This is the bank-feed + reconciliation layer. It does not own the books — it
  proposes matches between bank transactions and posted journal entries.
  """

  use Ash.Domain,
    otp_app: :gnome_garden,
    extensions: [AshAdmin.Domain]

  admin do
    show? true
  end

  resources do
    resource GnomeGarden.Banking.BankConnection do
      define :list_bank_connections, action: :read
      define :list_active_bank_connections, action: :active
      define :get_bank_connection, action: :read, get_by: [:id]

      define :get_bank_connection_by_provider_environment,
        action: :read,
        get_by: [:provider, :environment]

      define :create_bank_connection, action: :create
      define :update_bank_connection, action: :update
      define :activate_bank_connection, action: :activate
      define :pause_bank_connection, action: :pause
      define :archive_bank_connection, action: :archive
      define :mark_bank_connection_synced, action: :mark_synced
      define :sync_bank_connection, action: :sync
      define :get_banking_workspace, action: :banking_workspace
    end

    resource GnomeGarden.Banking.BankAccount do
      define :list_bank_accounts, action: :read
      define :get_bank_account, action: :read, get_by: [:id]

      define :get_bank_account_by_provider_id,
        action: :read,
        get_by: [:provider, :provider_account_id]

      define :list_bank_accounts_for_connection,
        action: :for_connection,
        args: [:bank_connection_id]

      define :create_bank_account, action: :create
      define :upsert_bank_account, action: :upsert
      define :update_bank_account, action: :update
      define :mark_bank_account_inactive, action: :mark_inactive
      define :get_bank_account_workspace, action: :account_workspace, args: [:bank_account_id]
    end

    resource GnomeGarden.Banking.BankTransaction do
      define :list_bank_transactions, action: :read
      define :list_bank_transactions_needing_review, action: :needs_review
      define :get_bank_transaction, action: :read, get_by: [:id]

      define :get_bank_transaction_by_provider_id,
        action: :read,
        get_by: [:provider, :provider_transaction_id]

      define :list_bank_transactions_for_account,
        action: :for_account,
        args: [:bank_account_id]

      define :create_bank_transaction, action: :create
      define :upsert_bank_transaction, action: :upsert
      define :update_bank_transaction, action: :update
      define :categorize_bank_transaction, action: :categorize
      define :mark_bank_transaction_reviewed, action: :mark_reviewed
      define :mark_bank_transaction_matched, action: :mark_matched
      define :ignore_bank_transaction, action: :ignore
      define :reopen_bank_transaction_review, action: :reopen_review

      define :get_bank_transaction_workspace,
        action: :transaction_workspace,
        args: [:bank_transaction_id]
    end

    resource GnomeGarden.Banking.BankTransactionMatch do
      define :list_bank_transaction_matches, action: :read
      define :get_bank_transaction_match, action: :read, get_by: [:id]

      define :list_bank_transaction_matches_for_transaction,
        action: :for_transaction,
        args: [:bank_transaction_id]

      define :list_proposed_bank_transaction_matches, action: :proposed
      define :create_bank_transaction_match, action: :create
      define :accept_bank_transaction_match, action: :accept
      define :reject_bank_transaction_match, action: :reject
      define :supersede_bank_transaction_match, action: :supersede
    end

    resource GnomeGarden.Banking.BankRule do
      define :list_bank_rules, action: :read
      define :list_bank_rules_sorted, action: :sorted
      define :get_bank_rule, action: :read, get_by: [:id]
      define :create_bank_rule, action: :create

      define :create_bank_rule_from_transaction,
        action: :create_from_transaction,
        args: [:bank_transaction_id]

      define :update_bank_rule, action: :update
      define :enable_bank_rule, action: :enable
      define :disable_bank_rule, action: :disable
      define :reorder_bank_rule, action: :reorder
      define :delete_bank_rule, action: :destroy
    end

    resource GnomeGarden.Banking.BankCounterpartyAlias do
      define :list_bank_counterparty_aliases, action: :read
      define :get_bank_counterparty_alias, action: :read, get_by: [:id]

      define :list_bank_counterparty_aliases_for_counterparty,
        action: :matching_counterparty,
        args: [:counterparty_name]

      define :create_bank_counterparty_alias, action: :create
      define :confirm_bank_counterparty_alias, action: :confirm
      define :ignore_bank_counterparty_alias, action: :ignore
      define :merge_bank_counterparty_alias, action: :merge
    end

    resource GnomeGarden.Banking.BankIntegrationEvent do
      define :list_bank_integration_events, action: :read
      define :list_recent_bank_integration_events, action: :recent
      define :list_bank_integration_event_history, action: :history

      define :list_recent_bank_integration_events_for_account,
        action: :recent_for_account,
        args: [:bank_account_id]

      define :get_bank_integration_event, action: :read, get_by: [:id]
      define :record_bank_integration_event, action: :record
      define :process_bank_integration_event, action: :process
      define :mark_bank_integration_event_processed, action: :mark_processed
      define :mark_bank_integration_event_failed, action: :mark_failed
      define :ignore_bank_integration_event, action: :ignore
      define :retry_bank_integration_event, action: :retry
    end

    resource GnomeGarden.Banking.BankTransactionEvent do
      define :list_bank_transaction_events, action: :read
      define :record_bank_transaction_event, action: :record

      define :list_bank_transaction_events_for_transaction,
        action: :for_transaction,
        args: [:bank_transaction_id]
    end

    resource GnomeGarden.Banking.BankSyncRun do
      define :list_bank_sync_runs, action: :read
      define :list_recent_bank_sync_runs, action: :recent
      define :get_bank_sync_run, action: :read, get_by: [:id]

      define :list_bank_sync_runs_for_connection,
        action: :for_connection,
        args: [:bank_connection_id]

      define :start_bank_sync_run, action: :start
      define :finish_bank_sync_run_success, action: :finish_success
      define :finish_bank_sync_run_failure, action: :finish_failure
      define :get_bank_sync_history_workspace, action: :sync_history_workspace
    end
  end
end
