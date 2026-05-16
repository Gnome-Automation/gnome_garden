defmodule GnomeGardenWeb.AuthenticatedRoutesTest do
  use GnomeGardenWeb.ConnCase

  import Phoenix.LiveViewTest

  @operator_live_routes [
    "/console/agents",
    "/console/agents/deployments/new",
    "/console/agents/runs/00000000-0000-0000-0000-000000000000",
    "/settings/users",
    "/acquisition/dashboard",
    "/acquisition/findings",
    "/acquisition/findings/00000000-0000-0000-0000-000000000000",
    "/acquisition/sources",
    "/acquisition/programs",
    "/operations/organizations",
    "/commercial/signals",
    "/commercial/discovery-programs",
    "/execution/projects",
    "/execution/service-tickets",
    "/finance/invoices",
    "/finance/payments",
    "/procurement/targeting"
  ]

  test "the operations workspace requires sign in", %{conn: conn} do
    conn = get(conn, ~p"/")

    assert redirected_to(conn) == ~p"/sign-in"
  end

  test "sign in uses operator text input", %{conn: conn} do
    conn = get(conn, ~p"/sign-in")
    html = html_response(conn, 200)

    assert html =~ "Operator"
    assert html =~ ~s(type="text")
    refute html =~ ~s(type="email")
  end

  test "internal operator LiveView routes require sign in", %{conn: conn} do
    for path <- @operator_live_routes do
      assert {:error, {:redirect, %{to: "/sign-in"}}} = live(conn, path)
    end
  end

  test "legacy agent page redirects to the durable agent console", %{conn: conn} do
    %{conn: conn} = register_and_log_in_user(%{conn: conn})

    conn = get(conn, "/agent")

    assert redirected_to(conn) == ~p"/console/agents"
  end

  test "admins can view user settings", %{conn: conn} do
    %{conn: conn} = register_and_log_in_user(%{conn: conn})

    assert {:ok, _view, html} = live(conn, "/settings/users")
    assert html =~ "Users"
    assert html =~ "Admin"
  end

  @tag team_member_role: :operator
  test "internal routes require an active admin team member", %{conn: conn} do
    %{conn: conn} = register_and_log_in_user(%{conn: conn, team_member_role: :operator})

    conn = get(conn, ~p"/")
    assert redirected_to(conn) == ~p"/access-denied"

    assert {:error, {:redirect, %{to: "/access-denied"}}} = live(conn, "/acquisition/findings")
  end
end
