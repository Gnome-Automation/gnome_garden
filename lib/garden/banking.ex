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
    end

    resource GnomeGarden.Banking.BankTransactionMatch do
      define :list_bank_transaction_matches, action: :read
      define :get_bank_transaction_match, action: :read, get_by: [:id]

      define :list_bank_transaction_matches_for_transaction,
        action: :for_transaction,
        args: [:bank_transaction_id]

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
      define :update_bank_rule, action: :update
      define :enable_bank_rule, action: :enable
      define :disable_bank_rule, action: :disable
      define :delete_bank_rule, action: :destroy
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
    end
  end
end
