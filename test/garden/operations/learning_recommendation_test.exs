defmodule GnomeGarden.Operations.LearningRecommendationTest do
  use GnomeGarden.DataCase, async: true

  alias GnomeGarden.Operations

  describe "learning recommendation lifecycle" do
    test "proposes, approves, applies, and lists by target" do
      target_id = Ash.UUID.generate()

      assert {:ok, recommendation} =
               Operations.propose_learning_recommendation(%{
                 title: "Raise source priority",
                 target_domain: :procurement,
                 target_resource: "procurement_source",
                 target_id: target_id,
                 target_action: "raise_priority",
                 proposed_change: %{"priority" => "high"},
                 evidence: %{"accepted_findings" => 4},
                 impact_summary: "The source repeatedly produces relevant public works bids.",
                 risk_level: :medium,
                 confidence: Decimal.new("0.78"),
                 source_type: :workflow
               })

      assert recommendation.status == :needs_review

      assert {:ok, [pending]} = Operations.list_pending_learning_recommendations()
      assert pending.id == recommendation.id

      assert {:ok, approved} =
               Operations.approve_learning_recommendation(recommendation, %{
                 review_note: "Evidence is sufficient"
               })

      assert approved.status == :approved
      assert approved.reviewed_at

      assert {:ok, applied} = Operations.apply_learning_recommendation(approved)
      assert applied.status == :applied
      assert applied.applied_at

      assert {:ok, by_target} =
               Operations.list_learning_recommendations_by_target(
                 :procurement,
                 "procurement_source",
                 target_id
               )

      assert Enum.map(by_target, & &1.id) == [recommendation.id]
    end

    test "rejects a recommendation" do
      assert {:ok, recommendation} =
               Operations.propose_learning_recommendation(%{
                 title: "Reject weak phrase rule",
                 target_domain: :acquisition,
                 target_resource: "finding",
                 target_action: "add_rejection_phrase",
                 proposed_change: %{"phrase" => "maintenance"},
                 evidence: %{"sample_size" => 1},
                 risk_level: :high
               })

      assert {:ok, rejected} =
               Operations.reject_learning_recommendation(recommendation, %{
                 review_note: "Sample is too small",
                 rejection_reason: "Insufficient evidence"
               })

      assert rejected.status == :rejected
      assert rejected.reviewed_at
      assert rejected.rejection_reason == "Insufficient evidence"
    end

    test "expires a pending recommendation" do
      assert {:ok, recommendation} =
               Operations.propose_learning_recommendation(%{
                 title: "Expired suggestion",
                 target_domain: :operations,
                 target_resource: "memory_block",
                 target_action: "update_content",
                 proposed_change: %{"content" => "Old note"},
                 evidence: %{}
               })

      assert {:ok, expired} = Operations.expire_learning_recommendation(recommendation)

      assert expired.status == :expired
      assert expired.expired_at
    end
  end
end
