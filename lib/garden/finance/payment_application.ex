defmodule GnomeGarden.Finance.PaymentApplication do
  @moduledoc """
  Allocation of a payment to an invoice.
  """

  use Ash.Resource,
    otp_app: :gnome_garden,
    domain: GnomeGarden.Finance,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshAdmin.Resource],
    notifiers: [GnomeGarden.Finance.Notifiers.PaymentApplicationGLNotifier]

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
        case reconcile_invoice(payment_application.invoice_id, context.actor) do
          :ok -> {:ok, payment_application}
          {:ok, _} -> {:ok, payment_application}
          {:error, reason} -> {:error, reason}
        end
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
        case reconcile_invoice(payment_application.invoice_id, context.actor) do
          :ok -> {:ok, payment_application}
          {:ok, _} -> {:ok, payment_application}
          {:error, reason} -> {:error, reason}
        end
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
           load: [:applied_amount, :retainer_applied_amount]
         ) do
      {:ok, invoice} when invoice.status in [:issued, :partial] ->
        total_applied =
          Decimal.add(
            invoice.applied_amount || Decimal.new("0"),
            invoice.retainer_applied_amount || Decimal.new("0")
          )

        total = invoice.total_amount || Decimal.new("0")

        cond do
          Decimal.compare(total_applied, total) != :lt ->
            Ash.update(invoice, %{}, action: :mark_paid, actor: actor, authorize?: false)

          Decimal.compare(total_applied, Decimal.new("0")) == :gt ->
            balance = Decimal.sub(total, total_applied)
            Ash.update(invoice, %{balance_amount: balance}, action: :partial, actor: actor, authorize?: false)

          true ->
            :ok
        end

      _ ->
        :ok
    end
  end
end
