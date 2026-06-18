defmodule GnomeGarden.Finance.Changes.ZeroInvoiceBalance do
  @moduledoc """
  Sets an invoice's `balance_amount` to zero in the invoice's own currency.

  Used by the `:mark_paid` and `:write_off` transitions. A `:money` attribute
  can't be zeroed with a bare `Decimal`, so the zero is built in the invoice's
  `currency_code`.
  """

  use Ash.Resource.Change

  @impl true
  def change(changeset, _opts, _context) do
    currency = Ash.Changeset.get_attribute(changeset, :currency_code) || "USD"
    Ash.Changeset.change_attribute(changeset, :balance_amount, Money.new!(currency, 0))
  end
end
