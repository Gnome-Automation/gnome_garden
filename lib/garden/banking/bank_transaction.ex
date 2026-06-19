defmodule GnomeGarden.Banking.BankTransaction do
  @moduledoc """
  A transaction synced from a provider bank account. `review_status` drives the
  reconciliation queue (a state machine); `status` mirrors the provider's own
  transaction status. Amounts are `:money`.

  Reconciliation against the ledger happens through `BankTransactionMatch`,
  which links a transaction to a `GnomeGarden.Ledger.JournalEntry`.
  """

  use Ash.Resource,
    otp_app: :gnome_garden,
    domain: GnomeGarden.Banking,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshAdmin.Resource, AshStateMachine]

  admin do
    table_columns [
      :id,
      :provider,
      :provider_transaction_id,
      :amount,
      :direction,
      :status,
      :review_status,
      :counterparty_name,
      :occurred_at
    ]
  end

  postgres do
    table "banking_transactions"
    repo GnomeGarden.Repo

    references do
      reference :bank_account, on_delete: :delete
    end
  end

  state_machine do
    state_attribute :review_status
    initial_states [:unreviewed, :matched]
    default_initial_state :unreviewed

    transitions do
      transition :mark_reviewed, from: [:unreviewed, :matched], to: :reviewed
      transition :ignore, from: [:unreviewed, :reviewed], to: :ignored
      transition :mark_matched, from: [:unreviewed, :reviewed], to: :matched
      transition :reopen_review, from: [:reviewed, :ignored, :matched], to: :unreviewed
    end
  end

  actions do
    defaults [:read]

    create :create do
      primary? true

      accept [
        :bank_account_id,
        :provider,
        :provider_transaction_id,
        :amount,
        :direction,
        :status,
        :description,
        :counterparty_name,
        :category,
        :kind,
        :memo,
        :counterparty_id,
        :counterparty_account_last4,
        :dashboard_link,
        :posted_at,
        :occurred_at
      ]
    end

    create :upsert do
      upsert? true
      upsert_identity :unique_provider_transaction

      accept [
        :bank_account_id,
        :provider,
        :provider_transaction_id,
        :amount,
        :direction,
        :status,
        :description,
        :counterparty_name,
        :category,
        :kind,
        :memo,
        :counterparty_id,
        :counterparty_account_last4,
        :dashboard_link,
        :posted_at,
        :occurred_at
      ]
    end

    update :update do
      accept [
        :amount,
        :direction,
        :status,
        :description,
        :counterparty_name,
        :category,
        :kind,
        :memo,
        :counterparty_id,
        :counterparty_account_last4,
        :dashboard_link,
        :posted_at,
        :occurred_at
      ]
    end

    update :categorize do
      accept [:category, :reconciliation_note]
    end

    update :mark_reviewed do
      accept [:reconciliation_note]
      change transition_state(:reviewed)
    end

    update :ignore do
      accept [:reconciliation_note]
      change transition_state(:ignored)
    end

    update :mark_matched do
      accept []
      change transition_state(:matched)
      change set_attribute(:match_status, :matched)
    end

    update :reopen_review do
      accept []
      change transition_state(:unreviewed)
    end

    read :needs_review do
      filter expr(review_status == :unreviewed)
      prepare build(sort: [occurred_at: :desc])
    end

    read :for_account do
      argument :bank_account_id, :uuid, allow_nil?: false
      filter expr(bank_account_id == ^arg(:bank_account_id))
      prepare build(sort: [occurred_at: :desc])
    end

    # Backs the reconciliation review-queue Cinder table.
    read :review_queue_page do
      pagination keyset?: true, offset?: true, required?: false, default_limit: 25
      filter expr(review_status == :unreviewed)
      prepare build(sort: [occurred_at: :desc], load: [:bank_account])
    end

    action :transaction_workspace, :map do
      argument :bank_transaction_id, :uuid, allow_nil?: false
      run GnomeGarden.Banking.Actions.BuildBankTransactionWorkspace
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :provider, :atom do
      allow_nil? false
      public? true
      constraints one_of: [:mercury]
    end

    attribute :provider_transaction_id, :string do
      allow_nil? false
      public? true
    end

    attribute :amount, :money do
      allow_nil? false
      public? true
    end

    attribute :direction, :atom do
      public? true
      constraints one_of: [:credit, :debit]
    end

    attribute :status, :atom do
      public? true
      constraints one_of: [:pending, :sent, :cancelled, :failed]
    end

    attribute :review_status, :atom do
      allow_nil? false
      default :unreviewed
      public? true
      constraints one_of: [:unreviewed, :reviewed, :ignored, :matched]
    end

    attribute :description, :string do
      public? true
    end

    attribute :counterparty_name, :string do
      public? true
    end

    attribute :category, :string do
      public? true
    end

    attribute :reconciliation_note, :string do
      public? true
    end

    # Denormalized match state for quick display (authoritative matches live in
    # BankTransactionMatch). Set to :matched by mark_matched.
    attribute :match_status, :atom do
      allow_nil? false
      default :unmatched
      public? true
      constraints one_of: [:unmatched, :suggested, :matched]
    end

    attribute :kind, :string, public?: true
    attribute :memo, :string, public?: true
    attribute :counterparty_id, :string, public?: true
    attribute :counterparty_account_last4, :string, public?: true
    attribute :dashboard_link, :string, public?: true

    attribute :posted_at, :utc_datetime do
      public? true
    end

    attribute :occurred_at, :utc_datetime do
      public? true
    end

    timestamps()
  end

  relationships do
    belongs_to :bank_account, GnomeGarden.Banking.BankAccount do
      allow_nil? false
      public? true
    end

    has_many :bank_transaction_matches, GnomeGarden.Banking.BankTransactionMatch do
      public? true
    end

    has_many :bank_transaction_events, GnomeGarden.Banking.BankTransactionEvent do
      public? true
    end
  end

  identities do
    identity :unique_provider_transaction, [:provider, :provider_transaction_id]
  end
end
