defmodule GnomeGarden.Company do
  @moduledoc """
  Gnome-owned company facts, documents, tax identifiers, and payment details.

  This domain owns reusable facts and files about Gnome Automation LLC. Customer
  specific onboarding requirements, pursuit state, and packet deliveries stay in
  the Commercial domain and reference these records when needed.
  """

  use Ash.Domain,
    otp_app: :gnome_garden,
    extensions: [AshAdmin.Domain]

  admin do
    show? true
  end

  resources do
    resource GnomeGarden.Company.Profile do
      define :list_company_profiles, action: :read
      define :get_company_profile, action: :read, get_by: [:id]
      define :get_company_profile_by_key, action: :by_key, args: [:key]
      define :get_primary_company_profile, action: :primary
      define :create_company_profile, action: :create
      define :update_company_profile, action: :update
      define :import_vendor_onboarding, action: :import_vendor_onboarding, args: [:payload]
      define :delete_company_profile, action: :destroy
    end

    resource GnomeGarden.Company.Document do
      define :list_company_documents, action: :read
      define :list_active_company_documents, action: :active
      define :list_company_documents_by_kind, action: :by_kind, args: [:kind]

      define :list_company_documents_for_profile,
        action: :for_company_profile,
        args: [:company_profile_id]

      define :get_company_document, action: :read, get_by: [:id]
      define :get_company_document_by_key, action: :by_key, args: [:company_profile_id, :key]
      define :create_company_document, action: :create
      define :update_company_document, action: :update
      define :activate_company_document, action: :activate
      define :retire_company_document, action: :retire
      define :archive_company_document, action: :archive
      define :delete_company_document, action: :destroy
    end

    resource GnomeGarden.Company.DocumentBlob
    resource GnomeGarden.Company.DocumentAttachment

    resource GnomeGarden.Company.TaxIdentifier do
      define :list_company_tax_identifiers, action: :read
      define :list_active_company_tax_identifiers, action: :active

      define :list_company_tax_identifiers_for_profile,
        action: :for_company_profile,
        args: [:company_profile_id]

      define :get_company_tax_identifier, action: :read, get_by: [:id]

      define :get_company_tax_identifier_by_type,
        action: :by_type,
        args: [:company_profile_id, :identifier_type, :jurisdiction]

      define :create_company_tax_identifier, action: :create
      define :update_company_tax_identifier, action: :update
      define :rotate_company_tax_identifier_value, action: :rotate_value
      define :delete_company_tax_identifier, action: :destroy
    end

    resource GnomeGarden.Company.PaymentDestination do
      define :list_payment_destinations, action: :read
      define :list_active_payment_destinations, action: :active
      define :get_payment_destination, action: :read, get_by: [:id]
      define :get_payment_destination_by_key, action: :by_key, args: [:key]
      define :create_payment_destination, action: :create
      define :update_payment_destination, action: :update
      define :rotate_payment_destination_account_number, action: :rotate_account_number
      define :delete_payment_destination, action: :destroy
    end

    resource GnomeGarden.Company.ComplianceObligation do
      define :list_company_compliance_obligations, action: :read
      define :list_active_company_compliance_obligations, action: :active

      define :list_company_compliance_obligations_for_profile,
        action: :for_company_profile,
        args: [:company_profile_id]

      define :get_company_compliance_obligation, action: :read, get_by: [:id]

      define :get_company_compliance_obligation_by_key,
        action: :by_key,
        args: [:company_profile_id, :key]

      define :create_company_compliance_obligation, action: :create
      define :update_company_compliance_obligation, action: :update
      define :complete_company_compliance_obligation, action: :mark_complete
      define :review_company_compliance_obligation, action: :mark_needs_review
      define :delete_company_compliance_obligation, action: :destroy
    end

    resource GnomeGarden.Company.GrowthInitiative do
      define :list_growth_initiatives, action: :read
      define :list_growth_initiative_workspace, action: :workspace

      define :list_growth_initiatives_for_profile,
        action: :for_profile,
        args: [:company_profile_id]

      define :get_growth_initiative, action: :read, get_by: [:id]
      define :create_growth_initiative, action: :create
      define :update_growth_initiative, action: :update
      define :evaluate_growth_initiative, action: :evaluate
      define :plan_growth_initiative, action: :plan
      define :start_growth_initiative, action: :start
      define :hold_growth_initiative, action: :hold
      define :resume_growth_initiative, action: :resume
      define :achieve_growth_initiative, action: :achieve
      define :decline_growth_initiative, action: :decline
      define :reconsider_growth_initiative, action: :reconsider
      define :delete_growth_initiative_idea, action: :destroy_idea
    end

    resource GnomeGarden.Company.GrowthInitiativeEvidence do
      define :create_growth_initiative_evidence, action: :create
      define :delete_growth_initiative_evidence, action: :destroy

      define :list_growth_initiative_evidence,
        action: :for_initiative,
        args: [:growth_initiative_id]
    end

    resource GnomeGarden.Company.Qualification do
      define :list_company_qualifications, action: :read
      define :list_company_qualification_registry, action: :registry
      define :list_active_company_qualifications, action: :active

      define :list_company_qualifications_expiring_within,
        action: :expiring_within,
        args: [:days]

      define :get_company_qualification, action: :read, get_by: [:id]
      define :create_company_qualification, action: :create
      define :update_company_qualification, action: :update
      define :activate_company_qualification, action: :activate
      define :suspend_company_qualification, action: :suspend
      define :expire_company_qualification, action: :expire
      define :retire_company_qualification, action: :retire
    end

    resource GnomeGarden.Company.SourceReviewItem do
      define :list_company_source_review_items, action: :read

      define :list_company_source_review_items_for_profile,
        action: :for_company_profile,
        args: [:company_profile_id]

      define :list_company_source_review_items_by_status, action: :by_status, args: [:status]
      define :get_company_source_review_item, action: :read, get_by: [:id]

      define :get_company_source_review_item_by_key,
        action: :by_key,
        args: [:company_profile_id, :key]

      define :create_company_source_review_item, action: :create
      define :update_company_source_review_item, action: :update
      define :apply_company_source_review_item, action: :mark_applied
      define :ignore_company_source_review_item, action: :ignore
      define :review_company_source_review_item, action: :mark_needs_review
      define :delete_company_source_review_item, action: :destroy
    end
  end

  defdelegate scan_growth_gaps(opts \\ []),
    to: GnomeGarden.Company.GrowthRecommendations,
    as: :scan_and_propose

  defdelegate approve_growth_recommendation(recommendation, opts \\ []),
    to: GnomeGarden.Company.GrowthRecommendations,
    as: :approve_into_initiative

  defdelegate assess_bid_eligibility(bid, qualifications \\ nil),
    to: GnomeGarden.Company.Eligibility,
    as: :assess
end
