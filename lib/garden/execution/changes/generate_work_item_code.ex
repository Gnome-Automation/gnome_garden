defmodule GnomeGarden.Execution.Changes.GenerateWorkItemCode do
  use Ash.Resource.Change

  @impl true
  def change(changeset, _opts, _context) do
    if Ash.Changeset.get_attribute(changeset, :code) do
      changeset
    else
      Ash.Changeset.before_action(changeset, fn cs ->
        {:ok, %{rows: [[val]]}} =
          GnomeGarden.Repo.query(
            "SELECT nextval('execution_work_item_code_seq')",
            []
          )

        code = "WI-" <> String.pad_leading("#{val}", 4, "0")
        Ash.Changeset.force_change_attribute(cs, :code, code)
      end)
    end
  end
end
