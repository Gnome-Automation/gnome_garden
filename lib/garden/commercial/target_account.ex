defmodule GnomeGarden.Commercial.TargetAccount do
  @moduledoc """
  Discovered target account waiting for human promotion into the signal inbox.

  Target accounts hold broad outbound and market-discovery candidates before
  they become true commercial intake. They aggregate raw observations, link to
  a durable organization when available, and only become signals when a human
  decides the account deserves active follow-up.
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
    table "commercial_target_accounts"
    repo GnomeGarden.Repo

    custom_indexes do
      index [:website_domain], name: "commercial_target_accounts_website_domain_idx"
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

      accept [
        :name,
        :website,
        :location,
        :region,
        :industry,
        :size_bucket,
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

      change {GnomeGarden.Commercial.Changes.NormalizeTargetAccountWebsite, []}
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

      change {GnomeGarden.Commercial.Changes.NormalizeTargetAccountWebsite, []}
    end

    update :start_review do
      accept []
      change transition_state(:reviewing)
    end

    update :promote_to_signal do
      require_atomic? false
      accept []
      change {GnomeGarden.Commercial.Changes.PromoteTargetAccountToSignal, []}
      change transition_state(:promoted)
    end

    update :reject do
      accept [:notes]
      change transition_state(:rejected)
    end

    update :archive do
      accept []
      change transition_state(:archived)
    end

    update :reopen do
      accept []
      change transition_state(:new)
    end

    update :resolve_identity do
      require_atomic? false
      accept []
      argument :organization_id, :uuid
      argument :contact_person_id, :uuid
      change {GnomeGarden.Commercial.Changes.ResolveTargetAccountIdentity, []}
    end

    read :review_queue do
      filter expr(status in [:new, :reviewing])

      prepare build(
                sort: [intent_score: :desc, fit_score: :desc, inserted_at: :desc],
                load: [
                  :discovery_program,
                  :organization,
                  :promoted_signal,
                  :observation_count,
                  :latest_observed_at,
                  :latest_observation_summary
                ]
              )
    end

    read :promoted do
      filter expr(status == :promoted)

      prepare build(
                sort: [promoted_at: :desc, inserted_at: :desc],
                load: [:discovery_program, :organization, :promoted_signal]
              )
    end

    read :rejected do
      filter expr(status == :rejected)

      prepare build(
                sort: [updated_at: :desc, inserted_at: :desc],
                load: [
                  :discovery_program,
                  :organization,
                  :promoted_signal,
                  :observation_count,
                  :latest_observed_at,
                  :latest_observation_summary,
                  :status_variant
                ]
              )
    end

    read :archived do
      filter expr(status == :archived)

      prepare build(
                sort: [updated_at: :desc, inserted_at: :desc],
                load: [
                  :discovery_program,
                  :organization,
                  :promoted_signal,
                  :observation_count,
                  :latest_observed_at,
                  :latest_observation_summary,
                  :status_variant
                ]
              )
    end

    read :for_organization do
      argument :organization_id, :uuid, allow_nil?: false
      filter expr(organization_id == ^arg(:organization_id))

      prepare build(
                sort: [inserted_at: :desc],
                load: [:discovery_program, :observation_count, :latest_observed_at]
              )
    end

    read :for_contact_person do
      argument :contact_person_id, :uuid, allow_nil?: false
      filter expr(contact_person_id == ^arg(:contact_person_id))

      prepare build(
                sort: [inserted_at: :desc],
                load: [:discovery_program, :organization, :observation_count, :latest_observed_at]
              )
    end

    read :for_discovery_program do
      argument :discovery_program_id, :uuid, allow_nil?: false
      filter expr(discovery_program_id == ^arg(:discovery_program_id))

      prepare build(
                sort: [intent_score: :desc, fit_score: :desc, inserted_at: :desc],
                load: [:status_variant, :observation_count, :latest_observed_at]
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

    has_many :observations, GnomeGarden.Commercial.TargetObservation do
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
    count :observation_count, :observations do
      public? true
    end

    first :latest_observed_at, :observations, :observed_at do
      sort observed_at: :desc
      public? true
    end

    first :latest_observation_summary, :observations, :summary do
      sort observed_at: :desc
      public? true
    end
  end

  identities do
    identity :unique_website_domain, [:website_domain]
    identity :unique_name_key_location, [:name_key, :location]
  end
end
