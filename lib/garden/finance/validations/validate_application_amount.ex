defmodule GnomeGarden.Finance.Validations.ValidateApplicationAmount do
  @moduledoc """
  Guards a payment application against over-application and against applying
  to/from records that can no longer receive it:

    * the amount must be positive
    * the invoice must not be void or written off
    * the payment must not be reversed
    * the amount must not exceed the invoice's remaining balance
    * the amount must not exceed the payment's unapplied amount

  Without these, an application could silently exceed the invoice balance or the
  payment, and the over-payment would simply vanish from both views — the worst
  kind of finance bug because it looks fine until reconciliation weeks later.
  """

  use Ash.Resource.Validation

  alias GnomeGarden.Finance
  alias GnomeGarden.Ledger.Reports

  @zero Decimal.new(0)

  @impl true
  def validate(changeset, _opts, _context) do
    amount = Ash.Changeset.get_attribute(changeset, :amount)
    invoice_id = Ash.Changeset.get_attribute(changeset, :invoice_id)
    payment_id = Ash.Changeset.get_attribute(changeset, :payment_id)

    # Required-field validations cover the nil cases; only run cross-record
    # checks once we actually have an amount, an invoice and a payment.
    if is_nil(amount) or is_nil(invoice_id) or is_nil(payment_id) do
      :ok
    else
      run_checks(Reports.amount(amount), invoice_id, payment_id)
    end
  end

  defp run_checks(amount, invoice_id, payment_id) do
    with :ok <- validate_positive(amount),
         {:ok, invoice} <- Finance.get_invoice(invoice_id),
         {:ok, payment} <- Finance.get_payment(payment_id, load: [:applied_amount]),
         :ok <- validate_invoice_status(invoice),
         :ok <- validate_payment_status(payment),
         :ok <- validate_within_balance(amount, invoice),
         :ok <- validate_within_unapplied(amount, payment) do
      :ok
    else
      # If the related records can't be loaded, let the foreign-key / required
      # validations surface that rather than erroring here.
      {:error, %Ash.Error.Query.NotFound{}} -> :ok
      other -> other
    end
  end

  defp validate_positive(amount) do
    if Decimal.compare(amount, @zero) == :gt do
      :ok
    else
      {:error, field: :amount, message: "must be greater than zero"}
    end
  end

  defp validate_invoice_status(%{status: status}) when status in [:void, :write_off] do
    {:error, field: :invoice_id, message: "cannot apply a payment to a #{status} invoice"}
  end

  defp validate_invoice_status(_invoice), do: :ok

  defp validate_payment_status(%{status: :reversed}) do
    {:error, field: :payment_id, message: "cannot apply a reversed payment"}
  end

  defp validate_payment_status(_payment), do: :ok

  defp validate_within_balance(amount, invoice) do
    balance = Reports.amount(invoice.balance_amount) || @zero

    if Decimal.compare(amount, balance) == :gt do
      {:error,
       field: :amount,
       message: "exceeds the invoice's remaining balance (#{Decimal.to_string(balance)})"}
    else
      :ok
    end
  end

  defp validate_within_unapplied(amount, payment) do
    unapplied = Decimal.sub(Reports.amount(payment.amount), Reports.amount(payment.applied_amount))

    if Decimal.compare(amount, unapplied) == :gt do
      {:error,
       field: :amount,
       message: "exceeds the payment's unapplied amount (#{Decimal.to_string(unapplied)})"}
    else
      :ok
    end
  end
end
