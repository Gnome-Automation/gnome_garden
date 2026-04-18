defmodule GnomeGarden.Finance.PaymentApplication do
  @moduledoc """
  Allocation of a payment to an invoice.
  """

  use Ash.Resource,
    otp_app: :gnome_garden,
    domain: GnomeGarden.Finance,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshAdmin.Resource]

  admin do
    table_columns [
      :id,
      :payment_id,
      :invoice_id,
      :amount,
      :applied_on
    ]
  end

  postgres do
    table "finance_payment_applications"
    repo GnomeGarden.Repo

    references do
      reference :payment, on_delete: :delete
      reference :invoice, on_delete: :delete
    end
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true

      accept [
        :payment_id,
        :invoice_id,
        :amount,
        :applied_on,
        :notes
      ]
    end

    update :update do
      accept [
        :payment_id,
        :invoice_id,
        :amount,
        :applied_on,
        :notes
      ]
    end

    read :for_invoice do
      argument :invoice_id, :uuid, allow_nil?: false
      filter expr(invoice_id == ^arg(:invoice_id))
      prepare build(sort: [applied_on: :asc, inserted_at: :asc], load: [:payment, :invoice])
    end

    read :for_payment do
      argument :payment_id, :uuid, allow_nil?: false
      filter expr(payment_id == ^arg(:payment_id))
      prepare build(sort: [applied_on: :asc, inserted_at: :asc], load: [:payment, :invoice])
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :amount, :decimal do
      allow_nil? false
      public? true
    end

    attribute :applied_on, :date do
      public? true
    end

    attribute :notes, :string do
      public? true
    end

    timestamps()
  end

  relationships do
    belongs_to :payment, GnomeGarden.Finance.Payment do
      allow_nil? false
      public? true
    end

    belongs_to :invoice, GnomeGarden.Finance.Invoice do
      allow_nil? false
      public? true
    end
  end

  identities do
    identity :unique_payment_invoice_pair, [:payment_id, :invoice_id]
  end
end
