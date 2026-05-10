defmodule GnomeGardenWeb.DiscoveryRecordLiveTest do
  use GnomeGardenWeb.ConnCase

  setup :register_and_log_in_user

  import Phoenix.LiveViewTest

  alias GnomeGarden.Acquisition
  alias GnomeGarden.Commercial
  alias GnomeGarden.Operations

  test "acquisition evidence routes render for discovery findings", %{
    conn: conn
  } do
    {:ok, discovery_program} =
      Commercial.create_discovery_program(%{
        name: "Packaging Watch",
        target_regions: ["oc"],
        target_industries: ["packaging"],
        search_terms: ["packaging automation orange county"],
        watch_channels: ["company_website"]
      })

    {:ok, discovery_record} =
      Commercial.create_discovery_record(%{
        discovery_program_id: discovery_program.id,
        name: "Harbor Packaging",
        website: "https://harbor-packaging.example.com",
        fit_score: 76,
        intent_score: 79
      })

    {:ok, finding} = Acquisition.get_finding_by_source_discovery_record(discovery_record.id)

    {:ok, observation} =
      Commercial.create_discovery_evidence(%{
        discovery_record_id: discovery_record.id,
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

    {:ok, form_view, _form_html} =
      live(conn, ~p"/acquisition/findings/#{finding.id}/evidence/new")

    assert has_element?(form_view, "#finding-evidence-form")
    assert render(form_view) =~ "Intake Finding"
    assert render(form_view) =~ discovery_program.name
    assert render(form_view) =~ "Evidence Context"

    {:ok, edit_view, _edit_html} = live(conn, ~p"/acquisition/evidence/#{observation}/edit")
    assert has_element?(edit_view, "#finding-evidence-form")
    assert render(edit_view) =~ "Edit Evidence"
    assert render(edit_view) =~ observation.summary
  end

  test "finding detail resolves candidate identities inline", %{conn: conn} do
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

    {:ok, discovery_record} =
      Commercial.create_discovery_record(%{
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

    {:ok, finding} = Acquisition.get_finding_by_source_discovery_record(discovery_record.id)
    {:ok, view, _html} = live(conn, ~p"/acquisition/findings/#{finding.id}")

    assert has_element?(view, "#finding-use-organization-#{organization.id}")
    assert has_element?(view, "#finding-use-person-#{person.id}")

    view
    |> element("#finding-use-person-#{person.id}")
    |> render_click()

    assert has_element?(view, ~s(a[href="/operations/organizations/#{organization.id}"]))
    assert has_element?(view, ~s(a[href="/operations/people/#{person.id}"]))

    {:ok, refreshed_discovery_record} =
      Commercial.get_discovery_record(discovery_record.id,
        load: [:organization, :contact_person]
      )

    assert refreshed_discovery_record.organization_id == organization.id
    assert refreshed_discovery_record.contact_person_id == person.id
  end

  test "finding detail can merge linked duplicate identities into a candidate", %{conn: conn} do
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

    {:ok, discovery_record} =
      Commercial.create_discovery_record(%{
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

    {:ok, finding} = Acquisition.get_finding_by_source_discovery_record(discovery_record.id)
    {:ok, view, _html} = live(conn, ~p"/acquisition/findings/#{finding.id}")

    assert has_element?(view, "#finding-merge-linked-organization-#{canonical_organization.id}")
    assert has_element?(view, "#finding-merge-linked-person-#{canonical_person.id}")

    view
    |> element("#finding-merge-linked-organization-#{canonical_organization.id}")
    |> render_click()

    view
    |> element("#finding-merge-linked-person-#{canonical_person.id}")
    |> render_click()

    {:ok, refreshed_discovery_record} =
      Commercial.get_discovery_record(discovery_record.id,
        load: [:organization, :contact_person]
      )

    assert refreshed_discovery_record.organization_id == canonical_organization.id
    assert refreshed_discovery_record.contact_person_id == canonical_person.id

    assert {:ok, merged_organization} = Operations.get_organization(duplicate_organization.id)
    assert merged_organization.status == :archived
    assert merged_organization.merged_into_id == canonical_organization.id

    assert {:ok, merged_person} = Operations.get_person(duplicate_person.id)
    assert merged_person.status == :archived
    assert merged_person.merged_into_id == canonical_person.id
  end

  test "finding detail captures structured discovery rejection feedback", %{conn: conn} do
    {:ok, program} =
      Commercial.create_discovery_program(%{
        name: "County Workflow Sweep",
        target_regions: ["oc"],
        target_industries: ["public_sector"]
      })

    {:ok, discovery_record} =
      Commercial.create_discovery_record(%{
        discovery_program_id: program.id,
        name: "County Workflow Office",
        website: "https://county-workflow.example.com",
        industry: "public sector",
        fit_score: 44,
        intent_score: 38,
        metadata: %{
          market_focus: %{
            "company_profile_key" => "primary",
            "company_profile_mode" => "industrial_plus_software",
            "icp_matches" => ["operations software/web"],
            "risk_flags" => ["wrong buyer / admin-side scope"]
          }
        }
      })

    {:ok, finding} = Acquisition.get_finding_by_source_discovery_record(discovery_record.id)
    {:ok, view, _html} = live(conn, ~p"/acquisition/findings/#{finding.id}")

    assert render(view) =~ "Discovery Context"
    assert has_element?(view, "#finding-show-discovery-icp")
    assert has_element?(view, "#finding-show-discovery-risks")
    assert render(view) =~ "Program Queue"

    view
    |> element("#finding-show-start-review")
    |> render_click()

    view
    |> element("#finding-show-reject")
    |> render_click()

    assert has_element?(view, "#finding-show-reject-form select[name='reason_code']")

    view
    |> form("#finding-show-reject-form", %{
      "reason_code" => "wrong_buyer_admin",
      "reason" => "Administrative workflow team, not plant operations",
      "feedback_scope" => "out_of_scope",
      "exclude_terms" => "county workflow, permitting portal"
    })
    |> render_submit()

    assert render(view) =~ "Discovery Feedback"
    assert render(view) =~ "Wrong buyer / admin-side target"
    assert render(view) =~ "county workflow"

    {:ok, refreshed_discovery_record} = Commercial.get_discovery_record(discovery_record.id)

    assert refreshed_discovery_record.status == :rejected

    feedback = refreshed_discovery_record.metadata["discovery_feedback"]
    assert feedback["reason_code"] == "wrong_buyer_admin"
    assert feedback["feedback_scope"] == "out_of_scope"
  end
end
