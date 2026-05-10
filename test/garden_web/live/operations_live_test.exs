defmodule GnomeGardenWeb.OperationsLiveTest do
  use GnomeGardenWeb.ConnCase

  setup :register_and_log_in_user

  import Phoenix.LiveViewTest

  alias GnomeGarden.Operations

  test "organizations index renders organization records", %{conn: conn} do
    {:ok, organization} =
      Operations.create_organization(%{
        name: "Acme Controls",
        organization_kind: :business,
        status: :prospect
      })

    assert {:ok, persisted_organization} = Operations.get_organization(organization.id)
    assert persisted_organization.name == organization.name

    {:ok, view, _html} = live(conn, ~p"/operations/organizations")
    assert render(view) =~ "Organizations"
  end

  test "organization show renders linked people and commercial context", %{conn: conn} do
    {:ok, organization} =
      Operations.create_organization(%{
        name: "Atlas Automation",
        organization_kind: :business,
        status: :active,
        relationship_roles: ["customer"]
      })

    {:ok, person} =
      Operations.create_person(%{
        first_name: "Maya",
        last_name: "Lopez",
        email: "maya@example.com"
      })

    {:ok, _affiliation} =
      Operations.create_organization_affiliation(%{
        organization_id: organization.id,
        person_id: person.id,
        status: :active,
        is_primary: true
      })

    {:ok, view, _html} = live(conn, ~p"/operations/organizations/#{organization}")

    assert has_element?(view, "#organization-people")
    assert has_element?(view, "#organization-commercial")
    assert render(view) =~ person.first_name
  end

  test "organization show surfaces duplicate merge candidates and merges into canonical record",
       %{
         conn: conn
       } do
    {:ok, canonical_organization} =
      Operations.create_organization(%{
        name: "North Coast Packaging",
        organization_kind: :business,
        status: :prospect,
        relationship_roles: ["prospect"],
        website: "https://northcoastpackaging.com"
      })

    {:ok, duplicate_organization} =
      Operations.create_organization(%{
        name: "North Coast Packaging, Inc.",
        organization_kind: :business,
        status: :active,
        relationship_roles: ["customer"]
      })

    {:ok, view, _html} = live(conn, ~p"/operations/organizations/#{duplicate_organization}")

    assert has_element?(view, "#organization-merge-candidates")
    assert render(view) =~ "Same Normalized Name"
    assert has_element?(view, "#merge-organization-#{canonical_organization.id}")

    view
    |> element("#merge-organization-#{canonical_organization.id}")
    |> render_click()

    assert render(view) =~ canonical_organization.name

    assert {:ok, merged_duplicate} = Operations.get_organization(duplicate_organization.id)
    assert merged_duplicate.merged_into_id == canonical_organization.id
    assert merged_duplicate.status == :archived
  end

  test "people index renders durable external contacts", %{conn: conn} do
    {:ok, person} =
      Operations.create_person(%{
        first_name: "Nina",
        last_name: "Patel",
        email: "nina@example.com",
        status: :active
      })

    assert {:ok, persisted_person} = Operations.get_person(person.id)
    assert persisted_person.first_name == person.first_name
    assert persisted_person.last_name == person.last_name

    {:ok, view, _html} = live(conn, ~p"/operations/people")
    assert render(view) =~ "People"
  end

  test "person show renders linked organizations", %{conn: conn} do
    {:ok, organization} =
      Operations.create_organization(%{
        name: "Beacon Systems",
        organization_kind: :business,
        status: :active,
        relationship_roles: ["partner"]
      })

    {:ok, person} =
      Operations.create_person(%{
        first_name: "Jordan",
        last_name: "Kim",
        email: "jordan@example.com",
        preferred_contact_method: :email
      })

    {:ok, _affiliation} =
      Operations.create_organization_affiliation(%{
        organization_id: organization.id,
        person_id: person.id,
        title: "Operations Director",
        status: :active
      })

    {:ok, view, _html} = live(conn, ~p"/operations/people/#{person}")

    assert has_element?(view, "#person-organizations")
    assert render(view) =~ organization.name
  end

  test "person show surfaces duplicate merge candidates and merges into canonical record", %{
    conn: conn
  } do
    {:ok, organization} =
      Operations.create_organization(%{
        name: "North Coast Packaging",
        organization_kind: :business,
        status: :active,
        relationship_roles: ["prospect"]
      })

    {:ok, canonical_person} =
      Operations.create_person(%{
        first_name: "Maya",
        last_name: "Lopez",
        email: "maya@northcoastpackaging.com"
      })

    {:ok, duplicate_person} =
      Operations.create_person(%{
        first_name: "Maya",
        last_name: "Lopez",
        phone: "555-0100"
      })

    {:ok, _canonical_affiliation} =
      Operations.create_organization_affiliation(%{
        organization_id: organization.id,
        person_id: canonical_person.id,
        title: "Controls Engineer",
        status: :active
      })

    {:ok, _duplicate_affiliation} =
      Operations.create_organization_affiliation(%{
        organization_id: organization.id,
        person_id: duplicate_person.id,
        title: "Controls Engineer",
        status: :active
      })

    {:ok, view, _html} = live(conn, ~p"/operations/people/#{duplicate_person}")

    assert has_element?(view, "#person-merge-candidates")
    assert render(view) =~ "Same Normalized Name"
    assert render(view) =~ "Shared Organization"
    assert has_element?(view, "#merge-person-#{canonical_person.id}")

    view
    |> element("#merge-person-#{canonical_person.id}")
    |> render_click()

    assert render(view) =~ canonical_person.first_name

    assert {:ok, merged_duplicate} = Operations.get_person(duplicate_person.id)
    assert merged_duplicate.merged_into_id == canonical_person.id
    assert merged_duplicate.status == :archived
  end

  test "operations forms render", %{conn: conn} do
    {:ok, organization_view, _html} = live(conn, ~p"/operations/organizations/new")
    {:ok, person_view, _html} = live(conn, ~p"/operations/people/new")

    assert has_element?(organization_view, "#organization-form")
    assert has_element?(person_view, "#person-form")
  end

  test "site routes render", %{conn: conn} do
    {:ok, organization} =
      Operations.create_organization(%{
        name: "Pioneer Controls",
        organization_kind: :business,
        status: :active
      })

    {:ok, site} =
      Operations.create_site(%{
        organization_id: organization.id,
        name: "Plant 3",
        site_kind: :facility,
        status: :active
      })

    {:ok, _index_view, _index_html} = live(conn, ~p"/operations/sites")

    {:ok, show_view, _show_html} = live(conn, ~p"/operations/sites/#{site}")
    assert render(show_view) =~ site.name

    {:ok, form_view, _form_html} =
      live(conn, ~p"/operations/sites/new?organization_id=#{organization.id}")

    assert has_element?(form_view, "#site-form")
  end

  test "managed system routes render", %{conn: conn} do
    {:ok, organization} =
      Operations.create_organization(%{
        name: "Horizon Integration",
        organization_kind: :business,
        status: :active
      })

    {:ok, site} =
      Operations.create_site(%{
        organization_id: organization.id,
        name: "Remote Ops",
        site_kind: :cloud,
        status: :active
      })

    {:ok, managed_system} =
      Operations.create_managed_system(%{
        organization_id: organization.id,
        site_id: site.id,
        code: "SYS-100",
        name: "Ignition Core",
        system_type: :automation
      })

    {:ok, _index_view, _index_html} = live(conn, ~p"/operations/managed-systems")

    {:ok, show_view, _show_html} = live(conn, ~p"/operations/managed-systems/#{managed_system}")
    assert render(show_view) =~ managed_system.code

    {:ok, form_view, _form_html} =
      live(conn, ~p"/operations/managed-systems/new?site_id=#{site.id}")

    assert has_element?(form_view, "#managed-system-form")
  end

  test "affiliations index and show render linked records", %{conn: conn} do
    {:ok, organization} =
      Operations.create_organization(%{
        name: "North Star Fabrication",
        organization_kind: :business,
        status: :active
      })

    {:ok, person} =
      Operations.create_person(%{
        first_name: "Avery",
        last_name: "Stone",
        email: "avery@example.com"
      })

    {:ok, affiliation} =
      Operations.create_organization_affiliation(%{
        organization_id: organization.id,
        person_id: person.id,
        title: "Plant Manager",
        contact_roles: ["decision_maker"],
        status: :active,
        is_primary: true
      })

    {:ok, _index_view, _index_html} = live(conn, ~p"/operations/affiliations")

    {:ok, show_view, _show_html} = live(conn, ~p"/operations/affiliations/#{affiliation}")
    assert render(show_view) =~ "Plant Manager"
    assert render(show_view) =~ organization.name
  end

  test "affiliation form renders with prefilled organization and person params", %{conn: conn} do
    {:ok, organization} =
      Operations.create_organization(%{
        name: "Delta Controls",
        organization_kind: :business,
        status: :prospect
      })

    {:ok, person} =
      Operations.create_person(%{
        first_name: "Casey",
        last_name: "Wong",
        email: "casey@example.com"
      })

    {:ok, view, _html} =
      live(
        conn,
        ~p"/operations/affiliations/new?#{[organization_id: organization.id, person_id: person.id]}"
      )

    assert has_element?(view, "#organization-affiliation-form")
  end
end
