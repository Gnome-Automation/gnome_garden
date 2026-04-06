defmodule GnomeGarden.Sales.Lead do
  @moduledoc """
  Lead resource for CRM.

  Pre-qualification workflow for prospects that need vetting
  before becoming Companies/Contacts. Can be converted to
  Company + Contact + Opportunity when qualified.
  """

  use Ash.Resource,
    otp_app: :gnome_garden,
    domain: GnomeGarden.Sales,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshAdmin.Resource, AshJido],
    notifiers: [AshJido.Notifier, Ash.Notifier.PubSub]

  admin do
    table_columns [:id, :first_name, :last_name, :company_name, :status, :source, :inserted_at]
  end

  postgres do
    table "leads"
    repo GnomeGarden.Repo
  end

  jido do
    signal_bus(GnomeGarden.SignalBus)

    publish :create, "sales.lead.created", include: :all
    publish :qualify, "sales.lead.qualified", include: :all
    publish :reject_lead, "sales.lead.rejected", include: :all
    publish :convert, "sales.lead.converted", include: :all
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true

      accept [
        :first_name,
        :last_name,
        :email,
        :phone,
        :title,
        :company_name,
        :source,
        :source_details,
        :source_url,
        :description,
        :owner_id,
        :company_id,
        :prospect_id
      ]

      change set_attribute(:status, :new)
    end

    update :update do
      accept [
        :first_name,
        :last_name,
        :email,
        :phone,
        :title,
        :company_name,
        :status,
        :source,
        :source_details,
        :source_url,
        :description,
        :owner_id,
        :company_id
      ]
    end

    update :screen do
      accept []
      change set_attribute(:status, :screening)
    end

    update :qualify do
      accept []
      change set_attribute(:status, :qualified)
    end

    update :start_outreach do
      accept []
      change set_attribute(:status, :outreach)
    end

    update :set_meeting do
      accept []
      change set_attribute(:status, :meeting)
    end

    update :send_proposal do
      accept []
      change set_attribute(:status, :proposal)
    end

    update :reject_lead do
      accept [:rejection_reason, :rejection_notes]
      change set_attribute(:status, :rejected)
    end

    update :convert do
      description "Mark lead as converted after creating Company/Contact/Opportunity"
      argument :company_id, :uuid, allow_nil?: false
      argument :contact_id, :uuid, allow_nil?: false
      argument :opportunity_id, :uuid

      change set_attribute(:status, :converted)
      change set_attribute(:converted_at, &DateTime.utc_now/0)
      change set_attribute(:converted_company_id, arg(:company_id))
      change set_attribute(:converted_contact_id, arg(:contact_id))
      change set_attribute(:converted_opportunity_id, arg(:opportunity_id))
    end

    read :by_owner do
      argument :owner_id, :uuid, allow_nil?: false
      filter expr(owner_id == ^arg(:owner_id) and status in [:new, :contacted, :qualified])
      prepare build(sort: [inserted_at: :desc])
    end

    read :by_status do
      argument :status, :atom, allow_nil?: false
      filter expr(status == ^arg(:status))
      prepare build(sort: [inserted_at: :desc])
    end

    read :new_leads do
      filter expr(status == :new)
      prepare build(sort: [inserted_at: :desc])
    end

    read :qualified do
      filter expr(status == :qualified)
      prepare build(sort: [inserted_at: :desc])
    end

    read :active do
      filter expr(status in [:new, :contacted, :qualified])
      prepare build(sort: [inserted_at: :desc])
    end

    read :by_source do
      argument :source, :atom, allow_nil?: false
      filter expr(source == ^arg(:source) and status in [:new, :contacted, :qualified])
      prepare build(sort: [inserted_at: :desc])
    end

    create :quick_add do
      accept [:company_name, :source, :source_details, :source_url, :description]
      change set_attribute(:status, :new)
      change set_attribute(:first_name, "Unknown")
      change set_attribute(:last_name, "Unknown")
    end
  end

  pub_sub do
    module GnomeGardenWeb.Endpoint
    prefix "lead"

    publish :create, "created"
    publish :update, "updated"
    publish :qualify, "qualified"
    publish :reject_lead, "rejected"
    publish :start_outreach, "updated"
    publish :convert, "converted"
  end

  attributes do
    uuid_primary_key :id

    attribute :first_name, :string do
      allow_nil? false
      public? true
      description "Lead's first name"
    end

    attribute :last_name, :string do
      allow_nil? false
      public? true
      description "Lead's last name"
    end

    attribute :email, :ci_string do
      public? true
      description "Email address"
    end

    attribute :phone, :string do
      public? true
      description "Phone number"
    end

    attribute :title, :string do
      public? true
      description "Job title"
    end

    attribute :company_name, :string do
      public? true
      description "Company name (before Company record exists)"
    end

    attribute :status, :atom do
      default :new
      public? true

      constraints one_of: [
                    :new,
                    :screening,
                    :qualified,
                    :outreach,
                    :meeting,
                    :proposal,
                    :converted,
                    :rejected
                  ]

      description "Lead status"
    end

    attribute :rejection_reason, :atom do
      public? true

      constraints one_of: [
                    :not_a_fit,
                    :too_large,
                    :too_small,
                    :wrong_industry,
                    :wrong_region,
                    :duplicate,
                    :no_budget,
                    :other
                  ]
    end

    attribute :rejection_notes, :string, public?: true

    attribute :source, :atom do
      public? true
      constraints one_of: [:website, :referral, :trade_show, :cold_call, :bid, :other]
      description "How we found this lead"
    end

    attribute :source_details, :string do
      public? true
      description "Signal — why this is a lead right now"
    end

    attribute :source_url, :string do
      public? true
      description "URL where we found this lead"
    end

    attribute :description, :string do
      public? true
      description "What the company does and why they need our services"
    end

    attribute :converted_at, :utc_datetime do
      public? true
      description "When lead was converted"
    end

    attribute :converted_company_id, :uuid do
      public? true
      description "Company created from conversion"
    end

    attribute :converted_contact_id, :uuid do
      public? true
      description "Contact created from conversion"
    end

    attribute :converted_opportunity_id, :uuid do
      public? true
      description "Opportunity created from conversion"
    end

    timestamps()
  end

  relationships do
    belongs_to :company, GnomeGarden.Sales.Company do
      public? true
      description "Company this lead is for"
    end

    belongs_to :owner, GnomeGarden.Accounts.User do
      public? true
      description "User who owns this lead"
    end

    belongs_to :prospect, GnomeGarden.Agents.Prospect do
      public? true
      description "Source prospect if created from agent discovery"
    end

    has_many :activities, GnomeGarden.Sales.Activity do
      public? true
    end
  end

  calculations do
    calculate :full_name, :string, expr(first_name <> " " <> last_name)
  end
end
