defmodule GnomeGarden.Finance.Changes.PostInvoiceVoidedReversal do
  @moduledoc """
  When an issued invoice is voided, posts a reversing journal entry so its
  revenue and AR are backed out of the ledger. Atomic with the `:void` action.

  Voiding a draft invoice (never issued, so never posted) is a no-op. The
  ledger's partial unique index prevents a second reversal of the same entry.
  """

  use Ash.Resource.Change

  alias GnomeGarden.Ledger

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.after_action(changeset, fn _changeset, invoice ->
      case reverse(invoice) do
        :ok -> {:ok, invoice}
        {:error, error} -> {:error, error}
      end
    end)
  end

  defp reverse(invoice) do
    with {:ok, entries} <- Ledger.list_journal_entries_for_reference("invoice", invoice.id),
         %{} = original <- Enum.find(entries, &(&1.entry_type == :invoice_issued)) do
      case Ledger.reverse_journal_entry(original.id) do
        {:ok, _reversal} -> :ok
        {:error, error} -> {:error, error}
      end
    else
      # No posted issuance entry (e.g. voided while still a draft) — nothing to reverse.
      nil -> :ok
      {:error, error} -> {:error, error}
    end
  end
end
