defmodule GnomeGardenWeb.TargetDiscoveryLiveTest do
  use GnomeGardenWeb.ConnCase

  import Phoenix.LiveViewTest

  alias GnomeGarden.Commercial
  alias GnomeGarden.Operations

  test "target backlog queues render by status", %{conn: conn} do
    {:ok, discovery_program} =
      Commercial.create_discovery_program(%{
        name: "Food and Beverage Sweep",
        target_regions: ["oc"],
        target_industries: ["food"],
        search_terms: ["orange county food manufacturing automation"],
        watch_channels: ["news_site"]
      })

    {:ok, review_target} =
      Commercial.create_target_account(%{
        discovery_program_id: discovery_program.id,
        name: "Review Foods",
        website: "https://review-foods.example.com",
        fit_score: 78,
        intent_score: 82
      })

    {:ok, promoted_target} =
      Commercial.create_target_account(%{
        discovery_program_id: discovery_program.id,
        name: "Promoted Foods",
        website: "https://promoted-foods.example.com",
        fit_score: 80,
        intent_score: 84
      })

    {:ok, promoted_target} = Commercial.promote_target_account_to_signal(promoted_target)

    {:ok, rejected_target} =
      Commercial.create_target_account(%{
        discovery_program_id: discovery_program.id,
        name: "Rejected Foods",
        website: "https://rejected-foods.example.com",
        fit_score: 42,
        intent_score: 33
      })

    {:ok, _rejected_target} = Commercial.reject_target_account(rejected_target, %{})

    {:ok, archived_target} =
      Commercial.create_target_account(%{
        discovery_program_id: discovery_program.id,
        name: "Archived Foods",
        website: "https://archived-foods.example.com",
        fit_score: 40,
        intent_score: 25
      })

    {:ok, _archived_target} = Commercial.archive_target_account(archived_target)

    {:ok, review_view, review_html} = live(conn, ~p"/commercial/targets")
    assert has_element?(review_view, "#targets")
    review_table = review_view |> element("#targets") |> render()
    assert review_html =~ "Review Queue"
    assert review_table =~ review_target.name
    refute review_table =~ promoted_target.name

    {:ok, promoted_view, promoted_html} = live(conn, ~p"/commercial/targets?queue=promoted")
    assert has_element?(promoted_view, "#targets")
    promoted_table = promoted_view |> element("#targets") |> render()
    assert promoted_html =~ "Promoted"
    assert promoted_table =~ promoted_target.name
    refute promoted_table =~ review_target.name

    {:ok, rejected_view, rejected_html} = live(conn, ~p"/commercial/targets?queue=rejected")
    assert has_element?(rejected_view, "#targets")
    rejected_table = rejected_view |> element("#targets") |> render()
    assert rejected_html =~ "Rejected"
    assert rejected_table =~ rejected_target.name

    {:ok, archived_view, archived_html} = live(conn, ~p"/commercial/targets?queue=archived")
    assert has_element?(archived_view, "#targets")
    archived_table = archived_view |> element("#targets") |> render()
    assert archived_html =~ "Archived"
    assert archived_table =~ archived_target.name
  end

  test "target backlog supports discovery program filtering and inline transitions", %{conn: conn} do
    {:ok, program_one} =
      Commercial.create_discovery_program(%{
        name: "OC Packaging Sweep",
        target_regions: ["oc"],
        target_industries: ["packaging"]
      })

    {:ok, program_two} =
      Commercial.create_discovery_program(%{
        name: "LA Food Sweep",
        target_regions: ["la"],
        target_industries: ["food_bev"]
      })

    {:ok, promoted_target} =
      Commercial.create_target_account(%{
        discovery_program_id: program_one.id,
        name: "Program One Promote",
        website: "https://program-one-promote.example.com",
        fit_score: 81,
        intent_score: 85
      })

    {:ok, rejected_target} =
      Commercial.create_target_account(%{
        discovery_program_id: program_one.id,
        name: "Program One Reject",
        website: "https://program-one-reject.example.com",
        fit_score: 62,
        intent_score: 48
      })

    {:ok, other_program_target} =
      Commercial.create_target_account(%{
        discovery_program_id: program_two.id,
        name: "Program Two Review",
        website: "https://program-two-review.example.com",
        fit_score: 77,
        intent_score: 74
      })

    {:ok, view, _html} = live(conn, ~p"/commercial/targets?program_id=#{program_one.id}")

    assert render(view) =~ program_one.name
    assert render(view) =~ promoted_target.name
    assert render(view) =~ rejected_target.name
    refute render(view) =~ other_program_target.name

    view
    |> element("#transition-promote_to_signal-#{promoted_target.id}")
    |> render_click()

    view
    |> element("#transition-reject-#{rejected_target.id}")
    |> render_click()

    refute render(view) =~ promoted_target.name
    refute render(view) =~ rejected_target.name

    {:ok, promoted_view, _promoted_html} =
      live(conn, ~p"/commercial/targets?queue=promoted&program_id=#{program_one.id}")

    assert render(promoted_view) =~ promoted_target.name
    refute render(promoted_view) =~ other_program_target.name

    {:ok, rejected_view, _rejected_html} =
      live(conn, ~p"/commercial/targets?queue=rejected&program_id=#{program_one.id}")

    assert render(rejected_view) =~ rejected_target.name
    refute render(rejected_view) =~ other_program_target.name
  end

  test "target observation routes render", %{conn: conn} do
    {:ok, discovery_program} =
      Commercial.create_discovery_program(%{
        name: "Packaging Watch",
        target_regions: ["oc"],
        target_industries: ["packaging"],
        search_terms: ["packaging automation orange county"],
        watch_channels: ["company_website"]
      })

    {:ok, target_account} =
      Commercial.create_target_account(%{
        discovery_program_id: discovery_program.id,
        name: "Harbor Packaging",
        website: "https://harbor-packaging.example.com",
        fit_score: 76,
        intent_score: 79
      })

    {:ok, observation} =
      Commercial.create_target_observation(%{
        target_account_id: target_account.id,
        discovery_program_id: discovery_program.id,
        observation_type: :website_contact,
        source_channel: :company_website,
        external_ref: "live:harbor-packaging:contact",
        source_url: "https://harbor-packaging.example.com/contact",
        observed_at: DateTime.utc_now(),
        confidence_score: 81,
        summary: "Public controls retrofit contact page with project intake form",
        evidence_points: ["Has controls project form", "Mentions modernization work"]
      })

    {:ok, index_view, index_html} = live(conn, ~p"/commercial/observations")
    assert has_element?(index_view, "#target-observations")
    assert index_html =~ observation.summary

    {:ok, show_view, _show_html} = live(conn, ~p"/commercial/observations/#{observation}")
    assert render(show_view) =~ observation.summary
    assert render(show_view) =~ target_account.name

    {:ok, form_view, _form_html} =
      live(
        conn,
        ~p"/commercial/observations/new?target_account_id=#{target_account.id}&discovery_program_id=#{discovery_program.id}"
      )

    assert has_element?(form_view, "#target-observation-form")
  end

  test "target show resolves candidate identities inline", %{conn: conn} do
    {:ok, organization} =
      Operations.create_organization(%{
        name: "North Coast Packaging",
        status: :prospect,
        relationship_roles: ["prospect"],
        website: "https://northcoastpackaging.com"
      })

    {:ok, person} =
      Operations.create_person(%{
        first_name: "Maya",
        last_name: "Lopez",
        email: "maya@northcoastpackaging.com"
      })

    {:ok, _affiliation} =
      Operations.create_organization_affiliation(%{
        organization_id: organization.id,
        person_id: person.id,
        title: "Controls Engineer",
        is_primary: true
      })

    {:ok, target_account} =
      Commercial.create_target_account(%{
        name: "North Coast Packaging",
        website: "https://northcoastpackaging.com",
        fit_score: 82,
        intent_score: 86,
        metadata: %{
          contact_snapshot: %{
            first_name: "Maya",
            last_name: "Lopez",
            title: "Controls Engineer",
            email: "maya@northcoastpackaging.com"
          }
        }
      })

    {:ok, view, _html} = live(conn, ~p"/commercial/targets/#{target_account}")

    assert has_element?(view, "#use-organization-#{organization.id}")
    assert has_element?(view, "#use-person-#{person.id}")

    view
    |> element("#use-person-#{person.id}")
    |> render_click()

    assert render(view) =~ organization.name
    assert render(view) =~ person.first_name

    {:ok, refreshed_target_account} =
      Commercial.get_target_account(target_account.id, load: [:organization, :contact_person])

    assert refreshed_target_account.organization_id == organization.id
    assert refreshed_target_account.contact_person_id == person.id
  end

  test "target show can merge linked duplicate identities into a candidate", %{conn: conn} do
    {:ok, canonical_organization} =
      Operations.create_organization(%{
        name: "North Coast Packaging",
        status: :prospect,
        relationship_roles: ["prospect"],
        website: "https://northcoastpackaging.com"
      })

    {:ok, duplicate_organization} =
      Operations.create_organization(%{
        name: "North Coast Packaging, Inc.",
        status: :active,
        relationship_roles: ["prospect", "customer"]
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
        organization_id: canonical_organization.id,
        person_id: canonical_person.id,
        title: "Controls Engineer",
        is_primary: true
      })

    {:ok, _duplicate_affiliation} =
      Operations.create_organization_affiliation(%{
        organization_id: duplicate_organization.id,
        person_id: duplicate_person.id,
        title: "Controls Engineer",
        is_primary: true
      })

    {:ok, target_account} =
      Commercial.create_target_account(%{
        name: "North Coast Packaging",
        website: "https://northcoastpackaging.com",
        organization_id: duplicate_organization.id,
        contact_person_id: duplicate_person.id,
        fit_score: 82,
        intent_score: 86,
        metadata: %{
          contact_snapshot: %{
            first_name: "Maya",
            last_name: "Lopez",
            title: "Controls Engineer",
            email: "maya@northcoastpackaging.com"
          }
        }
      })

    {:ok, view, _html} = live(conn, ~p"/commercial/targets/#{target_account}")

    assert has_element?(view, "#merge-linked-organization-#{canonical_organization.id}")
    assert has_element?(view, "#merge-linked-person-#{canonical_person.id}")

    view
    |> element("#merge-linked-organization-#{canonical_organization.id}")
    |> render_click()

    view
    |> element("#merge-linked-person-#{canonical_person.id}")
    |> render_click()

    {:ok, refreshed_target_account} =
      Commercial.get_target_account(target_account.id, load: [:organization, :contact_person])

    assert refreshed_target_account.organization_id == canonical_organization.id
    assert refreshed_target_account.contact_person_id == canonical_person.id

    assert {:ok, merged_organization} = Operations.get_organization(duplicate_organization.id)
    assert merged_organization.status == :archived
    assert merged_organization.merged_into_id == canonical_organization.id

    assert {:ok, merged_person} = Operations.get_person(duplicate_person.id)
    assert merged_person.status == :archived
    assert merged_person.merged_into_id == canonical_person.id
  end
end
