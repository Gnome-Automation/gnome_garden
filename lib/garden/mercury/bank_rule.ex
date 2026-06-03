# lib/garden/mercury/bank_rule.ex
defmodule GnomeGarden.Mercury.BankRule do
  use Ash.Resource,
    otp_app: :gnome_garden,
    domain: GnomeGarden.Mercury,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshAdmin.Resource]

  @moduledoc """
  A user-defined rule that automatically categorizes Mercury transactions.

  Rules are evaluated in priority order (lowest first) against each new
  incoming transaction. The first matching rule wins and sets
  reconciliation_category + reconciliation_note on the transaction.
  """

  admin do
    table_columns [:id, :name, :priority, :direction, :counterparty_contains, :reconciliation_category, :inserted_at]
  end

  postgres do
    table "mercury_bank_rules"
    repo GnomeGarden.Repo
  end

  actions do
    defaults [:read, :create, :update, :destroy]
  end

  attributes do
    uuid_primary_key :id

    attribute :name, :string do
      allow_nil? false
      public? true
    end

    attribute :priority, :integer do
      allow_nil? false
      default 0
      public? true
    end

    attribute :direction, :atom do
      allow_nil? false
      public? true
      constraints one_of: [:money_in, :money_out, :both]
    end

    attribute :counterparty_contains, :string do
      allow_nil? true
      public? true
      description "Case-insensitive substring match on counterparty_name. If nil, matches any counterparty."
    end

    attribute :amount_operator, :atom do
      allow_nil? true
      public? true
      constraints one_of: [:lt, :gt, :lte, :gte, :eq]
    end

    attribute :amount_value, :decimal do
      allow_nil? true
      public? true
      description "Used with amount_operator. Compared against abs(transaction.amount)."
    end

    attribute :reconciliation_category, :atom do
      allow_nil? false
      public? true
      constraints one_of: [
        :bank_fee,
        :internal_transfer,
        :misc_income,
        :refund,
        :interest_income,
        :owner_draw,
        :other
      ]
    end

    attribute :auto_note, :string do
      allow_nil? true
      public? true
      description "Default reconciliation_note to set on matched transactions. If nil, note is left nil."
    end

    timestamps()
  end
end
