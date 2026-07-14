defmodule GnomeGarden.Company.Qualification do
  @moduledoc """
  A durable capability Gnome holds: registration, license, certification,
  insurance limit, bonding capacity, or partner standing.

  Owns capability facts and lifecycle only (see docs/company-growth-plan.md).
  It never mutates `Company.Profile`; eligibility reads active
  qualifications through ProfileContext (epic bead .5). Recurring legal
  obligations stay in `Company.ComplianceObligation`.
  """

  use Ash.Resource,
    otp_app: :gnome_garden,
    domain: GnomeGarden.Company,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshAdmin.Resource, AshStateMachine],
    notifiers: [Ash.Notifier.PubSub]

  admin do
    table_columns [:id, :kind, :name, :issuing_authority, :status, :expires_on]
  end

  postgres do
    table "company_qualifications"
    repo GnomeGarden.Repo

    references do
      reference :company_profile, on_delete: :delete
      reference :owner_team_member, on_delete: :nilify
      reference :growth_initiative, on_delete: :nilify
      reference :evidence_document, on_delete: :nilify
    end
  end

  state_machine do
    state_attribute :status
    initial_states [:pending]
    default_initial_state :pending

    transitions do
      transition :activate, from: [:pending, :suspended, :expired], to: :active
      transition :suspend, from: :active, to: :suspended
      transition :expire, from: [:active, :suspended], to: :expired
      transition :retire, from: [:pending, :active, :suspended, :expired], to: :retired
    end
  end

  actions do
    defaults [:read]

    create :create do
      primary? true

      accept [
        :company_profile_id,
        :kind,
        :name,
        :issuing_authority,
        :identifier,
        :effective_on,
        :expires_on,
        :renewal_lead_days,
        :verification_url,
        :verified_on,
        :unlocks,
        :details,
        :owner_team_member_id,
        :growth_initiative_id,
        :evidence_document_id
      ]
    end

    update :update do
      require_atomic? false

      accept [
        :name,
        :issuing_authority,
        :identifier,
        :effective_on,
        :expires_on,
        :renewal_lead_days,
        :verification_url,
        :verified_on,
        :unlocks,
        :details,
        :owner_team_member_id,
        :evidence_document_id
      ]
    end

    update :activate do
      require_atomic? false
      accept [:effective_on, :expires_on, :identifier, :verified_on, :verification_url]
      change transition_state(:active)
    end

    update :suspend do
      require_atomic? false
      accept []
      change transition_state(:suspended)
    end

    update :expire do
      require_atomic? false
      accept []
      change transition_state(:expired)
    end

    update :retire do
      require_atomic? false
      accept []
      change transition_state(:retired)
    end

    read :active do
      filter expr(status == :active)
      prepare build(sort: [expires_on: :asc_nils_last])
    end

    read :registry do
      prepare build(
                sort: [status: :asc, expires_on: :asc_nils_last],
                load: [:status_variant, :owner_team_member]
              )
    end

    read :expiring_within do
      argument :days, :integer, allow_nil?: false

      filter expr(
               status == :active and
                 not is_nil(expires_on) and
                 expires_on <= date_add(today(), ^arg(:days), :day)
             )

      prepare build(sort: [expires_on: :asc])
    end
  end

  pub_sub do
    module GnomeGardenWeb.Endpoint
    prefix "company_qualification"

    publish_all :create, "created"
    publish_all :update, "updated"
    publish_all :update, ["updated", :_pkey]
  end

  validations do
    validate {GnomeGarden.Company.Validations.QualificationDetails, []}
  end

  attributes do
    uuid_primary_key :id

    attribute :kind, :atom do
      allow_nil? false
      public? true

      constraints one_of: [
                    :registration,
                    :license,
                    :certification,
                    :insurance,
                    :bonding,
                    :partner_standing
                  ]
    end

    attribute :name, :string do
      allow_nil? false
      public? true
    end

    attribute :issuing_authority, :string do
      allow_nil? false
      public? true
    end

    attribute :identifier, :string do
      public? true
    end

    attribute :status, :atom do
      allow_nil? false
      default :pending
      public? true
      constraints one_of: [:pending, :active, :expired, :suspended, :retired]
    end

    attribute :effective_on, :date do
      public? true
    end

    attribute :expires_on, :date do
      public? true
    end

    attribute :renewal_lead_days, :integer do
      allow_nil? false
      default 60
      public? true
      constraints min: 1
    end

    attribute :verification_url, :string do
      public? true
    end

    attribute :verified_on, :date do
      public? true
    end

    attribute :unlocks, {:array, :string} do
      allow_nil? false
      default []
      public? true

      description "Service lines or procurement markets this capability unlocks"
    end

    attribute :details, :map do
      allow_nil? false
      default %{}
      public? true

      description "Kind-specific facts, validated per kind (see QualificationDetails)"
    end

    timestamps()
  end

  relationships do
    belongs_to :company_profile, GnomeGarden.Company.Profile do
      allow_nil? false
      public? true
    end

    belongs_to :owner_team_member, GnomeGarden.Operations.TeamMember do
      public? true
    end

    belongs_to :growth_initiative, GnomeGarden.Company.GrowthInitiative do
      public? true
    end

    belongs_to :evidence_document, GnomeGarden.Company.Document do
      public? true
    end

    has_many :tasks, GnomeGarden.Operations.Task do
      destination_attribute :company_qualification_id
      public? true
    end
  end

  calculations do
    calculate :status_variant,
              :atom,
              {GnomeGarden.Calculations.EnumVariant,
               field: :status,
               mapping: [
                 pending: :info,
                 active: :success,
                 expired: :error,
                 suspended: :warning,
                 retired: :default
               ],
               default: :default}
  end

  identities do
    identity :unique_capability, [:company_profile_id, :kind, :issuing_authority, :name]
  end
end
