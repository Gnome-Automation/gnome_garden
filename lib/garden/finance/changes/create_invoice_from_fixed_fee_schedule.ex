defmodule GnomeGarden.Finance.Changes.CreateInvoiceFromFixedFeeSchedule do
  @moduledoc """
  Generates one draft Invoice per PaymentScheduleItem for a fixed-fee Agreement.

  Called via Finance.create_invoices_from_fixed_fee_schedule/1.

  Pre-conditions:
  - Agreement must have billing_model: :fixed_fee
  - Agreement must have a non-nil contract_value
  - Schedule items must exist and sum to exactly 100%
    (or no items: generates a single invoice for the full contract_value)

  Returns {:ok, [Invoice.t()]} or {:error, reason}.
  """

  alias GnomeGarden.Commercial
  alias GnomeGarden.Finance
  alias GnomeGarden.Finance.PaymentScheduleItem

  require Ash.Query

  def generate(agreement_id) do
    with {:ok, agreement} <- load_agreement(agreement_id),
         :ok <- validate_contract_value(agreement),
         {:ok, items} <- load_schedule_items(agreement_id) do
      case items do
        [] ->
          # No schedule: single invoice for full contract_value
          generate_single_invoice(agreement)

        items ->
          with :ok <- validate_percentage_sum(items) do
            create_invoices(agreement, items)
          end
      end
    end
  end

  defp load_agreement(agreement_id) do
    Commercial.get_agreement(agreement_id)
  end

  defp validate_contract_value(%{contract_value: nil}),
    do: {:error, "agreement must have a contract_value set before generating fixed-fee invoices"}

  defp validate_contract_value(_), do: :ok

  defp load_schedule_items(agreement_id) do
    PaymentScheduleItem
    |> Ash.Query.filter(agreement_id == ^agreement_id)
    |> Ash.Query.sort(position: :asc)
    |> Ash.read(domain: Finance)
  end

  defp validate_percentage_sum(items) do
    total =
      Enum.reduce(items, Decimal.new("0"), fn item, acc ->
        Decimal.add(acc, item.percentage)
      end)

    if Decimal.equal?(total, Decimal.new("100")) do
      :ok
    else
      {:error, "payment schedule percentages sum to #{total}%, must equal 100%"}
    end
  end

  defp generate_single_invoice(agreement) do
    attrs = %{
      organization_id: agreement.organization_id,
      agreement_id: agreement.id,
      invoice_number: generate_invoice_number(agreement, 1),
      currency_code: agreement.currency_code || "USD",
      subtotal: agreement.contract_value,
      tax_total: Decimal.new("0"),
      total_amount: agreement.contract_value,
      balance_amount: agreement.contract_value,
      due_on: Date.add(Date.utc_today(), agreement.payment_terms_days || 30),
      notes: "Full payment"
    }

    case Finance.create_invoice(attrs) do
      {:ok, invoice} -> {:ok, [invoice]}
      error -> error
    end
  end

  defp create_invoices(agreement, items) do
    today = Date.utc_today()

    result =
      Enum.reduce_while(items, [], fn item, acc ->
        amount =
          agreement.contract_value
          |> Decimal.mult(Decimal.div(item.percentage, Decimal.new("100")))
          |> Decimal.round(2)

        attrs = %{
          organization_id: agreement.organization_id,
          agreement_id: agreement.id,
          invoice_number: generate_invoice_number(agreement, item.position),
          currency_code: agreement.currency_code || "USD",
          subtotal: amount,
          tax_total: Decimal.new("0"),
          total_amount: amount,
          balance_amount: amount,
          due_on: Date.add(today, item.due_days),
          notes: item.label
        }

        case Finance.create_invoice(attrs) do
          {:ok, invoice} -> {:cont, [invoice | acc]}
          {:error, reason} -> {:halt, {:error, reason}}
        end
      end)

    case result do
      {:error, reason} -> {:error, reason}
      list -> {:ok, Enum.reverse(list)}
    end
  end

  defp generate_invoice_number(agreement, position) when is_integer(position) do
    ref = Map.get(agreement, :reference_number) || String.slice(agreement.id, 0, 8)
    "#{ref}-#{position}"
  end
end
