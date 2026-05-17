defmodule GnomeGarden.Payments.StripeClient do
  @moduledoc """
  Stripe API wrapper for creating Payment Links for invoices.

  Creates a Stripe Payment Link with two line items:
  1. The invoice amount
  2. A 3% card processing fee

  The payment link metadata includes invoice_id for webhook matching.
  Non-fatal — callers should log and continue if this fails.
  """

  require Logger

  @doc """
  Creates a Stripe Payment Link for the given invoice.
  Returns {:ok, url} on success, {:error, reason} on failure.
  """
  def create_payment_link(invoice) do
    if is_nil(invoice.total_amount) do
      {:error, :total_amount_nil}
    else
      do_create_payment_link(invoice)
    end
  end

  defp do_create_payment_link(invoice) do
    with {:ok, _api_key} <- get_api_key(),
         {:ok, price_id} <- create_price(invoice),
         {:ok, fee_price_id} <- create_fee_price(invoice),
         {:ok, link} <- create_link(invoice, price_id, fee_price_id) do
      {:ok, link.url}
    else
      {:error, reason} ->
        Logger.warning("StripeClient.create_payment_link failed: #{inspect(reason)}")
        {:error, reason}
    end
  end


  defp get_api_key do
    case Application.get_env(:stripity_stripe, :api_key) do
      nil -> {:error, :api_key_not_configured}
      key -> {:ok, key}
    end
  end

  defp amount_cents(decimal_amount) do
    decimal_amount
    |> Decimal.mult(100)
    |> Decimal.round(0)
    |> Decimal.to_integer()
  end

  defp create_price(invoice) do
    case Stripe.Price.create(%{
      unit_amount: amount_cents(invoice.total_amount),
      currency: "usd",
      product_data: %{name: "Invoice #{invoice.invoice_number}"}
    }) do
      {:ok, price} -> {:ok, price.id}
      {:error, _} = err -> err
    end
  end

  defp create_fee_price(invoice) do
    fee_cents =
      invoice.total_amount
      |> Decimal.mult("0.03")
      |> Decimal.mult(100)
      |> Decimal.round(0)
      |> Decimal.to_integer()

    case Stripe.Price.create(%{
      unit_amount: fee_cents,
      currency: "usd",
      product_data: %{name: "Card processing fee (3%)"}
    }) do
      {:ok, price} -> {:ok, price.id}
      {:error, _} = err -> err
    end
  end

  defp create_link(invoice, price_id, fee_price_id) do
    case Stripe.PaymentLink.create(%{
      line_items: [
        %{price: price_id, quantity: 1},
        %{price: fee_price_id, quantity: 1}
      ],
      metadata: %{invoice_id: invoice.id}
    }) do
      {:ok, link} -> {:ok, link}
      {:error, _} = err -> err
    end
  end
end
