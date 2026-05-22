defmodule GnomeGarden.Commercial.Changes.GenerateProposalNumber do
  use Ash.Resource.Change

  @impl true
  def change(changeset, _opts, _context) do
    if Ash.Changeset.get_attribute(changeset, :proposal_number) do
      changeset
    else
      Ash.Changeset.before_action(changeset, fn cs ->
        {:ok, %{rows: [[val]]}} =
          GnomeGarden.Repo.query(
            "SELECT nextval('commercial_proposal_number_seq')",
            []
          )

        number = "PROP-" <> String.pad_leading("#{val}", 4, "0")
        Ash.Changeset.force_change_attribute(cs, :proposal_number, number)
      end)
    end
  end
end
