defmodule GnomeGardenWeb.ClientPortal.SessionControllerTest do
  use GnomeGardenWeb.ConnCase, async: true

  alias GnomeGarden.Operations
  alias GnomeGarden.Accounts

  test "GET /portal/login renders login form", %{conn: conn} do
    conn = get(conn, ~p"/portal/login")
    assert html_response(conn, 200) =~ "Sign in"
  end

  test "POST /portal/login with unknown email silently succeeds", %{conn: conn} do
    conn = post(conn, ~p"/portal/login", %{"email" => "unknown@example.com"})
    assert html_response(conn, 200) =~ "check your email"
  end

  test "POST /portal/login with known email silently succeeds", %{conn: conn} do
    org = Ash.Seed.seed!(GnomeGarden.Operations.Organization, %{name: "Test Org"})
    person = Ash.Seed.seed!(GnomeGarden.Operations.Person, %{
      first_name: "Test",
      last_name: "Person",
      email: "known@example.com"
    })
    Ash.Seed.seed!(GnomeGarden.Operations.OrganizationAffiliation, %{
      organization_id: org.id,
      person_id: person.id,
      status: :active
    })

    conn = post(conn, ~p"/portal/login", %{"email" => "known@example.com"})
    assert html_response(conn, 200) =~ "check your email"
  end
end
