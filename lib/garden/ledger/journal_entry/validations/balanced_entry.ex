defmodule GnomeGarden.Ledger.JournalEntry.Validations.BalancedEntry do
  @moduledoc """
  Enforces the double-entry invariant: an entry may only post when total debits
  equal total credits, and the entry is non-empty with a positive total.

  Works for both posting paths:
    * create `:post_entry` — sums the `:lines` argument before insert
    * update `:post` — sums the entry's already-persisted journal lines
  """

  use Ash.Resource.Validation

  @impl true
  def validate(changeset, _opts, _context) do
    lines = resolve_lines(changeset)

    {debits, credits} =
      Enum.reduce(lines, {Decimal.new(0), Decimal.new(0)}, fn line, {d, c} ->
        {Decimal.add(d, amount(line, :debit)), Decimal.add(c, amount(line, :credit))}
      end)

    cond do
      lines == [] ->
        {:error, field: :lines, message: "journal entry must have at least one line"}

      not Decimal.equal?(debits, credits) ->
        {:error,
         field: :lines,
         message: "entry does not balance: debits %{debits} ≠ credits %{credits}",
         vars: %{debits: Decimal.to_string(debits), credits: Decimal.to_string(credits)}}

      Decimal.compare(debits, Decimal.new(0)) != :gt ->
        {:error, field: :lines, message: "journal entry total must be positive"}

      true ->
        :ok
    end
  end

  defp resolve_lines(changeset) do
    case Ash.Changeset.get_argument(changeset, :lines) do
      lines when is_list(lines) ->
        lines

      _ ->
        changeset.data
        |> Ash.load!(:journal_lines, domain: GnomeGarden.Ledger)
        |> Map.get(:journal_lines, [])
    end
  end

  # Pulls a Decimal amount for the given side out of a line that may be a map
  # (argument path) or a JournalLine struct (persisted path). Money/Decimal/nil
  # are all normalized to a Decimal.
  defp amount(line, side) do
    line
    |> fetch(side)
    |> to_decimal()
  end

  defp fetch(%{} = line, side) do
    Map.get(line, side) || Map.get(line, to_string(side))
  end

  defp to_decimal(nil), do: Decimal.new(0)
  defp to_decimal(%Money{amount: amount}), do: amount
  defp to_decimal(%Decimal{} = decimal), do: decimal
  defp to_decimal(value) when is_integer(value), do: Decimal.new(value)
  defp to_decimal(value) when is_binary(value), do: Decimal.new(value)
  # Money supplied as a plain map (e.g. JSON/form input: %{"amount" => ...}).
  defp to_decimal(%{"amount" => amount}), do: to_decimal(amount)
  defp to_decimal(%{amount: amount}), do: to_decimal(amount)
end
