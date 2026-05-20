defmodule GnomeGarden.Finance.Changes.GenerateInvoiceNumber do
  use Ash.Resource.Change

  @impl true
  def change(changeset, _opts, _context) do
    if Ash.Changeset.get_attribute(changeset, :invoice_number) do
      changeset
    else
      Ash.Changeset.before_action(changeset, fn cs ->
        {:ok, %{rows: [[val]]}} =
          GnomeGarden.Repo.query(
            "SELECT nextval('finance_invoice_number_seq')",
            []
          )

        number = "INV-" <> String.pad_leading("#{val}", 4, "0")
        Ash.Changeset.force_change_attribute(cs, :invoice_number, number)
      end)
    end
  end
end
