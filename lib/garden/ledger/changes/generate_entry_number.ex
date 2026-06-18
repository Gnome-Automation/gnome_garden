defmodule GnomeGarden.Ledger.Changes.GenerateEntryNumber do
  @moduledoc """
  Assigns a sequential `entry_number` (e.g. `JE-000123`) from the
  `ledger_journal_entry_seq` Postgres sequence, unless one was supplied.

  The sequence guarantees monotonic, collision-free numbers across concurrent
  posts. Like all sequences it may gap on rolled-back transactions, which is the
  expected behaviour for accounting document numbering.
  """

  use Ash.Resource.Change

  alias GnomeGarden.Repo

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.before_action(changeset, fn changeset ->
      if Ash.Changeset.get_attribute(changeset, :entry_number) do
        changeset
      else
        Ash.Changeset.force_change_attribute(changeset, :entry_number, next_entry_number())
      end
    end)
  end

  defp next_entry_number do
    %{rows: [[value]]} = Repo.query!("SELECT nextval('ledger_journal_entry_seq')")
    "JE-" <> (value |> Integer.to_string() |> String.pad_leading(6, "0"))
  end
end
