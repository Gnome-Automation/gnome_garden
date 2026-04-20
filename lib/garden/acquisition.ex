defmodule GnomeGarden.Acquisition do
  @moduledoc """
  Unified intake layer for agent-discovered work.

  This domain sits between the agent execution plane and downstream commercial
  workflow. Procurement bids, discovery records, and future lead-finding agents
  should all converge on durable acquisition findings before they become
  commercial signals or pursuits.
  """

  use Ash.Domain,
    otp_app: :gnome_garden,
    extensions: [AshAdmin.Domain]

  alias GnomeGarden.Acquisition.{Projector, Review}
  alias GnomeGarden.Commercial

  admin do
    show? true
  end

  resources do
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

      define :get_program_by_legacy_discovery_program,
        action: :by_legacy_discovery_program,
        args: [:legacy_discovery_program_id]

      define :create_program, action: :create
      define :update_program, action: :update
    end

    resource GnomeGarden.Acquisition.Finding do
      define :list_findings, action: :read
      define :list_findings_for_program, action: :for_program, args: [:program_id]
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
      define :review_finding, action: :start_review
      define :accept_finding, action: :accept
      define :reject_finding, action: :reject
      define :suppress_finding, action: :suppress
      define :park_finding, action: :park
      define :reopen_finding, action: :reopen
      define :promote_finding, action: :promote
    end
  end

  def sync_bid_finding(bid_or_id, opts \\ []), do: Projector.sync_bid(bid_or_id, opts)

  def sync_discovery_record_finding(discovery_record_or_id, opts \\ []),
    do: Projector.sync_discovery_record(discovery_record_or_id, opts)

  def sync_source(source_or_id, opts \\ []), do: Projector.sync_source(source_or_id, opts)

  def sync_program(program_or_id, opts \\ []), do: Projector.sync_program(program_or_id, opts)

  def backfill_intake(opts \\ []), do: Projector.backfill(opts)

  def get_discovery_record(discovery_record_id, opts \\ []),
    do: Commercial.get_discovery_record(discovery_record_id, opts)

  def get_discovery_record_by_website_domain(website_domain, opts \\ []),
    do: Commercial.get_discovery_record_by_website_domain(website_domain, opts)

  def create_discovery_record(attrs, opts \\ []),
    do: Commercial.create_discovery_record(attrs, opts)

  def update_discovery_record(discovery_record_or_id, attrs, opts \\ [])

  def update_discovery_record(%Commercial.DiscoveryRecord{} = discovery_record, attrs, opts),
    do: Commercial.update_discovery_record(discovery_record, attrs, opts)

  def update_discovery_record(discovery_record_id, attrs, opts)
      when is_binary(discovery_record_id) do
    with {:ok, discovery_record} <- get_discovery_record(discovery_record_id, opts) do
      Commercial.update_discovery_record(discovery_record, attrs, opts)
    end
  end

  def get_discovery_evidence(evidence_id, opts \\ []),
    do: Commercial.get_discovery_evidence(evidence_id, opts)

  def get_discovery_evidence_by_external_ref(external_ref, opts \\ []),
    do: Commercial.get_discovery_evidence_by_external_ref(external_ref, opts)

  def create_discovery_evidence(attrs, opts \\ []),
    do: Commercial.create_discovery_evidence(attrs, opts)

  def update_discovery_evidence(discovery_evidence_or_id, attrs, opts \\ [])

  def update_discovery_evidence(
        %Commercial.DiscoveryEvidence{} = discovery_evidence,
        attrs,
        opts
      ),
      do: Commercial.update_discovery_evidence(discovery_evidence, attrs, opts)

  def update_discovery_evidence(discovery_evidence_id, attrs, opts)
      when is_binary(discovery_evidence_id) do
    with {:ok, discovery_evidence} <- get_discovery_evidence(discovery_evidence_id, opts) do
      Commercial.update_discovery_evidence(discovery_evidence, attrs, opts)
    end
  end

  def list_recent_discovery_evidence(opts \\ []),
    do: Commercial.list_recent_discovery_evidence(opts)

  def list_discovery_evidence_for_discovery_record(discovery_record_id, opts \\ []),
    do: Commercial.list_discovery_evidence_for_discovery_record(discovery_record_id, opts)

  def list_discovery_evidence_for_program(discovery_program_id, opts \\ []),
    do: Commercial.list_discovery_evidence_for_program(discovery_program_id, opts)

  def list_discovery_records(opts \\ []), do: Commercial.list_discovery_records(opts)

  def list_review_discovery_records(opts \\ []),
    do: Commercial.list_review_discovery_records(opts)

  def list_promoted_discovery_records(opts \\ []),
    do: Commercial.list_promoted_discovery_records(opts)

  def list_rejected_discovery_records(opts \\ []),
    do: Commercial.list_rejected_discovery_records(opts)

  def list_archived_discovery_records(opts \\ []),
    do: Commercial.list_archived_discovery_records(opts)

  def list_discovery_records_for_organization(organization_id, opts \\ []),
    do: Commercial.list_discovery_records_for_organization(organization_id, opts)

  def list_discovery_records_for_contact_person(person_id, opts \\ []),
    do: Commercial.list_discovery_records_for_contact_person(person_id, opts)

  def list_discovery_records_for_program(discovery_program_id, opts \\ []),
    do: Commercial.list_discovery_records_for_program(discovery_program_id, opts)

  def list_legacy_discovery_programs(opts \\ []), do: Commercial.list_discovery_programs(opts)

  def get_discovery_identity_review(discovery_record, opts \\ []),
    do: Commercial.discovery_record_review_context(discovery_record, opts)

  def resolve_discovery_record_identity(discovery_record, attrs, opts \\ []),
    do: Commercial.resolve_discovery_record_identity(discovery_record, attrs, opts)

  def start_review_for_discovery_record(discovery_record_or_id, opts \\ [])

  def start_review_for_discovery_record(%Commercial.DiscoveryRecord{} = discovery_record, opts),
    do: Commercial.review_discovery_record(discovery_record, opts)

  def start_review_for_discovery_record(discovery_record_id, opts)
      when is_binary(discovery_record_id) do
    with {:ok, discovery_record} <- get_discovery_record(discovery_record_id, opts) do
      Commercial.review_discovery_record(discovery_record, opts)
    end
  end

  def promote_discovery_record_to_signal(discovery_record_or_id, opts \\ [])

  def promote_discovery_record_to_signal(%Commercial.DiscoveryRecord{} = discovery_record, opts),
    do: Commercial.promote_discovery_record_to_signal(discovery_record, opts)

  def promote_discovery_record_to_signal(discovery_record_id, opts)
      when is_binary(discovery_record_id) do
    with {:ok, discovery_record} <- get_discovery_record(discovery_record_id, opts) do
      Commercial.promote_discovery_record_to_signal(discovery_record, opts)
    end
  end

  def reject_discovery_record(discovery_record_or_id, attrs, opts \\ [])

  def reject_discovery_record(%Commercial.DiscoveryRecord{} = discovery_record, attrs, opts),
    do: Commercial.reject_discovery_record(discovery_record, attrs, opts)

  def reject_discovery_record(discovery_record_id, attrs, opts)
      when is_binary(discovery_record_id) do
    with {:ok, discovery_record} <- get_discovery_record(discovery_record_id, opts) do
      Commercial.reject_discovery_record(discovery_record, attrs, opts)
    end
  end

  def reopen_discovery_record(discovery_record_or_id, opts \\ [])

  def reopen_discovery_record(%Commercial.DiscoveryRecord{} = discovery_record, opts),
    do: Commercial.reopen_discovery_record(discovery_record, opts)

  def reopen_discovery_record(discovery_record_id, opts)
      when is_binary(discovery_record_id) do
    with {:ok, discovery_record} <- get_discovery_record(discovery_record_id, opts) do
      Commercial.reopen_discovery_record(discovery_record, opts)
    end
  end

  def start_review_for_finding(finding_or_id, opts \\ []),
    do: Review.start_review(finding_or_id, opts)

  def accept_finding_review(finding_or_id, opts \\ []), do: Review.accept(finding_or_id, opts)

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
