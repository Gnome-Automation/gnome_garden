defmodule GnomeGarden.Ledger.Account do
  @moduledoc """
  A node in the chart of accounts.

  Each account has a `type` (asset/liability/equity/revenue/expense) and a
  `normal_balance` (the side that increases it). System accounts (AR, cash,
  revenue, tax payable, …) are flagged `system?` and cannot be destroyed.
  """

  use Ash.Resource,
    otp_app: :gnome_garden,
    domain: GnomeGarden.Ledger,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshAdmin.Resource]

  admin do
    table_columns [
      :id,
      :number,
      :name,
      :type,
      :normal_balance,
      :system?,
      :active?
    ]
  end

  postgres do
    table "ledger_accounts"
    repo GnomeGarden.Repo
  end

  actions do
    defaults [:read]

    create :create do
      primary? true

      accept [
        :number,
        :name,
        :type,
        :normal_balance,
        :description,
        :system?,
        :active?
      ]
    end

    update :update do
      accept [
        :name,
        :description,
        :active?
      ]
    end

    destroy :destroy do
      require_atomic? false
      validate GnomeGarden.Ledger.Account.Validations.NotSystemAccount
    end

    read :active do
      filter expr(active? == true)
      prepare build(sort: [number: :asc])
    end

    action :trial_balance, :map do
      argument :as_of, :date, default: &Date.utc_today/0
      run GnomeGarden.Ledger.Actions.BuildTrialBalance
    end

    action :balance_sheet, :map do
      argument :as_of, :date, default: &Date.utc_today/0
      run GnomeGarden.Ledger.Actions.BuildBalanceSheet
    end

    action :income_statement, :map do
      argument :from, :date, allow_nil?: false
      argument :to, :date, allow_nil?: false
      run GnomeGarden.Ledger.Actions.BuildIncomeStatement
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :number, :string do
      allow_nil? false
      public? true
    end

    attribute :name, :string do
      allow_nil? false
      public? true
    end

    attribute :type, :atom do
      allow_nil? false
      public? true
      constraints one_of: [:asset, :liability, :equity, :revenue, :expense]
    end

    attribute :normal_balance, :atom do
      allow_nil? false
      public? true
      constraints one_of: [:debit, :credit]
    end

    attribute :description, :string do
      public? true
    end

    attribute :system?, :boolean do
      allow_nil? false
      default false
      public? true
    end

    attribute :active?, :boolean do
      allow_nil? false
      default true
      public? true
    end

    timestamps()
  end

  relationships do
    has_many :journal_lines, GnomeGarden.Ledger.JournalLine do
      public? true
    end
  end

  identities do
    identity :unique_number, [:number]
  end
end
