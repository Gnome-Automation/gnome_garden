defmodule GnomeGarden.Finance.JournalEntry do
  @moduledoc """
  Double-entry journal entry header.

  Auto-posted entries (from notifiers) are created with `status: :posted` directly.
  Manual entries start as `:draft` and are posted via the `:post` action.
  Posted entries are immutable — corrections are made via new manual reversal entries.
  """

  use Ash.Resource,
    otp_app: :gnome_garden,
    domain: GnomeGarden.Finance,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "finance_journal_entries"
    repo GnomeGarden.Repo
  end

  actions do
    defaults [:read]

    create :create do
      primary? true

      accept [
        :date,
        :description,
        :entry_type,
        :status,
        :reference_id,
        :reference_type
      ]

      change GnomeGarden.Finance.Changes.GenerateEntryNumber
    end

    update :post do
      accept []
      require_atomic? false

      validate fn changeset, _context ->
        entry = Ash.Changeset.get_data(changeset, :status)

        if entry == :posted do
          {:error, field: :status, message: "entry is already posted"}
        else
          :ok
        end
      end

      change fn changeset, _context ->
        # Lines must be loaded before calling post
        lines = Ash.Changeset.get_data(changeset, :lines) || []

        total_debits =
          lines
          |> Enum.map(& &1.debit)
          |> Enum.reject(&is_nil/1)
          |> Enum.reduce(Decimal.new("0"), &Decimal.add/2)

        total_credits =
          lines
          |> Enum.map(& &1.credit)
          |> Enum.reject(&is_nil/1)
          |> Enum.reduce(Decimal.new("0"), &Decimal.add/2)

        if Decimal.equal?(total_debits, total_credits) && Decimal.positive?(total_debits) do
          Ash.Changeset.change_attribute(changeset, :status, :posted)
        else
          Ash.Changeset.add_error(changeset,
            field: :lines,
            message: "debits must equal credits and be greater than zero"
          )
        end
      end
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
      allow_nil? false
      public? true
    end

    attribute :entry_type, :atom do
      allow_nil? false
      default :manual
      public? true

      constraints one_of: [
                    :manual,
                    :invoice_issued,
                    :payment_received,
                    :credit_note_issued,
                    :invoice_voided,
                    :invoice_written_off,
                    :expense_approved,
                    :retainer_received,
                    :retainer_applied,
                    :retainer_unapplied,
                    :retainer_voided
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

    timestamps()
  end

  relationships do
    has_many :lines, GnomeGarden.Finance.JournalEntryLine
  end
end
