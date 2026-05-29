defmodule GnomeGarden.Finance.JournalEntryLine do
  @moduledoc """
  A single debit or credit line within a journal entry.

  Exactly one of `debit` or `credit` must be non-nil and positive per line.
  """

  use Ash.Resource,
    otp_app: :gnome_garden,
    domain: GnomeGarden.Finance,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "finance_journal_entry_lines"
    repo GnomeGarden.Repo

    references do
      reference :journal_entry, on_delete: :delete
      reference :account, on_delete: :restrict
    end
  end

  actions do
    defaults [:read]

    create :create do
      primary? true
      accept [:journal_entry_id, :account_id, :debit, :credit, :description]

      validate fn changeset, _context ->
        debit = Ash.Changeset.get_attribute(changeset, :debit)
        credit = Ash.Changeset.get_attribute(changeset, :credit)

        cond do
          is_nil(debit) && is_nil(credit) ->
            {:error, message: "either debit or credit must be provided"}

          !is_nil(debit) && !is_nil(credit) ->
            {:error, message: "only one of debit or credit may be provided"}

          !is_nil(debit) && not Decimal.positive?(debit) ->
            {:error, field: :debit, message: "debit must be positive"}

          !is_nil(credit) && not Decimal.positive?(credit) ->
            {:error, field: :credit, message: "credit must be positive"}

          true ->
            :ok
        end
      end
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :debit, :decimal do
      public? true
    end

    attribute :credit, :decimal do
      public? true
    end

    attribute :description, :string do
      public? true
    end

    timestamps()
  end

  relationships do
    belongs_to :journal_entry, GnomeGarden.Finance.JournalEntry do
      allow_nil? false
    end

    belongs_to :account, GnomeGarden.Finance.ChartOfAccount do
      allow_nil? false
    end
  end
end
