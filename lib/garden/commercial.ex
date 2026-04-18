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
    resource GnomeGarden.Commercial.Signal do
      define :list_signals, action: :read
      define :get_signal, action: :read, get_by: [:id]
      define :create_signal, action: :create
      define :update_signal, action: :update
      define :review_signal, action: :start_review
      define :accept_signal, action: :accept
      define :reject_signal, action: :reject
      define :convert_signal, action: :convert
      define :archive_signal, action: :archive
      define :reopen_signal, action: :reopen
      define :list_open_signals, action: :open
    end

    resource GnomeGarden.Commercial.Pursuit do
      define :list_pursuits, action: :read
      define :get_pursuit, action: :read, get_by: [:id]
      define :create_pursuit, action: :create
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
      define :list_pursuits_for_organization, action: :for_organization
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
    end

    resource GnomeGarden.Commercial.ServiceEntitlementUsage do
      define :list_service_entitlement_usages, action: :read
      define :get_service_entitlement_usage, action: :read, get_by: [:id]
      define :create_service_entitlement_usage, action: :create
      define :update_service_entitlement_usage, action: :update
      define :list_usage_for_entitlement, action: :for_entitlement
      define :list_usage_for_agreement, action: :for_agreement
    end
  end
end
