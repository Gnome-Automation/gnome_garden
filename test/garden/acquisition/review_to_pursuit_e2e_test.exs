defmodule GnomeGarden.Acquisition.ReviewToPursuitE2ETest do
  use GnomeGarden.DataCase, async: false

  alias GnomeGarden.{Accounts, Acquisition, Commercial, Procurement}
  alias GnomeGarden.Commercial.Review

  test "human review promotes discovery and procurement findings into idempotent pursuits" do
    actor = actor_fixture()
    suffix = System.unique_integer([:positive])
    discovery = discovery_finding_fixture(suffix, actor)
    procurement = procurement_finding_fixture(suffix, actor)

    GnomeGardenWeb.Endpoint.subscribe("finding:updated")

    assert {:error, "finding must be accepted in acquisition before commercial pursuit"} =
             Review.accept_review_item(%{finding_id: discovery.finding.id}, actor: actor)

    discovery_feedback = %{
      reason: "Strong operating-company evidence and target-market fit.",
      reason_code: "qualified_company",
      feedback_scope: "program_source",
      exclude_terms: ["staffing agency"]
    }

    procurement_feedback = %{
      reason: "Qualified controls scope with a complete solicitation packet.",
      reason_code: "qualified_bid",
      feedback_scope: "source",
      exclude_terms: ["commodity only"]
    }

    assert {:ok, _finding} =
             Acquisition.start_review_for_finding(discovery.finding.id, actor: actor)

    assert {:ok, _finding} =
             Acquisition.accept_finding_review(
               discovery.finding.id,
               discovery_feedback,
               actor: actor
             )

    assert_receive %{topic: "finding:updated"}

    assert {:ok, _finding} =
             Acquisition.start_review_for_finding(procurement.finding.id, actor: actor)

    assert {:ok, _finding} =
             Acquisition.accept_finding_review(
               procurement.finding.id,
               procurement_feedback,
               actor: actor
             )

    assert_receive %{topic: "finding:updated"}

    assert {:ok, discovery_result} =
             Review.accept_review_item(
               %{
                 finding_id: discovery.finding.id,
                 reason: discovery_feedback.reason,
                 target_value: "85000"
               },
               actor: actor
             )

    assert {:ok, procurement_result} =
             Review.accept_review_item(
               %{
                 bid_id: procurement.bid.id,
                 reason: procurement_feedback.reason,
                 target_value: "175000"
               },
               actor: actor
             )

    assert_review_history(discovery.finding.id, discovery_feedback, actor)
    assert_review_history(procurement.finding.id, procurement_feedback, actor)

    assert {:ok, discovery_finding} = Acquisition.get_finding(discovery.finding.id)
    assert discovery_finding.status == :promoted
    assert discovery_finding.signal_id == discovery_result.signal.id

    assert {:ok, discovery_record} =
             Commercial.get_discovery_record(discovery.record.id)

    assert discovery_record.promoted_signal_id == discovery_result.signal.id
    assert discovery_result.signal.metadata["finding_id"] == discovery.finding.id
    assert discovery_result.pursuit.signal_id == discovery_result.signal.id
    assert discovery_result.pursuit.pursuit_type == :new_logo
    assert discovery_result.pursuit.organization_id == discovery_result.signal.organization_id

    assert {:ok, procurement_finding} = Acquisition.get_finding(procurement.finding.id)
    assert procurement_finding.status == :promoted
    assert procurement_finding.signal_id == procurement_result.signal.id

    assert {:ok, procurement_bid} = Procurement.get_bid(procurement.bid.id)
    assert procurement_bid.signal_id == procurement_result.signal.id
    assert procurement_bid.status == :pursuing
    assert procurement_result.pursuit.signal_id == procurement_result.signal.id
    assert procurement_result.pursuit.pursuit_type == :bid_response
    assert procurement_result.pursuit.organization_id == procurement_bid.organization_id

    assert {:ok, repeated_discovery} =
             Review.accept_review_item(
               %{finding_id: discovery.finding.id, reason: discovery_feedback.reason},
               actor: actor
             )

    assert {:ok, repeated_procurement} =
             Review.accept_review_item(
               %{bid_id: procurement.bid.id, reason: procurement_feedback.reason},
               actor: actor
             )

    assert repeated_discovery.signal.id == discovery_result.signal.id
    assert repeated_discovery.pursuit.id == discovery_result.pursuit.id
    assert repeated_procurement.signal.id == procurement_result.signal.id
    assert repeated_procurement.pursuit.id == procurement_result.pursuit.id

    assert {:ok, signals} = Commercial.list_signals()
    assert {:ok, pursuits} = Commercial.list_pursuits()

    assert MapSet.new(signals, & &1.id) ==
             MapSet.new([discovery_result.signal.id, procurement_result.signal.id])

    assert MapSet.new(pursuits, & &1.id) ==
             MapSet.new([discovery_result.pursuit.id, procurement_result.pursuit.id])
  end

  defp assert_review_history(finding_id, feedback, actor) do
    assert {:ok, decisions} =
             Acquisition.list_finding_review_decisions_for_finding(finding_id)

    assert MapSet.new(decisions, & &1.decision) ==
             MapSet.new([:started_review, :accepted, :promoted])

    assert Enum.all?(decisions, &(&1.actor_user_id == actor.id))
    accepted = Enum.find(decisions, &(&1.decision == :accepted))
    assert accepted.reason == feedback.reason
    assert accepted.reason_code == feedback.reason_code
    assert accepted.feedback_scope == feedback.feedback_scope
    assert accepted.exclude_terms == feedback.exclude_terms
    assert is_map(accepted.metadata["decision_snapshot"])
  end

  defp discovery_finding_fixture(suffix, actor) do
    {:ok, program} =
      Commercial.create_discovery_program(
        %{
          name: "Review E2E Discovery #{suffix}",
          target_regions: ["orange county"],
          target_industries: ["manufacturing"]
        },
        actor: actor
      )

    {:ok, record} =
      Commercial.create_discovery_record(
        %{
          discovery_program_id: program.id,
          name: "Review E2E Manufacturer #{suffix}",
          website: "https://review-e2e-#{suffix}.example.com",
          region: "orange county",
          fit_score: 86,
          intent_score: 82,
          notes: "Verified manufacturer planning a controls modernization."
        },
        actor: actor
      )

    {:ok, _evidence} =
      Commercial.create_discovery_evidence(
        %{
          discovery_record_id: record.id,
          discovery_program_id: program.id,
          observation_type: :expansion,
          source_channel: :company_website,
          external_ref: "review-e2e-discovery-evidence-#{suffix}",
          source_url: "https://review-e2e-#{suffix}.example.com/capabilities",
          observed_at: DateTime.utc_now(),
          confidence_score: 88,
          summary: "First-party capabilities and expansion evidence.",
          evidence_points: ["operating_company", "controls_modernization"]
        },
        actor: actor
      )

    {:ok, finding} = Acquisition.get_finding_by_source_discovery_record(record.id, actor: actor)
    %{record: record, finding: finding}
  end

  defp procurement_finding_fixture(suffix, actor) do
    {:ok, bid} =
      Procurement.create_bid(
        %{
          title: "Review E2E Controls Procurement #{suffix}",
          url: "https://procurement.example.test/review-e2e-#{suffix}",
          external_id: "REVIEW-E2E-#{suffix}",
          agency: "Review E2E Water District",
          region: :oc,
          location: "Orange County, CA",
          description: "SCADA, controls integration, and operator reporting modernization.",
          due_at: DateTime.utc_now() |> DateTime.add(30, :day)
        },
        actor: actor
      )

    {:ok, finding} = Acquisition.get_finding_by_source_bid(bid.id, actor: actor)
    {:ok, _document} = create_linked_document(finding, actor)
    %{bid: bid, finding: finding}
  end

  defp create_linked_document(finding, actor) do
    path = Path.join(System.tmp_dir!(), "#{Ecto.UUID.generate()}-review-e2e-packet.pdf")
    File.write!(path, "review e2e procurement packet")
    on_exit(fn -> File.rm(path) end)

    Acquisition.upload_document_for_finding(
      %{
        title: "Review E2E solicitation packet",
        summary: "Solicitation packet retained for promotion review.",
        document_type: :solicitation,
        source_url: finding.source_url,
        file: %Plug.Upload{
          path: path,
          filename: "review-e2e-packet.pdf",
          content_type: "application/pdf"
        },
        finding_id: finding.id,
        document_role: :solicitation,
        notes: "Required procurement promotion evidence."
      },
      actor: actor
    )
  end

  defp actor_fixture do
    suffix = System.unique_integer([:positive])

    Accounts.create_user_with_password!(%{
      email: "review-e2e-#{suffix}@example.com",
      password: "review-e2e-password-#{suffix}",
      password_confirmation: "review-e2e-password-#{suffix}"
    })
  end
end
