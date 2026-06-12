defmodule GnomeGarden.Finance.Changes.GenerateRetainerNumber do
  use Ash.Resource.Change

  @impl true
  def change(changeset, _opts, _context) do
    if Ash.Changeset.get_attribute(changeset, :retainer_number) do
      changeset
    else
      Ash.Changeset.before_action(changeset, fn cs ->
        {:ok, %{rows: [[val]]}} =
          GnomeGarden.Repo.query(
            "SELECT nextval('finance_retainer_number_seq')",
            []
          )

        number = "RET-" <> String.pad_leading("#{val}", 4, "0")
        Ash.Changeset.force_change_attribute(cs, :retainer_number, number)
      end)
    end
  end
end
