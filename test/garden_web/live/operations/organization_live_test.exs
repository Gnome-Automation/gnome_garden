defmodule GnomeGardenWeb.Operations.OrganizationLiveTest do
  use GnomeGardenWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  setup :register_and_log_in_user

  test "organization show page renders invite button", %{conn: conn} do
    org = Ash.Seed.seed!(GnomeGarden.Operations.Organization, %{name: "Test Org"})
    {:ok, _view, html} = live(conn, ~p"/operations/organizations/#{org.id}")
    assert html =~ "Invite to portal"
  end

  test "invite_to_portal sends invitation", %{conn: conn} do
    org = Ash.Seed.seed!(GnomeGarden.Operations.Organization, %{name: "Test Org"})
    person = Ash.Seed.seed!(GnomeGarden.Operations.Person, %{first_name: "Test", last_name: "User", email: "portaltest_#{System.unique_integer([:positive])}@example.com"})
    Ash.Seed.seed!(GnomeGarden.Operations.OrganizationAffiliation, %{
      organization_id: org.id,
      person_id: person.id,
      status: :active
    })

    {:ok, view, _html} = live(conn, ~p"/operations/organizations/#{org.id}")

    html =
      view
      |> form("#invite-portal-form", invite: %{email: person.email})
      |> render_submit()

    assert html =~ "invited"
  end
end
