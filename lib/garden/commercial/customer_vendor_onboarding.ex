defmodule GnomeGarden.Commercial.CustomerVendorOnboarding do
  @moduledoc """
  Customer-specific vendor onboarding case for getting Gnome approved as a supplier.

  This owns customer-specific packet rules: where to send the completed packet,
  which terms they requested, invoice instructions, status, and the requirement
  checklist. Reusable Gnome documents stay on `CompanyDocument`.
  """

  use Ash.Resource,
    otp_app: :gnome_garden,
    domain: GnomeGarden.Commercial,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshAdmin.Resource],
    notifiers: [Ash.Notifier.PubSub]

  admin do
    table_columns [:customer_name, :status, :return_email, :payment_terms, :updated_at]
  end

  postgres do
    table "commercial_vendor_onboardings"
    repo GnomeGarden.Repo

    custom_indexes do
      index [:status, :updated_at], name: "vendor_onboardings_status_idx"
    end

    identity_index_names unique_company_customer_vendor_onboarding:
                           "customer_vendor_onboardings_profile_key_idx"

    references do
      reference :company_profile,
        on_delete: :delete,
        name: "vendor_onboardings_company_profile_fkey"

      reference :customer_organization,
        on_delete: :nilify,
        name: "vendor_onboardings_customer_org_fkey"
    end
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true

      accept [
        :company_profile_id,
        :customer_organization_id,
        :key,
        :customer_name,
        :status,
        :return_email,
        :invoice_email,
        :payment_terms,
        :delivery_terms,
        :currency,
        :instructions,
        :terms_url,
        :supplier_code_url,
        :metadata
      ]
    end

    update :update do
      accept [
        :customer_organization_id,
        :customer_name,
        :status,
        :return_email,
        :invoice_email,
        :payment_terms,
        :delivery_terms,
        :currency,
        :instructions,
        :terms_url,
        :supplier_code_url,
        :metadata
      ]
    end

    update :activate do
      accept []
      change set_attribute(:status, :active)
    end

    update :complete do
      accept []
      change set_attribute(:status, :complete)
    end

    update :archive do
      accept []
      change set_attribute(:status, :archived)
    end

    read :active do
      filter expr(status in [:draft, :active, :sent, :rejected])

      prepare build(
                sort: [updated_at: :desc],
                load: [requirements: [:company_document]]
              )
    end

    read :by_key do
      argument :company_profile_id, :uuid, allow_nil?: false
      argument :key, :string, allow_nil?: false
      get? true
      filter expr(company_profile_id == ^arg(:company_profile_id) and key == ^arg(:key))

      prepare build(
                load: [requirements: [:company_document, :deliveries], customer_organization: []]
              )
    end
  end

  pub_sub do
    module GnomeGardenWeb.Endpoint
    prefix "customer_vendor_onboarding"

    publish :create, "created"
    publish :update, "updated"
    publish :activate, "updated"
    publish :complete, "updated"
    publish :archive, "updated"
    publish :destroy, "destroyed"
  end

  attributes do
    uuid_primary_key :id

    attribute :key, :string do
      allow_nil? false
      public? true
    end

    attribute :customer_name, :string do
      allow_nil? false
      public? true
    end

    attribute :status, :atom do
      allow_nil? false
      default :active
      public? true

      constraints one_of: [:draft, :active, :ready, :sent, :rejected, :complete, :archived]
    end

    attribute :return_email, :string do
      public? true
    end

    attribute :invoice_email, :string do
      public? true
    end

    attribute :payment_terms, :string do
      public? true
    end

    attribute :delivery_terms, :string do
      public? true
    end

    attribute :currency, :string do
      allow_nil? false
      default "USD"
      public? true
    end

    attribute :instructions, {:array, :string} do
      allow_nil? false
      default []
      public? true
    end

    attribute :terms_url, :string do
      public? true
    end

    attribute :supplier_code_url, :string do
      public? true
    end

    attribute :metadata, :map do
      allow_nil? false
      default %{}
      public? true
    end

    timestamps()
  end

  relationships do
    belongs_to :company_profile, GnomeGarden.Company.Profile do
      allow_nil? false
      public? true
    end

    belongs_to :customer_organization, GnomeGarden.Operations.Organization do
      public? true
    end

    has_many :requirements, GnomeGarden.Commercial.CustomerVendorRequirement do
      public? true
    end
  end

  aggregates do
    count :ready_requirement_count, :requirements do
      filter expr(status in [:ready, :sent, :accepted, :waived])
    end

    count :open_requirement_count, :requirements do
      filter expr(status in [:missing, :ready, :rejected])
    end
  end

  identities do
    identity :unique_company_customer_vendor_onboarding, [:company_profile_id, :key]
  end
end
