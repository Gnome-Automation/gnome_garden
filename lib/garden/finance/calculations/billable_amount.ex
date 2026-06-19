defmodule GnomeGarden.Finance.Calculations.BillableAmount do
  @moduledoc """
  Billable labor value for a time entry: `bill_rate × hours`, where hours is
  `minutes / 60`, rounded to the currency's precision.

  Returns `nil` when the entry has no bill rate or no minutes — there is no
  honest billable figure to derive, so the value is absent rather than a
  misleading zero.
  """

  use Ash.Resource.Calculation

  @impl true
  def load(_query, _opts, _context), do: [:bill_rate, :minutes]

  @impl true
  def calculate(records, _opts, _context), do: Enum.map(records, &amount/1)

  defp amount(%{bill_rate: %Money{} = rate, minutes: minutes}) when is_integer(minutes) do
    hours = Decimal.div(Decimal.new(minutes), Decimal.new(60))

    rate
    |> Money.mult!(hours)
    |> Money.round()
  end

  defp amount(_record), do: nil
end
