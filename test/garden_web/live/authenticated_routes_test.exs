defmodule GnomeGardenWeb.AuthenticatedRoutesTest do
  use GnomeGardenWeb.ConnCase

  import Phoenix.LiveViewTest

  test "internal operator routes require sign in", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/sign-in"}}} = live(conn, ~p"/acquisition/findings")
  end
end
