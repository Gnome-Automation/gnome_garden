defmodule GnomeGarden.Banking.BankRule do
  @moduledoc """
  Provider-neutral rule for categorizing and matching bank transactions.

  Rules are evaluated in `priority` order (lowest first). A rule matches when the
  transaction's direction, counterparty, description, and amount all satisfy the
  rule's (optional) conditions; the first matching enabled rule applies its
  `category`, sets the resulting `review_status_result`, and drives match
  behavior (`:none` / `:suggest` / `:auto_accept_when_exact`).
  """

  use Ash.Resource,
    otp_app: :gnome_garden,
    domain: GnomeGarden.Banking,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshAdmin.Resource]

  admin do
    table_columns [:id, :name, :enabled, :priority, :direction, :counterparty_contains, :category, :match_behavior]
  end

  postgres do
    table "banking_rules"
    repo GnomeGarden.Repo
  end

  actions do
    defaults [:read, :destroy]

    read :sorted do
      filter expr(enabled == true)
      prepare build(sort: [priority: :asc, inserted_at: :asc])
    end

    action :create_from_transaction, :map do
      argument :bank_transaction_id, :uuid, allow_nil?: false
      run GnomeGarden.Banking.Actions.CreateBankRuleFromTransaction
    end

    create :create do
      primary? true

      accept [
        :name,
        :enabled,
        :priority,
        :direction,
        :description_contains,
        :counterparty_contains,
        :amount_operator,
        :amount_value,
        :category,
        :review_status_result,
        :match_behavior,
        :auto_note
      ]
    end

    update :update do
      primary? true

      accept [
        :name,
        :enabled,
        :priority,
        :direction,
        :description_contains,
        :counterparty_contains,
        :amount_operator,
        :amount_value,
        :category,
        :review_status_result,
        :match_behavior,
        :auto_note
      ]
    end

    update :enable do
      accept []
      change set_attribute(:enabled, true)
    end

    update :disable do
      accept []
      change set_attribute(:enabled, false)
    end

    update :reorder do
      accept [:priority]
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :name, :string do
      allow_nil? false
      public? true
    end

    attribute :enabled, :boolean do
      allow_nil? false
      default true
      public? true
    end

    attribute :priority, :integer do
      allow_nil? false
      default 0
      public? true
    end

    attribute :direction, :atom do
      allow_nil? false
      default :both
      public? true
      constraints one_of: [:credit, :debit, :both]
    end

    attribute :description_contains, :string, public?: true
    attribute :counterparty_contains, :string, public?: true

    attribute :amount_operator, :atom do
      public? true
      constraints one_of: [:lt, :gt, :lte, :gte, :eq]
    end

    attribute :amount_value, :decimal, public?: true

    attribute :category, :atom do
      allow_nil? false
      default :unknown
      public? true

      constraints one_of: [
                    :customer_payment,
                    :vendor_payment,
                    :bank_fee,
                    :internal_transfer,
                    :misc_income,
                    :refund,
                    :interest_income,
                    :owner_draw,
                    :payroll,
                    :tax,
                    :unknown,
                    :other
                  ]
    end

    # Values mirror PR #41's rule form; mapped to BankTransaction.review_status
    # in the reconciliation engine (:needs_review -> :unreviewed,
    # :auto_matched -> :matched).
    attribute :review_status_result, :atom do
      allow_nil? false
      default :reviewed
      public? true
      constraints one_of: [:needs_review, :auto_matched, :reviewed, :ignored]
    end

    attribute :match_behavior, :atom do
      allow_nil? false
      default :none
      public? true
      constraints one_of: [:none, :suggest, :auto_accept_when_exact]
    end

    attribute :auto_note, :string, public?: true

    timestamps()
  end
end
