defmodule GnomeGarden.Ledger.JournalLine.Validations.OneSidedPositiveLine do
  @moduledoc """
  A journal line must carry a positive amount on exactly one side — a debit or a
  credit, never both, never neither, and never a negative amount.

  Without this, a nonsense line (a debit of -100 to "balance" a credit of -100,
  or a line with both sides set) would pass the balanced-entry check while being
  garbage. Enforcing it per line means the ledger's balance invariant can't be
  satisfied by malformed lines.
  """

  use Ash.Resource.Validation

  @zero Decimal.new(0)

  @impl true
  def validate(changeset, _opts, _context) do
    debit = amount(Ash.Changeset.get_attribute(changeset, :debit))
    credit = amount(Ash.Changeset.get_attribute(changeset, :credit))

    cond do
      negative?(debit) or negative?(credit) ->
        {:error, field: :debit, message: "debit and credit must not be negative"}

      positive?(debit) and positive?(credit) ->
        {:error, field: :debit, message: "a line cannot carry both a debit and a credit"}

      not positive?(debit) and not positive?(credit) ->
        {:error, field: :debit, message: "a line must carry a positive debit or credit"}

      true ->
        :ok
    end
  end

  defp amount(nil), do: @zero
  defp amount(%Money{amount: amount}), do: amount
  defp amount(%Decimal{} = decimal), do: decimal

  defp positive?(decimal), do: Decimal.compare(decimal, @zero) == :gt
  defp negative?(decimal), do: Decimal.compare(decimal, @zero) == :lt
end
