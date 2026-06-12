defmodule GnomeGarden.Finance.Changes.AutoApplyRetainer do
  require Ash.Query

  # Guard: no org_id means nothing to apply
  def maybe_apply(%{organization_id: nil}, _actor), do: :ok

  def maybe_apply(invoice, actor) do
    retainers =
      GnomeGarden.Finance.Retainer
      |> Ash.Query.filter(
        organization_id == ^invoice.organization_id and
        status == :paid and
        auto_apply == true
      )
      |> Ash.Query.load([:balance_amount])
      |> Ash.read!(authorize?: false)
      |> Enum.filter(fn r -> Decimal.compare(r.balance_amount, Decimal.new("0")) == :gt end)

    Enum.each(retainers, fn retainer ->
      invoice_balance =
        Ash.get!(GnomeGarden.Finance.Invoice, invoice.id,
          authorize?: false,
          load: [:balance_amount]
        ).balance_amount || invoice.total_amount

      if Decimal.compare(invoice_balance, Decimal.new("0")) == :gt do
        amount = Decimal.min(retainer.balance_amount, invoice_balance)

        GnomeGarden.Finance.RetainerApplication
        |> Ash.Changeset.for_create(:create, %{
          retainer_id: retainer.id,
          invoice_id: invoice.id,
          amount: amount,
          applied_on: Date.utc_today()
        }, authorize?: false)
        |> Ash.create(domain: GnomeGarden.Finance)
      end
    end)
  end
end
