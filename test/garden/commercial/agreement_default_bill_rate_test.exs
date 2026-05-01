defmodule GnomeGarden.Commercial.AgreementDefaultBillRateTest do
  use GnomeGarden.DataCase, async: true

  alias GnomeGarden.Commercial
  alias GnomeGarden.Operations

  setup do
    {:ok, org} =
      GnomeGarden.Operations.Organization
      |> Ash.Changeset.for_create(:create, %{
        name: "Rate Test Org #{System.unique_integer([:positive])}",
        organization_kind: :business
      })
      |> Ash.create(domain: Operations)

    %{org: org}
  end

  test "can create agreement with default_bill_rate", %{org: org} do
    {:ok, agreement} =
      GnomeGarden.Commercial.Agreement
      |> Ash.Changeset.for_create(:create, %{
        organization_id: org.id,
        name: "T&M Agreement",
        default_bill_rate: Decimal.new("195.00")
      })
      |> Ash.create(domain: Commercial)

    assert Decimal.equal?(agreement.default_bill_rate, Decimal.new("195.00"))
  end

  test "default_bill_rate is optional — nil by default", %{org: org} do
    {:ok, agreement} =
      GnomeGarden.Commercial.Agreement
      |> Ash.Changeset.for_create(:create, %{
        organization_id: org.id,
        name: "Fixed Fee Agreement"
      })
      |> Ash.create(domain: Commercial)

    assert is_nil(agreement.default_bill_rate)
  end

  test "can update default_bill_rate on existing agreement", %{org: org} do
    {:ok, agreement} =
      GnomeGarden.Commercial.Agreement
      |> Ash.Changeset.for_create(:create, %{
        organization_id: org.id,
        name: "Updatable Agreement"
      })
      |> Ash.create(domain: Commercial)

    {:ok, updated} =
      agreement
      |> Ash.Changeset.for_update(:update, %{default_bill_rate: Decimal.new("245.00")})
      |> Ash.update(domain: Commercial)

    assert Decimal.equal?(updated.default_bill_rate, Decimal.new("245.00"))
  end
end
