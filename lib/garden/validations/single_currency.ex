defmodule GnomeGarden.Validations.SingleCurrency do
  @moduledoc """
  Rejects any money attribute that is not in the system's single supported
  currency (USD by default).

  The system is single-currency today, but money is stored as
  `money_with_currency` and aggregates filter on `currency == "USD"` — so a
  non-USD value would be silently dropped from totals rather than rejected.
  This validation turns that latent, invisible bug into a loud, explicit
  rejection at the point of entry. Multi-currency support is a separate,
  larger effort — see `docs/multi_currency.md`.

  Usage:

      validate {GnomeGarden.Validations.SingleCurrency, attributes: [:amount]}
      validate {GnomeGarden.Validations.SingleCurrency, attributes: [:debit, :credit], currency: :USD}
  """

  use Ash.Resource.Validation

  @impl true
  def validate(changeset, opts, _context) do
    currency = Keyword.get(opts, :currency, :USD)
    attributes = Keyword.get(opts, :attributes, [])

    case Enum.find(attributes, &wrong_currency?(changeset, &1, currency)) do
      nil ->
        :ok

      attribute ->
        {:error,
         field: attribute,
         message: "must be in #{currency} — multi-currency is not yet supported"}
    end
  end

  # nil / unset is left to required-field validations; only a present Money in
  # the wrong currency is rejected.
  defp wrong_currency?(changeset, attribute, currency) do
    case Ash.Changeset.get_attribute(changeset, attribute) do
      %Money{currency: ^currency} -> false
      %Money{} -> true
      _ -> false
    end
  end
end
