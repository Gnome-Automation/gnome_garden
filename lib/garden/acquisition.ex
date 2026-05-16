defmodule GnomeGarden.Acquisition do
  @moduledoc """
  Unified intake layer for agent-discovered work.

  This domain sits between the agent execution plane and downstream commercial
  workflow. Procurement bids, discovery records, and future target-discovery
  agents should all converge on durable acquisition findings before they become
  commercial signals or pursuits.
  """

  use Ash.Domain,
    otp_app: :gnome_garden,
    extensions: [AshAdmin.Domain]

  alias GnomeGarden.Acquisition.{Projector, Review, Runner}

  admin do
    show? true
  end

  resources do
    resource GnomeGarden.Acquisition.DocumentBlob
    resource GnomeGarden.Acquisition.DocumentAttachment

    resource GnomeGarden.Acquisition.Document do
      define :list_documents, action: :read
      define :get_document, action: :read, get_by: [:id]
      define :create_document, action: :create
      define :upload_document_for_finding, action: :upload_for_finding
      define :update_document, action: :update
    end

    resource GnomeGarden.Acquisition.FindingDocument do
      define :list_finding_documents, action: :read
      define :list_finding_documents_for_finding, action: :for_finding, args: [:finding_id]
      define :get_finding_document, action: :read, get_by: [:id]
      define :link_document_to_finding, action: :link_existing
      define :update_finding_document, action: :update
      define :delete_finding_document, action: :destroy
    end

    resource GnomeGarden.Acquisition.Source do
      define :list_sources, action: :read
      define :list_console_sources, action: :console
      define :get_source, action: :read, get_by: [:id]
      define :get_source_by_external_ref, action: :by_external_ref, args: [:external_ref]
      define :get_source_by_url, action: :by_url, args: [:url]
      define :create_source, action: :create
      define :update_source, action: :update
    end

    resource GnomeGarden.Acquisition.Program do
      define :list_programs, action: :read
      define :list_console_programs, action: :console
      define :get_program, action: :read, get_by: [:id]
      define :get_program_by_external_ref, action: :by_external_ref, args: [:external_ref]

      define :get_program_by_discovery_program,
        action: :by_discovery_program,
        args: [:discovery_program_id]

      define :create_program, action: :create
      define :update_program, action: :update
    end

    resource GnomeGarden.Acquisition.Finding do
      define :list_findings, action: :read
      define :list_findings_for_program, action: :for_program, args: [:program_id]

      define :list_findings_queue,
        action: :queue,
        args: [:queue, :family, :source_id, :program_id, :agent_run_id]

      define :list_review_findings, action: :review_queue
      define :list_promoted_findings, action: :promoted
      define :list_rejected_findings, action: :rejected
      define :list_suppressed_findings, action: :suppressed
      define :list_parked_findings, action: :parked
      define :get_finding, action: :read, get_by: [:id]
      define :get_finding_by_external_ref, action: :by_external_ref, args: [:external_ref]
      define :get_finding_by_source_bid, action: :by_source_bid, args: [:source_bid_id]

      define :get_finding_by_source_discovery_record,
        action: :by_source_discovery_record,
        args: [:source_discovery_record_id]

      define :get_finding_by_signal, action: :by_signal, args: [:signal_id]

      define :create_finding, action: :create
      define :update_finding, action: :update
    end

    resource GnomeGarden.Acquisition.FindingReviewDecision do
      define :list_finding_review_decisions, action: :read

      define :list_finding_review_decisions_for_finding,
        action: :for_finding,
        args: [:finding_id]

      define :record_finding_review_decision, action: :record
      define :get_finding_review_decision, action: :read, get_by: [:id]
    end

    resource GnomeGarden.Acquisition.ResearchRequest do
      define :list_research_requests, action: :read
      define :create_research_request, action: :create
    end

    resource GnomeGarden.Acquisition.ResearchLink do
      define :list_research_links, action: :read
      define :create_research_link, action: :create
    end
  end

  def sync_bid_finding(bid_or_id, opts \\ []), do: Projector.sync_bid(bid_or_id, opts)

  def sync_discovery_record_finding(discovery_record_or_id, opts \\ []),
    do: Projector.sync_discovery_record(discovery_record_or_id, opts)

  def sync_source(source_or_id, opts \\ []), do: Projector.sync_source(source_or_id, opts)

  def sync_program(program_or_id, opts \\ []), do: Projector.sync_program(program_or_id, opts)

  def backfill_intake(opts \\ []), do: Projector.backfill(opts)

  def launch_source_run(source_or_id, opts \\ []), do: Runner.launch_source(source_or_id, opts)

  def launch_program_run(program_or_id, opts \\ []),
    do: Runner.launch_program(program_or_id, opts)

  def start_review_for_finding(finding_or_id, opts \\ []),
    do: Review.start_review(finding_or_id, opts)

  def accept_finding_review(finding_or_id, opts) when is_list(opts),
    do: Review.accept(finding_or_id, %{}, opts)

  def accept_finding_review(finding_or_id, feedback \\ %{}, opts \\ []),
    do: Review.accept(finding_or_id, feedback, opts)

  def reject_finding_review(finding_or_id, feedback \\ %{}, opts \\ []),
    do: Review.reject(finding_or_id, feedback, opts)

  def suppress_finding_review(finding_or_id, feedback \\ %{}, opts \\ []),
    do: Review.suppress(finding_or_id, feedback, opts)

  def park_finding_review(finding_or_id, feedback \\ %{}, opts \\ []),
    do: Review.park(finding_or_id, feedback, opts)

  def reopen_finding_review(finding_or_id, opts \\ []), do: Review.reopen(finding_or_id, opts)

  def promote_finding_to_signal(finding_or_id, opts \\ []),
    do: Review.promote_to_signal(finding_or_id, opts)
end
