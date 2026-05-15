defmodule GnomeGarden.Accounts.ClientUserTest do
  use GnomeGarden.DataCase, async: true

  alias GnomeGarden.Accounts

  setup do
    org = Ash.Seed.seed!(GnomeGarden.Operations.Organization, %{name: "Test Org"})
    {:ok, org: org}
  end

  test "invite/2 creates a ClientUser for an org", %{org: org} do
    assert {:ok, cu} = Accounts.invite_client_user("client@example.com", org.id)
    assert to_string(cu.email) == "client@example.com"
    assert cu.organization_id == org.id
  end

  test "invite/2 is idempotent (upserts on duplicate email+org)", %{org: org} do
    assert {:ok, cu1} = Accounts.invite_client_user("client@example.com", org.id)
    assert {:ok, cu2} = Accounts.invite_client_user("client@example.com", org.id)
    assert cu1.id == cu2.id
  end

  test "same email can belong to two different orgs" do
    org2 = Ash.Seed.seed!(GnomeGarden.Operations.Organization, %{name: "Other Org"})
    org3 = Ash.Seed.seed!(GnomeGarden.Operations.Organization, %{name: "Third Org"})
    assert {:ok, _} = Accounts.invite_client_user("shared@example.com", org2.id)
    assert {:ok, _} = Accounts.invite_client_user("shared@example.com", org3.id)
  end
end
