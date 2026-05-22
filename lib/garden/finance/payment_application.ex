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

      change after_action(fn _changeset, payment_application, context ->
        reconcile_invoice(payment_application.invoice_id, context.actor)
        {:ok, payment_application}
      end)
    end

    update :update do
      require_atomic? false

      accept [
        :payment_id,
        :invoice_id,
        :amount,
        :applied_on,
        :notes
      ]

      change after_action(fn _changeset, payment_application, context ->
        reconcile_invoice(payment_application.invoice_id, context.actor)
        {:ok, payment_application}
      end)
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

  defp reconcile_invoice(invoice_id, actor) do
    case GnomeGarden.Finance.get_invoice(invoice_id,
           actor: actor,
           authorize?: false,
           load: [:applied_amount]
         ) do
      {:ok, invoice} when invoice.status in [:issued, :partial] ->
        applied = invoice.applied_amount || Decimal.new("0")
        total = invoice.total_amount || Decimal.new("0")

        cond do
          Decimal.compare(applied, total) != :lt ->
            Ash.update!(invoice, %{}, action: :mark_paid, actor: actor, authorize?: false)

          Decimal.compare(applied, Decimal.new("0")) == :gt ->
            balance = Decimal.sub(total, applied)
            Ash.update!(invoice, %{balance_amount: balance}, action: :partial, actor: actor, authorize?: false)

          true ->
            :ok
        end

      _ ->
        :ok
    end
  end
end
