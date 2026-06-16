defmodule GnomeGardenWeb.AuthenticatedRoutesTest do
  use GnomeGardenWeb.ConnCase

  import Phoenix.LiveViewTest

  @operator_live_routes [
    "/console/agents",
    "/console/agents/evals",
    "/console/agents/workflows",
    "/console/agents/deployments/new",
    "/console/agents/runs/00000000-0000-0000-0000-000000000000",
    "/settings/users",
    "/acquisition/dashboard",
    "/acquisition/findings",
    "/acquisition/findings/00000000-0000-0000-0000-000000000000",
    "/acquisition/sources",
    "/acquisition/programs",
    "/operations/organizations",
    "/company/facts",
    "/company/profile",
    "/company/documents",
    "/company/compliance",
    "/company/sources",
    "/commercial/vendor-onboarding",
    "/company/vendor-packet",
    "/commercial/vendor-packet",
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

  test "company routes belong to the Company navigation area" do
    assert GnomeGardenWeb.Components.RailNav.area_for_path("/company/facts") == "Company"
    assert GnomeGardenWeb.Components.RailNav.area_for_path("/company/documents") == "Company"
    assert GnomeGardenWeb.Components.RailNav.area_for_path("/company/compliance") == "Company"
    assert GnomeGardenWeb.Components.RailNav.area_for_path("/company/sources") == "Company"

    assert GnomeGardenWeb.Components.RailNav.area_for_path("/company/vendor-packet") ==
             "Commercial"

    assert GnomeGardenWeb.Components.RailNav.area_for_path("/commercial/vendor-onboarding") ==
             "Commercial"

    assert Enum.any?(
             GnomeGardenWeb.Components.RailNav.area_dests("Company"),
             &(&1.path == "/company/facts")
           )

    assert Enum.any?(
             GnomeGardenWeb.Components.RailNav.area_dests("Company"),
             &(&1.path == "/company/documents")
           )

    assert Enum.any?(
             GnomeGardenWeb.Components.RailNav.area_dests("Commercial"),
             &(&1.path == "/commercial/vendor-onboarding")
           )
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
