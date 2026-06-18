defmodule GnomeGarden.Finance.Changes.PostPaymentAppliedToLedger do
  @moduledoc """
  Posts the GL entry when a payment is applied to an invoice, atomically with
  the `PaymentApplication` `:create` action.

  Debit  1000 Operating Bank        amount
  Credit 1100 Accounts Receivable   amount

  A posting failure (missing account, unbalanced entry) rolls back the
  application so cash and AR never drift from the ledger.
  """

  use Ash.Resource.Change

  alias GnomeGarden.Ledger

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.after_action(changeset, fn _changeset, application ->
      case post(application) do
        {:ok, _entry} -> {:ok, application}
        {:error, error} -> {:error, error}
      end
    end)
  end

  defp post(application) do
    amount = to_decimal(application.amount)

    with {:ok, cash} <- account("1000", "Operating Bank"),
         {:ok, ar} <- account("1100", "Accounts Receivable") do
      Ledger.post_journal_entry(%{
        date: application.applied_on || Date.utc_today(),
        description: "Payment applied to invoice",
        entry_type: :payment_received,
        reference_id: application.id,
        reference_type: "payment_application",
        lines: [
          %{account_id: cash.id, debit: money(amount), description: "Cash received"},
          %{account_id: ar.id, credit: money(amount), description: "AR — payment applied"}
        ]
      })
    end
  end

  defp account(number, label) do
    case Ledger.get_account_by_number(number) do
      {:ok, %{} = account} -> {:ok, account}
      _ -> {:error, "ledger account #{number} (#{label}) is not configured"}
    end
  end

  defp money(decimal), do: Money.new!("USD", decimal)

  defp to_decimal(nil), do: Decimal.new(0)
  defp to_decimal(%Decimal{} = decimal), do: decimal
  defp to_decimal(%Money{amount: amount}), do: amount
end
