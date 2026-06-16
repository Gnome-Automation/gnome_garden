defmodule GnomeGarden.Finance.BankTransactionMatch do
  @moduledoc """
  Match between an imported bank transaction and Finance payment state.
  """

  use Ash.Resource,
    otp_app: :gnome_garden,
    domain: GnomeGarden.Finance,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshAdmin.Resource]

  alias GnomeGarden.Finance

  admin do
    table_columns [
      :id,
      :bank_transaction_id,
      :payment_id,
      :invoice_id,
      :match_source,
      :status,
      :confidence,
      :matched_at
    ]
  end

  postgres do
    table "finance_bank_transaction_matches"
    repo GnomeGarden.Repo
    identity_index_names unique_bank_transaction_payment: "finance_bank_txn_payment_uidx"

    references do
      reference :bank_transaction, on_delete: :delete
      reference :payment, on_delete: :delete
      reference :invoice, on_delete: :nilify
    end
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true

      accept [
        :bank_transaction_id,
        :payment_id,
        :invoice_id,
        :match_source,
        :status,
        :confidence,
        :notes
      ]
    end

    read :for_transaction do
      argument :bank_transaction_id, :uuid, allow_nil?: false

      filter expr(bank_transaction_id == ^arg(:bank_transaction_id))
      prepare build(sort: [inserted_at: :asc], load: [:payment, :invoice])
    end

    update :accept do
      require_atomic? false

      accept [:notes]
      change set_attribute(:status, :accepted)
      change set_attribute(:matched_at, &DateTime.utc_now/0)
      change after_action(&sync_transaction_for_match(&1, &2, &3, :accept))
    end

    update :reject do
      require_atomic? false

      accept [:notes]
      change set_attribute(:status, :rejected)
      change after_action(&sync_transaction_for_match(&1, &2, &3, :reject))
    end

    update :supersede do
      require_atomic? false

      accept [:notes]
      change set_attribute(:status, :superseded)
      change after_action(&sync_transaction_for_match(&1, &2, &3, :supersede))
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :match_source, :atom do
      allow_nil? false
      public? true
      constraints one_of: [:rule, :amount_date, :operator, :sync, :ai]
    end

    attribute :status, :atom do
      allow_nil? false
      default :suggested
      public? true
      constraints one_of: [:suggested, :accepted, :rejected, :superseded]
    end

    attribute :confidence, :atom do
      allow_nil? false
      default :possible
      public? true
      constraints one_of: [:exact, :probable, :possible, :manual]
    end

    attribute :matched_at, :utc_datetime_usec, public?: true
    attribute :notes, :string, public?: true

    timestamps()
  end

  relationships do
    belongs_to :bank_transaction, GnomeGarden.Finance.BankTransaction do
      allow_nil? false
      public? true
    end

    belongs_to :payment, GnomeGarden.Finance.Payment do
      allow_nil? false
      public? true
    end

    belongs_to :invoice, GnomeGarden.Finance.Invoice do
      public? true
    end
  end

  identities do
    identity :unique_bank_transaction_payment, [:bank_transaction_id, :payment_id]
  end

  defp sync_transaction_for_match(changeset, match, context, :accept) do
    with {:ok, transaction} <- load_transaction(match, context.actor),
         {:ok, _transaction} <-
           Finance.mark_bank_transaction_matched(
             transaction,
             %{reconciliation_note: match_note(changeset, match)},
             actor: context.actor,
             authorize?: false
           ) do
      {:ok, match}
    end
  end

  defp sync_transaction_for_match(changeset, match, context, :reject) do
    with {:ok, transaction} <- load_transaction(match, context.actor),
         {:ok, _transaction} <-
           Finance.mark_bank_transaction_unmatched(
             transaction,
             %{reconciliation_note: match_note(changeset, match)},
             actor: context.actor,
             authorize?: false
           ) do
      {:ok, match}
    end
  end

  defp sync_transaction_for_match(_changeset, match, _context, :supersede) do
    {:ok, match}
  end

  defp load_transaction(match, actor) do
    Finance.get_bank_transaction(match.bank_transaction_id, actor: actor, authorize?: false)
  end

  defp match_note(changeset, match) do
    Ash.Changeset.get_attribute(changeset, :notes) ||
      match.notes ||
      "Bank transaction match #{match.status}"
  end
end
