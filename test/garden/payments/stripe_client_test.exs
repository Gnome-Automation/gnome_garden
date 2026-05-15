defmodule GnomeGarden.Payments.StripeClientTest do
  use GnomeGarden.DataCase, async: true

  alias GnomeGarden.Payments.StripeClient

  test "create_payment_link/1 returns {:ok, url} when Stripe responds" do
    # Skip if no Stripe key configured
    if System.get_env("STRIPE_SECRET_KEY") do
      org = Ash.Seed.seed!(GnomeGarden.Operations.Organization, %{name: "Test"})
      invoice = Ash.Seed.seed!(GnomeGarden.Finance.Invoice, %{
        organization_id: org.id,
        invoice_number: "INV-STRIPE-001",
        status: :draft,
        total_amount: Decimal.new("100.00"),
        balance_amount: Decimal.new("100.00")
      })

      assert {:ok, url} = StripeClient.create_payment_link(invoice)
      assert String.starts_with?(url, "https://")
    else
      assert true
    end
  end

  test "create_payment_link/1 returns {:error, reason} when Stripe key missing" do
    original_key = Application.get_env(:stripity_stripe, :api_key)
    Application.put_env(:stripity_stripe, :api_key, nil)

    on_exit(fn ->
      if original_key, do: Application.put_env(:stripity_stripe, :api_key, original_key),
        else: Application.delete_env(:stripity_stripe, :api_key)
    end)

    org = Ash.Seed.seed!(GnomeGarden.Operations.Organization, %{name: "Test"})
    invoice = Ash.Seed.seed!(GnomeGarden.Finance.Invoice, %{
      organization_id: org.id,
      invoice_number: "INV-STRIPE-002",
      status: :draft,
      total_amount: Decimal.new("100.00"),
      balance_amount: Decimal.new("100.00")
    })

    result = StripeClient.create_payment_link(invoice)
    assert match?({:error, _}, result)
  end
end
