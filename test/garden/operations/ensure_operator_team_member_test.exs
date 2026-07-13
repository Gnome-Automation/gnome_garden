defmodule GnomeGarden.Operations.EnsureOperatorTeamMemberTest do
  use GnomeGarden.DataCase, async: true

  alias GnomeGarden.Accounts
  alias GnomeGarden.Operations

  test "creates, then reuses, an active operator for a registered user" do
    user = user_fixture("sam-#{System.unique_integer([:positive])}@example.com")

    assert {:ok, member} =
             Operations.ensure_operator_team_member(user.email, "Sam", authorize?: false)

    assert member.user_id == user.id
    assert member.role == :operator
    assert member.status == :active

    assert {:ok, same_member} =
             Operations.ensure_operator_team_member(user.email, "Sam", authorize?: false)

    assert same_member.id == member.id
    assert {:ok, [_only_one]} = Operations.list_team_members(authorize?: false)
  end

  test "reactivates an inactive team member instead of duplicating" do
    user = user_fixture("patrick-#{System.unique_integer([:positive])}@example.com")

    {:ok, member} =
      Operations.create_team_member(%{
        user_id: user.id,
        display_name: "Old Name",
        role: :operator,
        status: :inactive
      })

    assert {:ok, ensured} =
             Operations.ensure_operator_team_member(user.email, "Patrick", authorize?: false)

    assert ensured.id == member.id
    assert ensured.status == :active
    assert ensured.display_name == "Patrick"
  end

  test "refuses to invent credentials for unregistered emails" do
    assert {:error, error} =
             Operations.ensure_operator_team_member(
               "nobody@example.com",
               "Nobody",
               authorize?: false
             )

    assert Exception.message(error) =~ "Complete registration"
  end

  defp user_fixture(email) do
    password = "valid-password-#{System.unique_integer([:positive, :monotonic])}"

    {:ok, user} =
      Accounts.create_user_with_password(%{
        email: email,
        password: password,
        password_confirmation: password
      })

    user
  end
end
