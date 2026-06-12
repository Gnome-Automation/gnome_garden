defmodule GnomeGarden.Finance.RetainerApplication do
  use Ash.Resource,
    otp_app: :gnome_garden,
    domain: GnomeGarden.Finance,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshAdmin.Resource]

  admin do
    table_columns [:id, :retainer_id, :invoice_id, :amount, :applied_on]
  end

  postgres do
    table "finance_retainer_applications"
    repo GnomeGarden.Repo

    identity_index_names unique_retainer_invoice_pair: "fin_retainer_app_unique_pair_idx"

    references do
      reference :retainer, on_delete: :delete
      reference :invoice, on_delete: :delete
    end
  end

  actions do
    defaults [:read]

    create :create do
      primary? true
      accept [:retainer_id, :invoice_id, :amount, :applied_on]

      change after_action(fn _changeset, application, context ->
        with {:ok_or_noop} <- wrap_reconcile(reconcile_invoice(application.invoice_id, context.actor)),
             {:ok_or_noop} <- wrap_reconcile(reconcile_retainer(application.retainer_id, context.actor)) do
          {:ok, application}
        else
          {:error, reason} -> {:error, reason}
        end
      end)
    end

    destroy :destroy do
      primary? true
      require_atomic? false

      change before_action(fn changeset, context ->
        app = changeset.data

        Ash.Changeset.after_action(changeset, fn _cs, result ->
          with {:ok_or_noop} <- wrap_reconcile(reverse_invoice(app.invoice_id, app.amount, context.actor)),
               {:ok_or_noop} <- wrap_reconcile(reopen_retainer(app.retainer_id, context.actor)) do
            {:ok, result}
          else
            {:error, reason} -> {:error, reason}
          end
        end)
      end)
    end

    read :for_invoice do
      argument :invoice_id, :uuid, allow_nil?: false
      filter expr(invoice_id == ^arg(:invoice_id))
      prepare build(sort: [applied_on: :asc], load: [:retainer])
    end

    read :for_retainer do
      argument :retainer_id, :uuid, allow_nil?: false
      filter expr(retainer_id == ^arg(:retainer_id))
      prepare build(sort: [applied_on: :asc], load: [:invoice])
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

    timestamps()
  end

  relationships do
    belongs_to :retainer, GnomeGarden.Finance.Retainer do
      allow_nil? false
      public? true
    end

    belongs_to :invoice, GnomeGarden.Finance.Invoice do
      allow_nil? false
      public? true
    end
  end

  identities do
    identity :unique_retainer_invoice_pair, [:retainer_id, :invoice_id]
  end

  # --- Private reconciliation helpers ---

  defp reconcile_invoice(invoice_id, actor) do
    case Ash.get(GnomeGarden.Finance.Invoice, invoice_id,
           actor: actor,
           authorize?: false,
           load: [:applied_amount, :retainer_applied_amount]
         ) do
      {:ok, invoice} when invoice.status in [:issued, :partial] ->
        total_applied = Decimal.add(
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

  defp reconcile_retainer(retainer_id, actor) do
    case Ash.get(GnomeGarden.Finance.Retainer, retainer_id, actor: actor, authorize?: false, load: [:balance_amount]) do
      {:ok, retainer} when retainer.status == :paid ->
        if Decimal.compare(retainer.balance_amount, Decimal.new("0")) != :gt do
          Ash.update(retainer, %{}, action: :exhaust, actor: actor, authorize?: false)
        else
          :ok
        end

      _ ->
        :ok
    end
  end

  defp reverse_invoice(invoice_id, amount, actor) do
    case Ash.get(GnomeGarden.Finance.Invoice, invoice_id, actor: actor, authorize?: false) do
      {:ok, invoice} when invoice.status in [:paid, :partial] ->
        new_balance = Decimal.add(invoice.balance_amount || Decimal.new("0"), amount)
        total = invoice.total_amount || Decimal.new("0")

        cond do
          Decimal.compare(new_balance, total) == :eq ->
            # Fully restored — transition back to issued
            Ash.update(invoice, %{balance_amount: new_balance}, action: :unmark_paid, actor: actor, authorize?: false)

          true ->
            # Still partially covered — stay partial with updated balance
            Ash.update(invoice, %{balance_amount: new_balance}, action: :partial, actor: actor, authorize?: false)
        end

      _ ->
        :ok
    end
  end

  defp reopen_retainer(retainer_id, actor) do
    case Ash.get(GnomeGarden.Finance.Retainer, retainer_id, actor: actor, authorize?: false) do
      {:ok, retainer} when retainer.status == :exhausted ->
        Ash.update(retainer, %{}, action: :reopen, actor: actor, authorize?: false)

      _ ->
        :ok
    end
  end

  # Normalises reconciliation helper return values so errors propagate while
  # {:ok, _record} (successful Ash.update) and :ok (no-op) both continue.
  defp wrap_reconcile(:ok), do: {:ok_or_noop}
  defp wrap_reconcile({:ok, _}), do: {:ok_or_noop}
  defp wrap_reconcile({:error, reason}), do: {:error, reason}
end
