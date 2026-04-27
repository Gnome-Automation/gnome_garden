defmodule GnomeGarden.Mercury.PaymentMatch do
  use Ash.Resource,
    otp_app: :gnome_garden,
    domain: GnomeGarden.Mercury,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshAdmin.Resource]

  @moduledoc """
  Links a Mercury bank transaction to a Finance.Payment record.

  Created by MercuryPaymentMatcher (Oban job) with match_source: :auto,
  or manually corrected with match_source: :manual.
  A single Mercury transaction can match multiple Finance.Payment records
  (e.g. one wire covering two invoices).

  To undo a wrong match, destroy the record and create a correct one.
  """

  admin do
    table_columns [:id, :mercury_transaction_id, :finance_payment_id, :match_source, :matched_at]
  end

  postgres do
    table "mercury_payment_matches"
    repo GnomeGarden.Repo

    references do
      reference :mercury_transaction, on_delete: :delete
      reference :finance_payment, on_delete: :delete
    end
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true
      accept [:match_source, :mercury_transaction_id, :finance_payment_id]
      change set_attribute(:matched_at, &DateTime.utc_now/0)
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :match_source, :atom do
      allow_nil? false
      public? true
      constraints one_of: [:auto, :manual]
    end

    attribute :matched_at, :utc_datetime_usec do
      allow_nil? false
      public? true
    end

    timestamps()
  end

  identities do
    identity :unique_transaction_payment_pair, [:mercury_transaction_id, :finance_payment_id]
  end

  relationships do
    belongs_to :mercury_transaction, GnomeGarden.Mercury.Transaction do
      allow_nil? false
      public? true
    end

    belongs_to :finance_payment, GnomeGarden.Finance.Payment do
      allow_nil? false
      public? true
    end
  end
end
