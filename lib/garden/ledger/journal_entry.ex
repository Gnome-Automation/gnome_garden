defmodule GnomeGarden.Ledger.JournalEntry do
  @moduledoc """
  Double-entry journal entry header.

  Auto-posted entries (from `GnomeGarden.Finance` events) are created already
  `:posted` via `:post_entry`. Manual entries start `:draft` and are posted with
  the `:post` action. Posted entries are immutable — there is no update or
  destroy action for them; corrections are made with new reversing entries.

  An entry only posts if its lines balance: total debits must equal total
  credits (and be positive). That invariant is enforced by
  `GnomeGarden.Ledger.JournalEntry.Validations.BalancedEntry`.
  """

  use Ash.Resource,
    otp_app: :gnome_garden,
    domain: GnomeGarden.Ledger,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshAdmin.Resource, AshStateMachine]

  admin do
    table_columns [
      :id,
      :entry_number,
      :date,
      :entry_type,
      :status,
      :reference_type,
      :reference_id,
      :posted_at
    ]
  end

  postgres do
    table "ledger_journal_entries"
    repo GnomeGarden.Repo

    # One posted entry per business event. Prevents double-posting (e.g. an
    # invoice issued, reopened, then re-issued). Manual entries carry no
    # reference and are exempt via the partial WHERE clause.
    custom_indexes do
      index [:reference_type, :reference_id, :entry_type],
        unique: true,
        where: "reference_id IS NOT NULL",
        name: "ledger_journal_entries_unique_business_event"
    end
  end

  state_machine do
    state_attribute :status
    initial_states [:draft, :posted]
    default_initial_state :draft

    transitions do
      transition :post, from: :draft, to: :posted
    end
  end

  actions do
    defaults [:read]

    create :create do
      primary? true

      accept [
        :date,
        :description,
        :entry_type,
        :reference_id,
        :reference_type
      ]

      argument :lines, {:array, :map}, allow_nil?: true

      change GnomeGarden.Ledger.Changes.GenerateEntryNumber
      change manage_relationship(:lines, :journal_lines, type: :create)
    end

    create :post_entry do
      accept [
        :date,
        :description,
        :entry_type,
        :reference_id,
        :reference_type
      ]

      argument :lines, {:array, :map}, allow_nil?: false

      change transition_state(:posted)
      change set_attribute(:posted_at, &DateTime.utc_now/0)
      change GnomeGarden.Ledger.Changes.GenerateEntryNumber
      change manage_relationship(:lines, :journal_lines, type: :create)

      validate GnomeGarden.Ledger.JournalEntry.Validations.BalancedEntry
    end

    update :post do
      require_atomic? false
      accept []

      change transition_state(:posted)
      change set_attribute(:posted_at, &DateTime.utc_now/0)

      validate GnomeGarden.Ledger.JournalEntry.Validations.BalancedEntry
    end

    create :reverse do
      accept [:date]
      argument :original_entry_id, :uuid, allow_nil?: false

      change transition_state(:posted)
      change set_attribute(:posted_at, &DateTime.utc_now/0)
      change GnomeGarden.Ledger.Changes.GenerateEntryNumber
      change GnomeGarden.Ledger.Changes.BuildReversal
    end

    read :posted do
      filter expr(status == :posted)
      prepare build(sort: [date: :desc, inserted_at: :desc])
    end

    read :posted_through do
      argument :as_of, :date, allow_nil?: false
      filter expr(status == :posted and date <= ^arg(:as_of))
      prepare build(sort: [date: :asc], load: [journal_lines: [:account]])
    end

    read :posted_between do
      argument :from, :date, allow_nil?: false
      argument :to, :date, allow_nil?: false
      filter expr(status == :posted and date >= ^arg(:from) and date <= ^arg(:to))
      prepare build(sort: [date: :asc], load: [journal_lines: [:account]])
    end

    read :for_reference do
      argument :reference_type, :string, allow_nil?: false
      argument :reference_id, :uuid, allow_nil?: false

      filter expr(reference_type == ^arg(:reference_type) and reference_id == ^arg(:reference_id))
      prepare build(sort: [inserted_at: :asc])
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :entry_number, :string do
      allow_nil? false
      public? true
    end

    attribute :date, :date do
      allow_nil? false
      public? true
    end

    attribute :description, :string do
      public? true
    end

    attribute :entry_type, :atom do
      allow_nil? false
      public? true

      constraints one_of: [
                    :invoice_issued,
                    :invoice_voided,
                    :payment_received,
                    :payment_reversed,
                    :credit_note,
                    :retainer_issued,
                    :retainer_applied,
                    :vendor_bill,
                    :vendor_payment,
                    :expense,
                    :manual,
                    :adjustment,
                    :reversal
                  ]
    end

    attribute :status, :atom do
      allow_nil? false
      default :draft
      public? true
      constraints one_of: [:draft, :posted]
    end

    attribute :reference_id, :uuid do
      public? true
    end

    attribute :reference_type, :string do
      public? true
    end

    attribute :posted_at, :utc_datetime do
      public? true
    end

    timestamps()
  end

  relationships do
    has_many :journal_lines, GnomeGarden.Ledger.JournalLine do
      public? true
    end
  end

  calculations do
    calculate :status_variant,
              :atom,
              {GnomeGarden.Calculations.EnumVariant,
               field: :status,
               mapping: [
                 draft: :default,
                 posted: :success
               ],
               default: :default}
  end

  aggregates do
    # Single-currency (USD) for now — the currency filter prevents the
    # money_with_currency operators from raising on mixed-currency rows and
    # excludes the nil side of each line.
    sum :total_debits, :journal_lines, :debit do
      public? true
      filter expr(debit[:currency] == "USD")
    end

    sum :total_credits, :journal_lines, :credit do
      public? true
      filter expr(credit[:currency] == "USD")
    end
  end

  identities do
    identity :unique_entry_number, [:entry_number]
  end
end
