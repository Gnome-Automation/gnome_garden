defmodule GnomeGardenWeb.DevAuthControllerTest do
  use GnomeGardenWeb.ConnCase, async: false

  alias GnomeGarden.Accounts
  alias GnomeGarden.Operations

  test "sign_in creates an active admin session", %{conn: conn} do
    conn =
      conn
      |> Phoenix.ConnTest.init_test_session(%{})
      |> fetch_flash()

    conn =
      GnomeGardenWeb.DevAuthController.sign_in(conn, %{
        "return_to" => "/acquisition/sources"
      })

    assert redirected_to(conn) == "/acquisition/sources"
    assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "Signed in as"

    assert {:ok, user} = Accounts.get_user_by_email("dev-admin@example.com", authorize?: false)
    assert is_binary(get_session(conn, "user_token"))

    assert {:ok, team_member} =
             Operations.get_team_member_by_user(user.id, authorize?: false)

    assert team_member.role == :admin
    assert team_member.status == :active
  end
end
