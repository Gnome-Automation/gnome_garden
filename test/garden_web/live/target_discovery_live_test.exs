defmodule GnomeGardenWeb.TargetDiscoveryLiveTest do
  use GnomeGardenWeb.ConnCase

  import Phoenix.LiveViewTest

  alias GnomeGarden.Commercial

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
end
