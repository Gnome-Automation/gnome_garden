defmodule GnomeGarden.Finance.BankTransaction do
  @moduledoc """
  Provider-neutral bank transaction imported into Finance.
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
      :provider,
      :provider_transaction_id,
      :amount,
      :direction,
      :status,
      :counterparty_name,
      :category,
      :review_status,
      :match_status,
      :occurred_at
    ]
  end

  postgres do
    table "finance_bank_transactions"
    repo GnomeGarden.Repo

    references do
      reference :bank_account, on_delete: :delete
    end
  end

  actions do
    defaults [:read, :destroy]

    read :needs_review do
      filter expr(review_status == :needs_review)
      prepare build(sort: [occurred_at: :desc, inserted_at: :desc])
    end

    read :needs_review_page do
      filter expr(review_status == :needs_review)
      pagination offset?: true, keyset?: true, default_limit: 25
      prepare build(sort: [occurred_at: :desc, inserted_at: :desc])
    end

    create :create do
      primary? true

      accept [
        :bank_account_id,
        :provider,
        :provider_transaction_id,
        :amount,
        :direction,
        :kind,
        :status,
        :occurred_at,
        :posted_at,
        :description,
        :memo,
        :counterparty_id,
        :counterparty_name,
        :counterparty_account_last4,
        :dashboard_link,
        :raw_provider_payload,
        :category,
        :review_status,
        :match_status,
        :match_confidence,
        :reconciliation_note
      ]
    end

    update :update do
      primary? true

      accept [
        :amount,
        :direction,
        :kind,
        :status,
        :occurred_at,
        :posted_at,
        :description,
        :memo,
        :counterparty_id,
        :counterparty_name,
        :counterparty_account_last4,
        :dashboard_link,
        :raw_provider_payload,
        :category,
        :review_status,
        :match_status,
        :match_confidence,
        :reconciliation_note
      ]
    end

    update :categorize do
      require_atomic? false

      accept [:category, :reconciliation_note]
      change set_attribute(:review_status, :reviewed)
      change after_action(&record_transaction_event(&1, &2, &3, :categorized))
    end

    update :apply_rule do
      accept [:category, :reconciliation_note, :review_status, :match_status]
    end

    update :mark_reviewed do
      require_atomic? false

      accept [:reconciliation_note]
      change set_attribute(:review_status, :reviewed)
      change after_action(&record_transaction_event(&1, &2, &3, :reviewed))
    end

    update :ignore do
      require_atomic? false

      accept [:reconciliation_note]
      change set_attribute(:review_status, :ignored)
      change set_attribute(:match_status, :not_matchable)
      change after_action(&record_transaction_event(&1, &2, &3, :ignored))
    end

    update :reopen_review do
      require_atomic? false

      accept []
      change set_attribute(:review_status, :needs_review)
      change set_attribute(:match_status, :unmatched)
      change after_action(&record_transaction_event(&1, &2, &3, :reopened))
    end

    update :mark_matched do
      require_atomic? false

      accept [:reconciliation_note]
      change set_attribute(:review_status, :reviewed)
      change set_attribute(:match_status, :matched)
      change after_action(&record_transaction_event(&1, &2, &3, :matched))
    end

    update :mark_unmatched do
      require_atomic? false

      accept [:reconciliation_note]
      change set_attribute(:review_status, :needs_review)
      change set_attribute(:match_status, :unmatched)
      change after_action(&record_transaction_event(&1, &2, &3, :unmatched))
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :provider, :atom do
      allow_nil? false
      default :mercury
      public? true
      constraints one_of: [:mercury]
    end

    attribute :provider_transaction_id, :string do
      allow_nil? false
      public? true
    end

    attribute :amount, :decimal do
      allow_nil? false
      public? true
    end

    attribute :direction, :atom do
      allow_nil? false
      public? true
      constraints one_of: [:credit, :debit]
    end

    attribute :kind, :atom do
      allow_nil? false
      default :other
      public? true
      constraints one_of: [:ach, :wire, :check, :card, :fee, :transfer, :other]
    end

    attribute :status, :atom do
      allow_nil? false
      default :posted
      public? true
      constraints one_of: [:pending, :posted, :cancelled, :failed]
    end

    attribute :occurred_at, :utc_datetime_usec do
      allow_nil? false
      public? true
    end

    attribute :posted_at, :utc_datetime_usec, public?: true
    attribute :description, :string, public?: true
    attribute :memo, :string, public?: true
    attribute :counterparty_id, :string, public?: true
    attribute :counterparty_name, :string, public?: true

    attribute :counterparty_account_last4, :string do
      public? true
      sensitive? true
    end

    attribute :dashboard_link, :string, public?: true
    attribute :raw_provider_payload, :map, public?: false

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

    attribute :review_status, :atom do
      allow_nil? false
      default :needs_review
      public? true
      constraints one_of: [:needs_review, :auto_matched, :reviewed, :ignored]
    end

    attribute :match_status, :atom do
      allow_nil? false
      default :unmatched
      public? true
      constraints one_of: [:unmatched, :suggested, :matched, :not_matchable]
    end

    attribute :match_confidence, :atom do
      public? true
      constraints one_of: [:exact, :probable, :possible, :unmatched]
    end

    attribute :reconciliation_note, :string, public?: true

    timestamps()
  end

  relationships do
    belongs_to :bank_account, GnomeGarden.Finance.BankAccount do
      allow_nil? false
      public? true
    end

    has_many :bank_transaction_matches, GnomeGarden.Finance.BankTransactionMatch do
      public? true
    end

    has_many :bank_transaction_events, GnomeGarden.Finance.BankTransactionEvent do
      public? true
    end
  end

  identities do
    identity :unique_provider_transaction, [:provider, :provider_transaction_id]
  end

  defp record_transaction_event(changeset, transaction, context, event_type) do
    attrs =
      %{
        bank_transaction_id: transaction.id,
        event_type: event_type,
        source: :operator,
        message: transaction_event_message(event_type),
        metadata: transaction_event_metadata(changeset, transaction),
        actor_id: actor_id(context.actor),
        amount: transaction.amount
      }
      |> Enum.reject(fn {_key, value} -> is_nil(value) end)
      |> Map.new()

    case Finance.record_bank_transaction_event(attrs, actor: context.actor, authorize?: false) do
      {:ok, _event} -> {:ok, transaction}
      {:error, error} -> {:error, error}
    end
  end

  defp transaction_event_message(:categorized), do: "Categorized bank transaction"
  defp transaction_event_message(:reviewed), do: "Marked bank transaction reviewed"
  defp transaction_event_message(:ignored), do: "Ignored bank transaction"
  defp transaction_event_message(:reopened), do: "Reopened bank transaction review"
  defp transaction_event_message(:matched), do: "Matched bank transaction"
  defp transaction_event_message(:unmatched), do: "Marked bank transaction unmatched"
  defp transaction_event_message(event_type), do: "Updated bank transaction #{event_type}"

  defp transaction_event_metadata(changeset, transaction) do
    %{
      "category" => atom_string(transaction.category),
      "review_status" => atom_string(transaction.review_status),
      "match_status" => atom_string(transaction.match_status),
      "reconciliation_note" => Ash.Changeset.get_attribute(changeset, :reconciliation_note)
    }
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new()
  end

  defp actor_id(%{id: id}), do: id
  defp actor_id(_actor), do: nil

  defp atom_string(value) when is_atom(value), do: Atom.to_string(value)
  defp atom_string(value), do: value
end
