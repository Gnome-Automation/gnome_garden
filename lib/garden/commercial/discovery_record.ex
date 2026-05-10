defmodule GnomeGarden.Commercial.DiscoveryRecord do
  @moduledoc """
  Source-specific discovery record that feeds the acquisition queue.

  Discovery records are for programmatic outbound discovery where the system
  needs a durable source record, evidence rollup, identity resolution, and
  source-state transitions. Direct findings can enter Acquisition without this
  wrapper and still be accepted or promoted once their own summary, source, and
  work description are ready.
  """

  use Ash.Resource,
    otp_app: :gnome_garden,
    domain: GnomeGarden.Commercial,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshAdmin.Resource, AshStateMachine]

  admin do
    table_columns [
      :id,
      :name,
      :website_domain,
      :status,
      :fit_score,
      :intent_score,
      :organization_id,
      :inserted_at
    ]
  end

  postgres do
    table "commercial_discovery_records"
    repo GnomeGarden.Repo

    custom_indexes do
      index [:website_domain], name: "commercial_discovery_records_website_domain_idx"
    end

    references do
      reference :discovery_program, on_delete: :nilify
      reference :organization, on_delete: :nilify
      reference :contact_person, on_delete: :nilify
      reference :owner_user, on_delete: :nilify
      reference :promoted_signal, on_delete: :nilify
    end
  end

  state_machine do
    state_attribute :status
    initial_states [:new]
    default_initial_state :new

    transitions do
      transition :start_review, from: :new, to: :reviewing
      transition :promote_to_signal, from: [:new, :reviewing], to: :promoted
      transition :reject, from: [:new, :reviewing], to: :rejected
      transition :archive, from: :*, to: :archived
      transition :reopen, from: [:rejected, :archived], to: :new
    end
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true
      upsert? true
      upsert_identity :unique_website_domain

      upsert_fields {:replace_all_except,
                     [:id, :inserted_at, :status, :promoted_at, :promoted_signal_id]}

      accept [
        :name,
        :website,
        :location,
        :region,
        :industry,
        :size_bucket,
        :record_type,
        :fit_score,
        :intent_score,
        :status,
        :notes,
        :metadata,
        :discovery_program_id,
        :organization_id,
        :contact_person_id,
        :owner_user_id
      ]

      change {GnomeGarden.Commercial.Changes.NormalizeDiscoveryRecordWebsite, []}
      change {GnomeGarden.Commercial.Changes.SyncDiscoveryRecordFinding, []}
    end

    update :update do
      require_atomic? false

      accept [
        :name,
        :website,
        :location,
        :region,
        :industry,
        :size_bucket,
        :record_type,
        :fit_score,
        :intent_score,
        :status,
        :notes,
        :metadata,
        :discovery_program_id,
        :organization_id,
        :contact_person_id,
        :owner_user_id
      ]

      change {GnomeGarden.Commercial.Changes.NormalizeDiscoveryRecordWebsite, []}
      change {GnomeGarden.Commercial.Changes.SyncDiscoveryRecordFinding, []}
    end

    update :start_review do
      require_atomic? false
      accept []
      change transition_state(:reviewing)
      change {GnomeGarden.Commercial.Changes.SyncDiscoveryRecordFinding, []}
    end

    update :promote_to_signal do
      require_atomic? false
      accept []
      change {GnomeGarden.Commercial.Changes.PromoteDiscoveryRecordToSignal, []}
      change transition_state(:promoted)
      change {GnomeGarden.Commercial.Changes.SyncDiscoveryRecordFinding, []}
    end

    update :reject do
      require_atomic? false
      accept [:notes]
      change transition_state(:rejected)
      change {GnomeGarden.Commercial.Changes.SyncDiscoveryRecordFinding, []}
    end

    update :archive do
      require_atomic? false
      accept []
      change transition_state(:archived)
      change {GnomeGarden.Commercial.Changes.SyncDiscoveryRecordFinding, []}
    end

    update :reopen do
      require_atomic? false
      accept []
      change transition_state(:new)
      change {GnomeGarden.Commercial.Changes.SyncDiscoveryRecordFinding, []}
    end

    update :resolve_identity do
      require_atomic? false
      accept []
      argument :organization_id, :uuid
      argument :contact_person_id, :uuid
      change {GnomeGarden.Commercial.Changes.ResolveDiscoveryRecordIdentity, []}
      change {GnomeGarden.Commercial.Changes.SyncDiscoveryRecordFinding, []}
    end

    create :create_prospect do
      description """
      Create a prospect discovery record together with its backing Organization
      in a single transaction. Idempotent on website domain.
      """

      upsert? true
      upsert_identity :unique_website_domain

      upsert_fields {:replace_all_except,
                     [:id, :inserted_at, :status, :promoted_at, :promoted_signal_id]}

      accept [
        :name,
        :website,
        :location,
        :region,
        :industry,
        :size_bucket,
        :fit_score,
        :intent_score,
        :notes,
        :metadata,
        :discovery_program_id
      ]

      argument :organization_name, :string
      argument :organization_website, :string
      argument :organization_primary_region, :string
      argument :organization_phone, :string
      argument :organization_notes, :string
      argument :organization_status, :atom
      argument :organization_relationship_roles, {:array, :string}

      change set_attribute(:record_type, :prospect)
      change {GnomeGarden.Commercial.Changes.UpsertOrganizationForDiscoveryRecord, []}
      change {GnomeGarden.Commercial.Changes.NormalizeDiscoveryRecordWebsite, []}
      change {GnomeGarden.Commercial.Changes.SyncDiscoveryRecordFinding, []}
    end

    create :create_opportunity do
      description """
      Create an opportunity discovery record (company seeking an integrator)
      together with its backing Organization in a single transaction.
      """

      upsert? true
      upsert_identity :unique_website_domain

      upsert_fields {:replace_all_except,
                     [:id, :inserted_at, :status, :promoted_at, :promoted_signal_id]}

      accept [
        :name,
        :website,
        :location,
        :region,
        :industry,
        :size_bucket,
        :fit_score,
        :intent_score,
        :notes,
        :metadata,
        :discovery_program_id
      ]

      argument :organization_name, :string
      argument :organization_website, :string
      argument :organization_primary_region, :string
      argument :organization_phone, :string
      argument :organization_notes, :string
      argument :organization_status, :atom
      argument :organization_relationship_roles, {:array, :string}

      change set_attribute(:record_type, :opportunity)
      change {GnomeGarden.Commercial.Changes.UpsertOrganizationForDiscoveryRecord, []}
      change {GnomeGarden.Commercial.Changes.NormalizeDiscoveryRecordWebsite, []}
      change {GnomeGarden.Commercial.Changes.SyncDiscoveryRecordFinding, []}
    end

    read :for_organization do
      argument :organization_id, :uuid, allow_nil?: false
      filter expr(organization_id == ^arg(:organization_id))

      prepare build(
                sort: [inserted_at: :desc],
                load: [:discovery_program, :discovery_evidence_count, :latest_evidence_at]
              )
    end

    read :for_contact_person do
      argument :contact_person_id, :uuid, allow_nil?: false
      filter expr(contact_person_id == ^arg(:contact_person_id))

      prepare build(
                sort: [inserted_at: :desc],
                load: [
                  :discovery_program,
                  :organization,
                  :discovery_evidence_count,
                  :latest_evidence_at
                ]
              )
    end

    read :for_discovery_program do
      argument :discovery_program_id, :uuid, allow_nil?: false
      filter expr(discovery_program_id == ^arg(:discovery_program_id))

      prepare build(
                sort: [intent_score: :desc, fit_score: :desc, inserted_at: :desc],
                load: [:status_variant, :discovery_evidence_count, :latest_evidence_at]
              )
    end

    read :by_website_domain do
      argument :website_domain, :string, allow_nil?: false
      get_by [:website_domain]
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :name, :string do
      allow_nil? false
      public? true
    end

    attribute :website, :string do
      public? true
    end

    attribute :website_domain, :string do
      public? true
    end

    attribute :name_key, :string do
      public? true
    end

    attribute :location, :string do
      public? true
    end

    attribute :region, :string do
      public? true
    end

    attribute :industry, :string do
      public? true
    end

    attribute :size_bucket, :atom do
      public? true
      constraints one_of: [:small, :medium, :large, :enterprise]
    end

    attribute :record_type, :atom do
      allow_nil? false
      default :prospect
      public? true
      constraints one_of: [:prospect, :opportunity]
    end

    attribute :fit_score, :integer do
      allow_nil? false
      default 50
      public? true
      constraints min: 0, max: 100
    end

    attribute :intent_score, :integer do
      allow_nil? false
      default 50
      public? true
      constraints min: 0, max: 100
    end

    attribute :status, :atom do
      allow_nil? false
      default :new
      public? true
      constraints one_of: [:new, :reviewing, :promoted, :rejected, :archived]
    end

    attribute :promoted_at, :utc_datetime do
      public? true
    end

    attribute :notes, :string do
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
    belongs_to :discovery_program, GnomeGarden.Commercial.DiscoveryProgram do
      public? true
    end

    belongs_to :organization, GnomeGarden.Operations.Organization do
      public? true
    end

    belongs_to :contact_person, GnomeGarden.Operations.Person do
      public? true
    end

    belongs_to :owner_user, GnomeGarden.Accounts.User do
      public? true
    end

    belongs_to :promoted_signal, GnomeGarden.Commercial.Signal do
      public? true
    end

    has_many :discovery_evidence, GnomeGarden.Commercial.DiscoveryEvidence do
      destination_attribute :discovery_record_id
      public? true
    end
  end

  calculations do
    calculate :status_variant,
              :atom,
              {GnomeGarden.Calculations.EnumVariant,
               field: :status,
               mapping: [
                 new: :default,
                 reviewing: :info,
                 promoted: :success,
                 rejected: :error,
                 archived: :warning
               ],
               default: :default}
  end

  aggregates do
    count :discovery_evidence_count, :discovery_evidence do
      public? true
    end

    first :latest_evidence_at, :discovery_evidence, :observed_at do
      sort observed_at: :desc
      public? true
    end

    first :latest_evidence_summary, :discovery_evidence, :summary do
      sort observed_at: :desc
      public? true
    end
  end

  identities do
    identity :unique_website_domain, [:website_domain]
    identity :unique_name_key_location, [:name_key, :location]
  end
end
