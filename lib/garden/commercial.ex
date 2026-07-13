defmodule GnomeGarden.Commercial do
  @moduledoc """
  Commercial operating model domain.

  Owns the business-development and agreement layer between market signals and
  downstream delivery or service execution.
  """

  use Ash.Domain,
    otp_app: :gnome_garden,
    extensions: [AshAdmin.Domain]

  admin do
    show? true
  end

  resources do
    resource GnomeGarden.Commercial.CustomerVendorOnboarding do
      define :list_customer_vendor_onboardings, action: :read
      define :list_active_customer_vendor_onboardings, action: :active
      define :get_customer_vendor_onboarding, action: :read, get_by: [:id]

      define :get_customer_vendor_onboarding_by_key,
        action: :by_key,
        args: [:company_profile_id, :key]

      define :create_customer_vendor_onboarding, action: :create
      define :update_customer_vendor_onboarding, action: :update
      define :activate_customer_vendor_onboarding, action: :activate
      define :complete_customer_vendor_onboarding, action: :complete
      define :archive_customer_vendor_onboarding, action: :archive
      define :delete_customer_vendor_onboarding, action: :destroy
    end

    resource GnomeGarden.Commercial.CustomerVendorRequirement do
      define :list_customer_vendor_requirements, action: :read

      define :list_customer_vendor_requirements_for_onboarding,
        action: :for_onboarding,
        args: [:customer_vendor_onboarding_id]

      define :get_customer_vendor_requirement, action: :read, get_by: [:id]

      define :get_customer_vendor_requirement_by_key,
        action: :by_key,
        args: [:customer_vendor_onboarding_id, :key]

      define :create_customer_vendor_requirement, action: :create
      define :update_customer_vendor_requirement, action: :update
      define :ready_customer_vendor_requirement, action: :mark_ready
      define :send_customer_vendor_requirement, action: :mark_sent
      define :accept_customer_vendor_requirement, action: :accept
      define :reject_customer_vendor_requirement, action: :reject
      define :waive_customer_vendor_requirement, action: :waive
      define :delete_customer_vendor_requirement, action: :destroy
    end

    resource GnomeGarden.Commercial.CustomerVendorRequirementDelivery do
      define :list_customer_vendor_requirement_deliveries, action: :read

      define :list_customer_vendor_requirement_deliveries_for_requirement,
        action: :for_requirement,
        args: [:customer_vendor_requirement_id]

      define :create_customer_vendor_requirement_delivery, action: :create
      define :delete_customer_vendor_requirement_delivery, action: :destroy
    end

    resource GnomeGarden.Commercial.CustomerVendorRequirementArtifact do
      define :list_customer_vendor_requirement_artifacts, action: :read

      define :list_customer_vendor_requirement_artifacts_for_requirement,
        action: :for_requirement,
        args: [:customer_vendor_requirement_id]

      define :get_customer_vendor_requirement_artifact, action: :read, get_by: [:id]
      define :create_customer_vendor_requirement_artifact, action: :create
      define :update_customer_vendor_requirement_artifact, action: :update
      define :extract_customer_vendor_requirement_artifact, action: :mark_extracted
      define :draft_customer_vendor_requirement_artifact, action: :mark_drafted
      define :sign_customer_vendor_requirement_artifact, action: :mark_signed
      define :approve_customer_vendor_requirement_artifact, action: :approve
      define :reject_customer_vendor_requirement_artifact, action: :reject
      define :send_customer_vendor_requirement_artifact, action: :mark_sent

      define :populate_customer_vendor_requirement_artifact,
        action: :populate_source_form,
        args: [:artifact_id]

      define :delete_customer_vendor_requirement_artifact, action: :destroy
    end

    resource GnomeGarden.Commercial.CustomerVendorRequirementArtifactBlob
    resource GnomeGarden.Commercial.CustomerVendorRequirementArtifactAttachment

    resource GnomeGarden.Commercial.DiscoveryProgram do
      define :list_discovery_programs, action: :read
      define :list_active_discovery_programs, action: :active
      define :list_due_discovery_programs, action: :due_for_run
      define :get_discovery_program, action: :read, get_by: [:id]
      define :create_discovery_program, action: :create
      define :update_discovery_program, action: :update
      define :activate_discovery_program, action: :activate
      define :pause_discovery_program, action: :pause
      define :archive_discovery_program, action: :archive
      define :reopen_discovery_program, action: :reopen
      define :mark_discovery_program_ran, action: :mark_ran

      define :list_discovery_programs_for_owner,
        action: :for_owner,
        args: [:owner_team_member_id]
    end

    resource GnomeGarden.Commercial.DiscoveryRun do
      define :list_discovery_runs, action: :read
      define :list_discovery_runs_for_slo, action: :slo_window, args: [:updated_since]
      define :get_discovery_run, action: :read, get_by: [:id]
      define :get_discovery_run_by_key, action: :by_idempotency_key, args: [:idempotency_key]

      define :get_active_discovery_run_for_program,
        action: :active_for_program,
        args: [:discovery_program_id]

      define :get_latest_discovery_run_for_program,
        action: :latest_for_program,
        args: [:discovery_program_id]

      define :create_discovery_run, action: :create
      define :start_discovery_run, action: :start
      define :retry_discovery_run, action: :retry
      define :recover_discovery_run, action: :recover
      define :complete_discovery_run, action: :complete
      define :partially_complete_discovery_run, action: :partial_failure
      define :fail_discovery_run, action: :fail
    end

    resource GnomeGarden.Commercial.DiscoveryRecord do
      define :list_discovery_records, action: :read
      define :get_discovery_record, action: :read, get_by: [:id]

      define :get_discovery_record_by_website_domain,
        action: :by_website_domain,
        args: [:website_domain]

      define :search_discovery_records, action: :search, args: [:query]
      define :create_discovery_record, action: :create
      define :create_prospect_discovery_record, action: :create_prospect
      define :create_opportunity_discovery_record, action: :create_opportunity
      define :update_discovery_record, action: :update
      define :resolve_discovery_record_identity, action: :resolve_identity
      define :review_discovery_record, action: :start_review
      define :promote_discovery_record_to_signal, action: :promote_to_signal
      define :reject_discovery_record, action: :reject
      define :archive_discovery_record, action: :archive
      define :reopen_discovery_record, action: :reopen

      define :list_discovery_records_for_organization,
        action: :for_organization,
        args: [:organization_id]

      define :list_discovery_records_for_contact_person,
        action: :for_contact_person,
        args: [:contact_person_id]

      define :list_discovery_records_for_program,
        action: :for_discovery_program,
        args: [:discovery_program_id]
    end

    resource GnomeGarden.Commercial.DiscoveryEvidence do
      define :list_discovery_evidence, action: :read
      define :get_discovery_evidence, action: :read, get_by: [:id]

      define :get_discovery_evidence_by_external_ref,
        action: :by_external_ref,
        args: [:external_ref]

      define :create_discovery_evidence, action: :create
      define :update_discovery_evidence, action: :update
      define :list_recent_discovery_evidence, action: :recent

      define :list_discovery_evidence_for_discovery_record,
        action: :for_discovery_record,
        args: [:discovery_record_id]

      define :list_discovery_evidence_for_program,
        action: :for_discovery_program,
        args: [:discovery_program_id]
    end

    resource GnomeGarden.Commercial.Activity do
      define :list_activities, action: :read
      define :get_activity, action: :read, get_by: [:id]
      define :create_activity, action: :create
      define :update_activity, action: :update
      define :list_recent_activities, action: :recent
      define :list_activities_by_organization, action: :by_organization, args: [:organization_id]
      define :list_activities_by_person, action: :by_person, args: [:person_id]
      define :list_activities_by_pursuit, action: :by_pursuit, args: [:pursuit_id]
      define :list_activities_by_type, action: :by_type, args: [:activity_type]
    end

    resource GnomeGarden.Commercial.Event do
      define :log_event, action: :log
    end

    resource GnomeGarden.Commercial.Signal do
      define :list_signals, action: :read
      define :get_signal, action: :read, get_by: [:id]
      define :get_signal_by_external_ref, action: :by_external_ref, args: [:external_ref]
      define :create_signal, action: :create
      define :update_signal, action: :update
      define :list_signals_for_organization, action: :for_organization, args: [:organization_id]
      define :create_signal_from_bid, action: :create_from_bid, args: [:source_bid_id]
      define :review_signal, action: :start_review
      define :accept_signal, action: :accept
      define :reject_signal, action: :reject
      define :convert_signal, action: :convert
      define :archive_signal, action: :archive
      define :reopen_signal, action: :reopen
      define :list_signal_queue, action: :review_queue
    end

    resource GnomeGarden.Commercial.Pursuit do
      define :list_pursuits, action: :read
      define :get_pursuit, action: :read, get_by: [:id]
      define :get_pursuit_workspace, action: :workspace, args: [:id]
      define :create_pursuit, action: :create
      define :create_pursuit_from_signal, action: :create_from_signal, args: [:source_signal_id]
      define :update_pursuit, action: :update
      define :qualify_pursuit, action: :qualify
      define :estimate_pursuit, action: :estimate
      define :propose_pursuit, action: :propose
      define :negotiate_pursuit, action: :negotiate
      define :win_pursuit, action: :mark_won
      define :lose_pursuit, action: :mark_lost
      define :archive_pursuit, action: :archive
      define :reopen_pursuit, action: :reopen
      define :list_active_pursuits, action: :active
      define :list_pursuits_for_organization, action: :for_organization, args: [:organization_id]
    end

    resource GnomeGarden.Commercial.Proposal do
      define :list_proposals, action: :read
      define :get_proposal, action: :read, get_by: [:id]
      define :create_proposal, action: :create
      define :update_proposal, action: :update
      define :issue_proposal, action: :issue
      define :accept_proposal, action: :accept
      define :reject_proposal, action: :reject
      define :expire_proposal, action: :expire
      define :supersede_proposal, action: :supersede
      define :reopen_proposal, action: :reopen
      define :list_active_proposals, action: :active
      define :list_proposals_for_pursuit, action: :for_pursuit
    end

    resource GnomeGarden.Commercial.ProposalLine do
      define :list_proposal_lines, action: :read
      define :get_proposal_line, action: :read, get_by: [:id]
      define :create_proposal_line, action: :create
      define :update_proposal_line, action: :update
      define :list_lines_for_proposal, action: :for_proposal
    end

    resource GnomeGarden.Commercial.Agreement do
      define :list_agreements, action: :read
      define :get_agreement, action: :read, get_by: [:id]
      define :create_agreement, action: :create
      define :create_agreement_from_proposal, action: :create_from_proposal
      define :update_agreement, action: :update
      define :submit_agreement, action: :submit_for_signature
      define :activate_agreement, action: :activate
      define :suspend_agreement, action: :suspend
      define :complete_agreement, action: :complete
      define :terminate_agreement, action: :terminate
      define :reopen_agreement, action: :reopen
      define :list_active_agreements, action: :active
      define :list_expiring_agreements, action: :expiring_soon
    end

    resource GnomeGarden.Commercial.ChangeOrder do
      define :list_change_orders, action: :read
      define :get_change_order, action: :read, get_by: [:id]
      define :create_change_order, action: :create
      define :update_change_order, action: :update
      define :submit_change_order, action: :submit
      define :approve_change_order, action: :approve
      define :reject_change_order, action: :reject
      define :implement_change_order, action: :implement
      define :cancel_change_order, action: :cancel
      define :reopen_change_order, action: :reopen
      define :list_active_change_orders, action: :active
      define :list_change_orders_for_agreement, action: :for_agreement
    end

    resource GnomeGarden.Commercial.ChangeOrderLine do
      define :list_change_order_lines, action: :read
      define :get_change_order_line, action: :read, get_by: [:id]
      define :create_change_order_line, action: :create
      define :update_change_order_line, action: :update
      define :list_lines_for_change_order, action: :for_change_order
    end

    resource GnomeGarden.Commercial.ServiceLevelPolicy do
      define :list_service_level_policies, action: :read
      define :get_service_level_policy, action: :read, get_by: [:id]
      define :create_service_level_policy, action: :create
      define :update_service_level_policy, action: :update
      define :activate_service_level_policy, action: :activate
      define :retire_service_level_policy, action: :retire
      define :reopen_service_level_policy, action: :reopen
      define :list_active_service_level_policies, action: :active
      define :list_policies_for_agreement, action: :for_agreement
    end

    resource GnomeGarden.Commercial.ServiceEntitlement do
      define :list_service_entitlements, action: :read
      define :get_service_entitlement, action: :read, get_by: [:id]
      define :create_service_entitlement, action: :create
      define :update_service_entitlement, action: :update
      define :activate_service_entitlement, action: :activate
      define :retire_service_entitlement, action: :retire
      define :reopen_service_entitlement, action: :reopen
      define :list_active_service_entitlements, action: :active
      define :list_entitlements_for_agreement, action: :for_agreement
      define :list_available_service_entitlements_for_usage, action: :available_for_usage
    end

    resource GnomeGarden.Commercial.ServiceEntitlementUsage do
      define :list_service_entitlement_usages, action: :read
      define :get_service_entitlement_usage, action: :read, get_by: [:id]
      define :create_service_entitlement_usage, action: :create
      define :update_service_entitlement_usage, action: :update
      define :delete_service_entitlement_usage, action: :destroy

      define :list_usage_for_entitlement,
        action: :for_entitlement,
        args: [:service_entitlement_id]

      define :list_usage_for_agreement, action: :for_agreement, args: [:agreement_id]
      define :list_usage_for_time_entry, action: :for_time_entry, args: [:time_entry_id]
      define :list_usage_for_expense, action: :for_expense, args: [:expense_id]
      define :list_usage_for_work_order, action: :for_work_order, args: [:work_order_id]
    end
  end

  def create_referral_lead(attrs, opts \\ []) do
    GnomeGarden.Commercial.LeadIntake.create_referral_lead(attrs, opts)
  end

  def launch_discovery_program(program_or_id, opts \\ []) do
    GnomeGarden.Commercial.DiscoveryRunner.launch_program(program_or_id, opts)
  end

  def discovery_record_review_context(discovery_record_or_id, opts \\ []) do
    actor = Keyword.get(opts, :actor)

    with {:ok, discovery_record} <-
           load_discovery_record_for_review_context(discovery_record_or_id, actor) do
      GnomeGarden.Commercial.DiscoveryIdentityResolver.discovery_record_review_context(
        discovery_record,
        actor: actor
      )
    end
  end

  defp load_discovery_record_for_review_context(
         %GnomeGarden.Commercial.DiscoveryRecord{id: id},
         actor
       ),
       do: load_discovery_record_for_review_context(id, actor)

  defp load_discovery_record_for_review_context(discovery_record_id, actor)
       when is_binary(discovery_record_id) do
    get_discovery_record(
      discovery_record_id,
      actor: actor,
      load: [:organization, :contact_person]
    )
  end
end
