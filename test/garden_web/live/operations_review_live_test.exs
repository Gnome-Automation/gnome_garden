defmodule GnomeGardenWeb.OperationsReviewLiveTest do
  use GnomeGardenWeb.ConnCase

  setup :register_and_log_in_user

  import Phoenix.LiveViewTest

  alias GnomeGarden.Operations

  test "renders pending memory and learning proposals", %{conn: conn} do
    {:ok, _block} =
      Operations.propose_memory_block(%{
        key: "company_voice",
        label: "Company voice",
        content: "Use direct operator language."
      })

    {:ok, _entry} =
      Operations.propose_memory_entry(%{
        title: "Source pattern",
        content: "Water source produced relevant bids.",
        namespace: "procurement",
        tags: ["water"]
      })

    {:ok, _recommendation} =
      Operations.propose_learning_recommendation(%{
        title: "Update source priority",
        target_domain: :procurement,
        target_resource: "procurement_source",
        target_action: "raise_priority",
        proposed_change: %{"priority" => "high"},
        evidence: %{"accepted" => 2},
        impact_summary: "Accepted findings justify higher source priority."
      })

    {:ok, _view, html} = live(conn, ~p"/operations/review")

    assert html =~ "Review Queue"
    assert html =~ "Company voice"
    assert html =~ "Source pattern"
    assert html =~ "Update source priority"
    assert html =~ "procurement"
    assert html =~ "water"
    assert html =~ "priority: high"
    assert html =~ "accepted: 2"
    assert html =~ "Accepted findings justify higher source priority."
  end

  test "approves and rejects proposals from the review queue", %{conn: conn} do
    {:ok, block} =
      Operations.propose_memory_block(%{
        key: "source_rule",
        label: "Source rule",
        content: "Prioritize reliable public portals."
      })

    {:ok, entry} =
      Operations.propose_memory_entry(%{
        title: "Temporary note",
        content: "This note should be rejected."
      })

    {:ok, recommendation} =
      Operations.propose_learning_recommendation(%{
        title: "Candidate rule",
        target_domain: :acquisition,
        target_resource: "finding",
        target_action: "add_rule",
        proposed_change: %{"rule" => "candidate"},
        evidence: %{}
      })

    {:ok, view, _html} = live(conn, ~p"/operations/review")

    view
    |> element("#approve-#{block.id}")
    |> render_click()

    view
    |> element("#reject-#{entry.id}")
    |> render_click()

    view
    |> element("#approve-learning-#{recommendation.id}")
    |> render_click()

    assert {:ok, approved_block} = Operations.get_memory_block(block.id)
    assert approved_block.status == :active

    assert {:ok, rejected_entry} = Operations.get_memory_entry(entry.id)
    assert rejected_entry.status == :rejected

    assert {:ok, approved_recommendation} =
             Operations.get_learning_recommendation(recommendation.id)

    assert approved_recommendation.status == :approved
  end
end
