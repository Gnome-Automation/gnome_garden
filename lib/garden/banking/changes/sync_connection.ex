defmodule GnomeGarden.Banking.Changes.SyncConnection do
  @moduledoc """
  Runs a provider sync for the connection after the `:sync` action commits.

  A sync failure is recorded in the `BankSyncRun` (by the adapter) and logged;
  the action still succeeds so the run record and `last_synced_at` persist. The
  AshOban trigger's `where` filter gates re-runs by `last_synced_at`, so a failed
  sync is retried on the next scheduled tick rather than hammering the provider.
  """

  use Ash.Resource.Change

  alias GnomeGarden.Banking.Integrations

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.after_action(changeset, fn _changeset, connection ->
      Integrations.sync(connection)
      {:ok, connection}
    end)
  end
end
