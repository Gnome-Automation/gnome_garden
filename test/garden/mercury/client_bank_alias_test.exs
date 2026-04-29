defmodule GnomeGarden.Mercury.ClientBankAliasTest do
  use GnomeGarden.DataCase, async: true

  alias GnomeGarden.Mercury
  alias GnomeGarden.Operations

  setup do
    {:ok, org} =
      Operations.create_organization(%{
        name: "Acme Corp #{System.unique_integer([:positive])}",
        organization_kind: :business
      })

    %{org: org}
  end

  test "creates an alias linking counterparty name to organization", %{org: org} do
    {:ok, alias} =
      Mercury.create_client_bank_alias(%{
        counterparty_name_fragment: "ACME CORP",
        organization_id: org.id
      })

    assert alias.counterparty_name_fragment == "ACME CORP"
    assert alias.organization_id == org.id
  end

  test "enforces unique counterparty_name_fragment", %{org: org} do
    {:ok, _} =
      Mercury.create_client_bank_alias(%{
        counterparty_name_fragment: "ACME CORP",
        organization_id: org.id
      })

    assert {:error, _} =
             Mercury.create_client_bank_alias(%{
               counterparty_name_fragment: "ACME CORP",
               organization_id: org.id
             })
  end

  test "can look up alias by fragment", %{org: org} do
    {:ok, _} =
      Mercury.create_client_bank_alias(%{
        counterparty_name_fragment: "ACME CORPORATION",
        organization_id: org.id
      })

    {:ok, found} = Mercury.get_client_bank_alias_by_fragment("ACME CORPORATION")
    assert found.organization_id == org.id
  end

  test "deletes alias", %{org: org} do
    {:ok, alias} =
      Mercury.create_client_bank_alias(%{
        counterparty_name_fragment: "DELETE ME",
        organization_id: org.id
      })

    {:ok, _} = Mercury.delete_client_bank_alias(alias)
    assert {:error, _} = Mercury.get_client_bank_alias_by_fragment("DELETE ME")
  end
end
