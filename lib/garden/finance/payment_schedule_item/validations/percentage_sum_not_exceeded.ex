defmodule GnomeGarden.Finance.PaymentScheduleItem.Validations.PercentageSumNotExceeded do
  @moduledoc """
  Validates that adding/updating this item will not push the schedule's
  total percentage above 100.

  Note: enforces <= 100 (not == 100) so items can be added incrementally.
  The complete-schedule check (sum == 100) is enforced at invoice generation time.
  """

  use Ash.Resource.Validation

  require Ash.Query

  alias GnomeGarden.Finance.PaymentScheduleItem

  @impl true
  def validate(changeset, _opts, _context) do
    agreement_id =
      Ash.Changeset.get_attribute(changeset, :agreement_id) ||
        (changeset.data && changeset.data.agreement_id)
    new_pct = Ash.Changeset.get_attribute(changeset, :percentage) || Decimal.new("0")
    item_id = changeset.data && changeset.data.id

    existing_sum =
      PaymentScheduleItem
      |> Ash.Query.filter(agreement_id == ^agreement_id)
      |> then(fn q ->
        if item_id, do: Ash.Query.filter(q, id != ^item_id), else: q
      end)
      |> Ash.read!(domain: GnomeGarden.Finance)
      |> Enum.reduce(Decimal.new("0"), fn item, acc ->
        Decimal.add(acc, item.percentage)
      end)

    total = Decimal.add(existing_sum, new_pct)

    if Decimal.compare(total, Decimal.new("100")) == :gt do
      {:error,
       field: :percentage,
       message: "would push schedule total to %{total}% (max 100%)",
       vars: %{total: Decimal.to_string(total)}}
    else
      :ok
    end
  end
end
