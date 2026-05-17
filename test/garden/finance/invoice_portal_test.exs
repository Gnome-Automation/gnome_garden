defmodule GnomeGarden.Finance.InvoicePortalTest do
  use GnomeGarden.DataCase, async: true

  alias GnomeGarden.Finance

  setup do
    org = Ash.Seed.seed!(GnomeGarden.Operations.Organization, %{name: "Client Org"})
    other_org = Ash.Seed.seed!(GnomeGarden.Operations.Organization, %{name: "Other Org"})
    client_user = Ash.Seed.seed!(GnomeGarden.Accounts.ClientUser, %{
      email: "c@example.com",
      organization_id: org.id
    })

    invoice = Ash.Seed.seed!(GnomeGarden.Finance.Invoice, %{
      organization_id: org.id,
      invoice_number: "INV-001",
      status: :issued,
      total_amount: Decimal.new("100.00"),
      balance_amount: Decimal.new("100.00")
    })

    other_invoice = Ash.Seed.seed!(GnomeGarden.Finance.Invoice, %{
      organization_id: other_org.id,
      invoice_number: "INV-002",
      status: :issued,
      total_amount: Decimal.new("50.00"),
      balance_amount: Decimal.new("50.00")
    })

    {:ok, org: org, client_user: client_user, invoice: invoice, other_invoice: other_invoice}
  end

  test "portal_index returns only invoices for actor's org", %{client_user: cu, invoice: inv, other_invoice: other} do
    {:ok, results} = Finance.list_portal_invoices(actor: cu)
    ids = Enum.map(results, & &1.id)
    assert inv.id in ids
    refute other.id in ids
  end

  test "portal_show returns invoice for actor's org", %{client_user: cu, invoice: inv} do
    assert {:ok, result} = Finance.get_portal_invoice(inv.id, actor: cu)
    assert result.id == inv.id
  end

  test "portal_show returns not found for another org's invoice", %{client_user: cu, other_invoice: other} do
    assert {:error, _} = Finance.get_portal_invoice(other.id, actor: cu)
  end
end
