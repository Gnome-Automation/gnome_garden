defmodule GnomeGarden.Finance.Actions.BuildArAging do
  @moduledoc """
  Accounts-receivable aging as of a date: open invoice balances bucketed by how
  overdue they are (current, 1–30, 31–60, 61–90, 90+ days past due).
  """

  use Ash.Resource.Actions.Implementation

  alias GnomeGarden.Finance
  alias GnomeGarden.Ledger.Reports

  @impl true
  def run(input, _opts, context) do
    as_of = Ash.ActionInput.get_argument(input, :as_of) || Date.utc_today()

    with {:ok, invoices} <- Finance.list_open_invoices(actor: context.actor) do
      buckets =
        Enum.reduce(invoices, empty_buckets(), fn invoice, acc ->
          bucket = bucket_for(invoice, as_of)
          Map.update!(acc, bucket, &Decimal.add(&1, Reports.amount(invoice.balance_amount)))
        end)

      total = buckets |> Map.values() |> Enum.reduce(Reports.zero(), &Decimal.add(&2, &1))

      {:ok, Map.merge(%{as_of: as_of, total: total, invoice_count: length(invoices)}, buckets)}
    end
  end

  defp empty_buckets do
    %{current: Reports.zero(), d1_30: Reports.zero(), d31_60: Reports.zero(), d61_90: Reports.zero(), d90_plus: Reports.zero()}
  end

  defp bucket_for(%{due_on: nil}, _as_of), do: :current

  defp bucket_for(%{due_on: due_on}, as_of) do
    case Date.diff(as_of, due_on) do
      days when days <= 0 -> :current
      days when days <= 30 -> :d1_30
      days when days <= 60 -> :d31_60
      days when days <= 90 -> :d61_90
      _ -> :d90_plus
    end
  end
end
