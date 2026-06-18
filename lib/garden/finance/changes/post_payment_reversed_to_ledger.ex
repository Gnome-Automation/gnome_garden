defmodule GnomeGarden.Finance.Changes.PostPaymentReversedToLedger do
  @moduledoc """
  When a payment is reversed, posts reversing journal entries for each of its
  payment applications — backing the cash and AR postings out of the ledger.
  Atomic with the `:reverse` action.

  Each application's `:payment_received` entry is reversed. Applications with no
  posted entry are skipped; the ledger's partial unique index prevents a second
  reversal of the same entry.
  """

  use Ash.Resource.Change

  alias GnomeGarden.Finance
  alias GnomeGarden.Ledger

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.after_action(changeset, fn _changeset, payment ->
      case reverse(payment) do
        :ok -> {:ok, payment}
        {:error, error} -> {:error, error}
      end
    end)
  end

  defp reverse(payment) do
    case Finance.list_payment_applications_for_payment(payment.id) do
      {:ok, applications} ->
        Enum.reduce_while(applications, :ok, fn application, _acc ->
          case reverse_application(application) do
            :ok -> {:cont, :ok}
            {:error, error} -> {:halt, {:error, error}}
          end
        end)

      {:error, error} ->
        {:error, error}
    end
  end

  defp reverse_application(application) do
    with {:ok, entries} <-
           Ledger.list_journal_entries_for_reference("payment_application", application.id),
         %{} = original <- Enum.find(entries, &(&1.entry_type == :payment_received)) do
      case Ledger.reverse_journal_entry(original.id) do
        {:ok, _reversal} -> :ok
        {:error, error} -> {:error, error}
      end
    else
      # No posted payment entry for this application — nothing to reverse.
      nil -> :ok
      {:error, error} -> {:error, error}
    end
  end
end
