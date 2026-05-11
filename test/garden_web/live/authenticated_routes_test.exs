defmodule GnomeGardenWeb.AuthenticatedRoutesTest do
  use GnomeGardenWeb.ConnCase

  import Phoenix.LiveViewTest

  @operator_live_routes [
    "/agent",
    "/console/agents",
    "/console/agents/deployments/new",
    "/console/agents/runs/00000000-0000-0000-0000-000000000000",
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

  test "internal operator LiveView routes require sign in", %{conn: conn} do
    for path <- @operator_live_routes do
      assert {:error, {:redirect, %{to: "/sign-in"}}} = live(conn, path)
    end
  end
end
