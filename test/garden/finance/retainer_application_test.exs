defmodule GnomeGarden.Finance.RetainerApplicationTest do
  use GnomeGarden.DataCase, async: true

  alias GnomeGarden.Finance

  test "applying a retainer reduces invoice balance and transitions retainer to exhausted when emptied" do
    org = org_fixture()
    invoice = invoice_fixture(org, "500.00")
    retainer = paid_retainer_fixture(org, "500.00")

    assert {:ok, _app} =
      GnomeGarden.Finance.RetainerApplication
      |> Ash.Changeset.for_create(:create, %{
        retainer_id: retainer.id,
        invoice_id: invoice.id,
        amount: Decimal.new("500.00"),
        applied_on: Date.utc_today()
      }, authorize?: false)
      |> Ash.create()

    {:ok, invoice} = Ash.get(Finance.Invoice, invoice.id, authorize?: false)
    assert invoice.status == :paid

    {:ok, retainer} = Ash.get(Finance.Retainer, retainer.id, authorize?: false)
    assert retainer.status == :exhausted
  end

  test "partial application sets invoice to partial status" do
    org = org_fixture()
    invoice = invoice_fixture(org, "500.00")
    retainer = paid_retainer_fixture(org, "200.00")

    assert {:ok, _app} =
      GnomeGarden.Finance.RetainerApplication
      |> Ash.Changeset.for_create(:create, %{
        retainer_id: retainer.id,
        invoice_id: invoice.id,
        amount: Decimal.new("200.00"),
        applied_on: Date.utc_today()
      }, authorize?: false)
      |> Ash.create()

    {:ok, invoice} = Ash.get(Finance.Invoice, invoice.id, authorize?: false, load: [:balance_amount])
    assert invoice.status == :partial

    {:ok, retainer} = Ash.get(Finance.Retainer, retainer.id, authorize?: false)
    assert retainer.status == :exhausted
  end

  test "destroying application reopens retainer and invoice" do
    org = org_fixture()
    invoice = invoice_fixture(org, "300.00")
    retainer = paid_retainer_fixture(org, "300.00")

    {:ok, app} =
      GnomeGarden.Finance.RetainerApplication
      |> Ash.Changeset.for_create(:create, %{
        retainer_id: retainer.id,
        invoice_id: invoice.id,
        amount: Decimal.new("300.00"),
        applied_on: Date.utc_today()
      }, authorize?: false)
      |> Ash.create()

    :ok = Ash.destroy(app, authorize?: false)

    {:ok, retainer} = Ash.get(Finance.Retainer, retainer.id, authorize?: false)
    assert retainer.status == :paid

    {:ok, invoice} = Ash.get(Finance.Invoice, invoice.id, authorize?: false)
    assert invoice.status in [:issued, :partial]
  end

  # --- Fixtures ---
  defp org_fixture do
    {:ok, org} =
      GnomeGarden.Operations.Organization
      |> Ash.Changeset.for_create(:create, %{name: "Org #{System.unique_integer()}"}, authorize?: false)
      |> Ash.create()
    org
  end

  defp invoice_fixture(org, amount) do
    {:ok, invoice} =
      Finance.Invoice
      |> Ash.Changeset.for_create(:create, %{
        organization_id: org.id,
        total_amount: Decimal.new(amount),
        balance_amount: Decimal.new(amount),
        due_on: Date.utc_today() |> Date.add(30)
      }, authorize?: false)
      |> Ash.create()

    {:ok, invoice} = Ash.update(invoice, %{}, action: :issue, authorize?: false)
    invoice
  end

  defp paid_retainer_fixture(org, amount) do
    {:ok, r} =
      Finance.Retainer
      |> Ash.Changeset.for_create(:create, %{
        organization_id: org.id,
        amount: Decimal.new(amount),
        received_on: Date.utc_today()
      }, authorize?: false)
      |> Ash.create()

    {:ok, r} = Ash.update(r, %{}, action: :issue, authorize?: false)
    {:ok, r} = Ash.update(r, %{}, action: :mark_paid, authorize?: false)
    r
  end
end
