defmodule GnomeGarden.Finance.Changes.GenerateBillNumber do
  use Ash.Resource.Change

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.before_action(changeset, fn cs ->
      {:ok, %{rows: [[val]]}} =
        GnomeGarden.Repo.query(
          "SELECT nextval('finance_vendor_bill_number_seq')",
          []
        )

      number = "BILL-" <> String.pad_leading("#{val}", 4, "0")
      Ash.Changeset.force_change_attribute(cs, :bill_number, number)
    end)
  end
end
