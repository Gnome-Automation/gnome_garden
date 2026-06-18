defmodule GnomeGarden.Ledger.Account.Validations.NotSystemAccount do
  @moduledoc """
  Rejects destroying a system account. Checks the persisted record
  (`changeset.data`) rather than changeset attributes, since destroy actions
  don't carry the `system?` value in the changeset.
  """

  use Ash.Resource.Validation

  @impl true
  def validate(changeset, _opts, _context) do
    if changeset.data.system? do
      {:error, field: :system?, message: "system accounts cannot be deleted"}
    else
      :ok
    end
  end
end
