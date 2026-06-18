defmodule GnomeGarden.Ledger.Changes.BuildReversal do
  @moduledoc """
  Builds a reversing journal entry from an existing posted entry: each line's
  debit and credit are swapped, so the reversal nets the original to zero.

  The reversal references the original entry. Because a reversal carries
  `entry_type: :reversal` and `reference_id` of the original, the partial unique
  index on (reference_type, reference_id, entry_type) prevents reversing the
  same entry twice.

  A reversal of a balanced entry is balanced by construction, so no balance
  validation is needed on this path.
  """

  use Ash.Resource.Change

  alias GnomeGarden.Ledger

  @impl true
  def change(changeset, _opts, _context) do
    original_id = Ash.Changeset.get_argument(changeset, :original_entry_id)

    case Ledger.get_journal_entry(original_id, load: [journal_lines: [:account]]) do
      {:ok, %{status: :posted} = original} ->
        changeset
        |> Ash.Changeset.change_attribute(:entry_type, :reversal)
        |> Ash.Changeset.change_attribute(:description, "Reversal of #{original.entry_number}")
        |> Ash.Changeset.change_attribute(:reference_type, "journal_entry")
        |> Ash.Changeset.change_attribute(:reference_id, original.id)
        |> default_date(original)
        |> Ash.Changeset.manage_relationship(:journal_lines, flipped_lines(original),
          type: :create
        )

      {:ok, _unposted} ->
        Ash.Changeset.add_error(changeset,
          field: :original_entry_id,
          message: "only posted entries can be reversed"
        )

      _ ->
        Ash.Changeset.add_error(changeset,
          field: :original_entry_id,
          message: "original journal entry not found"
        )
    end
  end

  defp default_date(changeset, original) do
    if Ash.Changeset.get_attribute(changeset, :date) do
      changeset
    else
      Ash.Changeset.change_attribute(changeset, :date, original.date)
    end
  end

  defp flipped_lines(original) do
    Enum.map(original.journal_lines, fn line ->
      %{
        account_id: line.account_id,
        debit: line.credit,
        credit: line.debit,
        description: "Reversal: #{line.description}"
      }
    end)
  end
end
