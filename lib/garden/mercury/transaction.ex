defmodule GnomeGarden.Mercury.Transaction do
  use Ash.Resource,
    otp_app: :gnome_garden,
    domain: GnomeGarden.Mercury,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshAdmin.Resource]

  @moduledoc """
  A Mercury bank transaction.

  Transactions are inserted by the webhook receiver on `transaction.created`
  events and updated on `transaction.updated` events. Status is owned by
  Mercury — this resource only mirrors Mercury's state.
  """

  admin do
    table_columns [:id, :mercury_id, :amount, :kind, :status, :counterparty_name, :match_confidence, :occurred_at]
  end

  postgres do
    table "mercury_transactions"
    repo GnomeGarden.Repo

    references do
      reference :account, on_delete: :delete
    end
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true

      accept [
        :mercury_id,
        :account_id,
        :amount,
        :kind,
        :status,
        :bank_description,
        :external_memo,
        :counterparty_id,
        :counterparty_name,
        :counterparty_nickname,
        :note,
        :details,
        :currency_exchange_info,
        :reason_for_failure,
        :dashboard_link,
        :fee_id,
        :estimated_delivery_date,
        :posted_date,
        :failed_at,
        :occurred_at,
        :company_id
      ]
    end

    update :update do
      primary? true

      accept [
        :status,
        :bank_description,
        :external_memo,
        :note,
        :details,
        :currency_exchange_info,
        :reason_for_failure,
        :dashboard_link,
        :posted_date,
        :failed_at,
        :company_id,
        :match_confidence
      ]
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :mercury_id, :string do
      allow_nil? false
      public? true
    end

    attribute :amount, :decimal do
      allow_nil? false
      public? true
    end

    attribute :kind, :atom do
      allow_nil? false
      public? true
      constraints one_of: [:external_transfer, :internal_transfer, :outbound, :inbound, :fee, :ach, :wire, :check, :other]
    end

    attribute :status, :atom do
      allow_nil? false
      public? true
      constraints one_of: [:pending, :sent, :cancelled, :failed]
    end

    attribute :bank_description, :string, public?: true
    attribute :external_memo, :string, public?: true
    attribute :counterparty_id, :string, public?: true
    attribute :counterparty_name, :string, public?: true
    attribute :counterparty_nickname, :string, public?: true
    attribute :note, :string, public?: true
    attribute :details, :map, public?: true
    attribute :currency_exchange_info, :map, public?: true
    attribute :reason_for_failure, :string, public?: true
    attribute :dashboard_link, :string, public?: true
    attribute :fee_id, :string, public?: true
    attribute :estimated_delivery_date, :date, public?: true
    attribute :posted_date, :date, public?: true
    attribute :failed_at, :utc_datetime_usec, public?: true

    attribute :occurred_at, :utc_datetime_usec do
      allow_nil? false
      public? true
    end

    attribute :company_id, :uuid, public?: true

    attribute :match_confidence, :atom do
      public? true
      constraints one_of: [:exact, :probable, :possible, :unmatched]
    end

    timestamps()
  end

  identities do
    identity :unique_mercury_id, [:mercury_id]
  end

  relationships do
    belongs_to :account, GnomeGarden.Mercury.Account do
      allow_nil? false
      public? true
    end

    has_many :payment_matches, GnomeGarden.Mercury.PaymentMatch do
      destination_attribute :mercury_transaction_id
      public? true
    end
  end
end
