defmodule GnomeGarden.Finance.RetainerTest do
  use GnomeGarden.DataCase, async: true
  alias GnomeGarden.Finance

  test "journal entry accepts :retainer_received entry type" do
    valid_types = [:retainer_received, :retainer_applied, :retainer_unapplied, :retainer_voided]

    for type <- valid_types do
      cs =
        GnomeGarden.Finance.JournalEntry
        |> Ash.Changeset.for_create(:create, %{
          date: Date.utc_today(),
          description: "test",
          entry_type: type,
          reference_type: "retainer"
        }, authorize?: false)

      refute Keyword.has_key?(cs.errors, :entry_type),
             "entry_type #{type} should be valid but got errors: #{inspect(cs.errors)}"
    end
  end
end
