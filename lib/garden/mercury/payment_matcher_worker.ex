defmodule GnomeGarden.Mercury.PaymentMatcherWorker do
  @moduledoc """
  Oban worker that matches a Mercury transaction to an open Finance.Invoice.

  Matching priority:
  1. Invoice number found in wire reference/memo → :exact
  2. Exact amount + single open invoice for identified client → :exact
  3. Exact amount + multiple open invoices for client → :probable (oldest chosen)
  4. Exact amount matches exactly one open invoice (no client signal) → :possible
  5. No match → :unmatched (logged, transaction updated, :ok returned)
  """

  use Oban.Worker, queue: :mercury, max_attempts: 3

  require Logger
  require Ash.Query

  alias GnomeGarden.Finance
  alias GnomeGarden.Mercury

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"transaction_id" => transaction_id}}) do
    case Mercury.get_mercury_transaction(transaction_id) do
      {:ok, txn} ->
        match_transaction(txn)

      {:error, _} ->
        Logger.warning("PaymentMatcherWorker: transaction not found",
          transaction_id: transaction_id
        )

        :ok
    end
  end

  defp match_transaction(txn) do
    case find_match(txn) do
      {:ok, invoice, confidence} ->
        apply_match(txn, invoice, confidence)

      :unmatched ->
        Logger.warning("PaymentMatcherWorker: no match for transaction",
          mercury_id: txn.mercury_id,
          amount: txn.amount,
          counterparty: txn.counterparty_name
        )

        Mercury.update_mercury_transaction(txn, %{match_confidence: :unmatched})
        :ok
    end
  end

  # --- Matching ---

  defp find_match(txn) do
    with :not_found <- find_by_invoice_number(txn),
         :not_found <- find_by_amount_and_client(txn),
         :not_found <- find_by_amount_only(txn) do
      :unmatched
    end
  end

  defp find_by_invoice_number(txn) do
    reference = "#{txn.external_memo || ""} #{txn.bank_description || ""}"

    case Regex.run(~r/INV-[A-Z0-9-]+/i, reference) do
      [invoice_number] ->
        GnomeGarden.Finance.Invoice
        |> Ash.Query.filter(
          invoice_number == ^invoice_number and status in [:issued, :partial]
        )
        |> Ash.read_one(domain: Finance)
        |> case do
          {:ok, invoice} when not is_nil(invoice) -> {:ok, invoice, :exact}
          _ -> :not_found
        end

      nil ->
        :not_found
    end
  end

  defp find_by_amount_and_client(txn) do
    case resolve_organization(txn.counterparty_name) do
      {:ok, organization_id} ->
        open_invoices =
          GnomeGarden.Finance.Invoice
          |> Ash.Query.filter(
            organization_id == ^organization_id and status in [:issued, :partial]
          )
          |> Ash.Query.sort(due_on: :asc)
          |> Ash.read!(domain: Finance, load: [:applied_amount])

        candidates = Enum.filter(open_invoices, &amount_matches?(&1, txn.amount))

        case candidates do
          [invoice] -> {:ok, invoice, :exact}
          [invoice | _] -> {:ok, invoice, :probable}
          [] -> :not_found
        end

      :not_found ->
        :not_found
    end
  end

  defp find_by_amount_only(txn) do
    open_invoices =
      GnomeGarden.Finance.Invoice
      |> Ash.Query.filter(status in [:issued, :partial])
      |> Ash.Query.sort(due_on: :asc)
      |> Ash.read!(domain: Finance, load: [:applied_amount])

    candidates = Enum.filter(open_invoices, &amount_matches?(&1, txn.amount))

    case candidates do
      [invoice] -> {:ok, invoice, :possible}
      _ -> :not_found
    end
  end

  defp resolve_organization(nil), do: :not_found

  defp resolve_organization(name) do
    # Find a ClientBankAlias whose fragment appears in the counterparty name (case-insensitive)
    lower_name = String.downcase(name)

    all_aliases =
      GnomeGarden.Mercury.ClientBankAlias
      |> Ash.read!(domain: Mercury)

    case Enum.find(all_aliases, fn a ->
           String.contains?(lower_name, String.downcase(a.counterparty_name_fragment))
         end) do
      nil -> :not_found
      bank_alias -> {:ok, bank_alias.organization_id}
    end
  end

  defp amount_matches?(invoice, txn_amount) do
    tolerance = underpayment_tolerance()
    balance = effective_balance(invoice)
    Decimal.compare(Decimal.abs(Decimal.sub(balance, txn_amount)), tolerance) != :gt
  end

  defp effective_balance(invoice) do
    applied = invoice.applied_amount || Decimal.new("0")
    total = invoice.total_amount || Decimal.new("0")
    Decimal.sub(total, applied)
  end

  defp underpayment_tolerance do
    raw =
      Application.get_env(:gnome_garden, :payment_matching, [])
      |> Keyword.get(:underpayment_tolerance, "1.00")

    if is_struct(raw, Decimal), do: raw, else: Decimal.new(to_string(raw))
  end

  # --- Applying a match ---

  defp apply_match(txn, invoice, confidence) do
    with {:ok, payment} <-
           Finance.create_payment(%{
             organization_id: invoice.organization_id,
             agreement_id: invoice.agreement_id,
             received_on: DateTime.to_date(txn.occurred_at),
             payment_method: kind_to_payment_method(txn.kind),
             currency_code: invoice.currency_code || "USD",
             amount: txn.amount,
             reference: txn.mercury_id
           }),
         {:ok, _application} <-
           Finance.create_payment_application(%{
             payment_id: payment.id,
             invoice_id: invoice.id,
             amount: txn.amount,
             applied_on: DateTime.to_date(txn.occurred_at)
           }),
         {:ok, _match} <-
           Mercury.create_payment_match(%{
             mercury_transaction_id: txn.id,
             finance_payment_id: payment.id,
             match_source: :auto
           }) do
      close_or_partial(invoice, txn.amount)
      Mercury.update_mercury_transaction(txn, %{match_confidence: confidence})
      :ok
    else
      {:error, reason} ->
        Logger.error("PaymentMatcherWorker: failed to apply match",
          mercury_id: txn.mercury_id,
          reason: inspect(reason)
        )

        {:error, reason}
    end
  end

  defp close_or_partial(invoice, _txn_amount) do
    # Reload with fresh applied_amount after PaymentApplication was just created
    {:ok, fresh} =
      Ash.get(GnomeGarden.Finance.Invoice, invoice.id, domain: Finance, load: [:applied_amount])

    new_balance = effective_balance(fresh)

    if Decimal.compare(new_balance, underpayment_tolerance()) != :gt do
      Finance.pay_invoice(fresh)
    else
      Finance.partial_invoice(fresh, %{balance_amount: new_balance})
    end
  end

  defp kind_to_payment_method(:wire), do: :wire
  defp kind_to_payment_method(:ach), do: :ach
  defp kind_to_payment_method(_), do: :other
end
