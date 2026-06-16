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
end
