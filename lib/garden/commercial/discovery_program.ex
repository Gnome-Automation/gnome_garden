defmodule GnomeGarden.Commercial.DiscoveryProgram do
  @moduledoc """
  Durable definition of an outbound discovery or scouting motion.

  Discovery programs describe where Gnome wants agents and operators to look
  for new work. They scope the target industries, regions, search terms, and
  watch channels that should produce target accounts and observations. The
  program exists independently from the agent runtime so the commercial model
  can answer which discovery motions are active and what they are producing.
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
      :program_type,
      :priority,
      :status,
      :cadence_hours,
      :last_run_at,
      :inserted_at
    ]
  end

  postgres do
    table "commercial_discovery_programs"
    repo GnomeGarden.Repo

    references do
      reference :owner_user, on_delete: :nilify
    end
  end

  state_machine do
    state_attribute :status
    initial_states [:draft]
    default_initial_state :draft

    transitions do
      transition :activate, from: [:draft, :paused], to: :active
      transition :pause, from: :active, to: :paused
      transition :archive, from: :*, to: :archived
      transition :reopen, from: :archived, to: :draft
    end
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true

      accept [
        :name,
        :description,
        :program_type,
        :priority,
        :status,
        :target_regions,
        :target_industries,
        :search_terms,
        :watch_channels,
        :cadence_hours,
        :notes,
        :metadata,
        :owner_user_id
      ]
    end

    update :update do
      accept [
        :name,
        :description,
        :program_type,
        :priority,
        :status,
        :target_regions,
        :target_industries,
        :search_terms,
        :watch_channels,
        :cadence_hours,
        :last_run_at,
        :notes,
        :metadata,
        :owner_user_id
      ]
    end

    update :activate do
      accept []
      change transition_state(:active)
    end

    update :pause do
      accept []
      change transition_state(:paused)
    end

    update :archive do
      accept []
      change transition_state(:archived)
    end

    update :reopen do
      accept []
      change transition_state(:draft)
    end

    update :mark_ran do
      accept []
      change set_attribute(:last_run_at, &DateTime.utc_now/0)
    end

    read :active do
      filter expr(status == :active)

      prepare build(
                sort: [priority: :desc, inserted_at: :desc],
                load: [
                  :status_variant,
                  :priority_variant,
                  :target_account_count,
                  :review_target_count,
                  :observation_count,
                  :latest_observed_at
                ]
              )
    end

    read :for_owner do
      argument :owner_user_id, :uuid, allow_nil?: false
      filter expr(owner_user_id == ^arg(:owner_user_id))

      prepare build(
                sort: [priority: :desc, inserted_at: :desc],
                load: [:target_account_count, :review_target_count]
              )
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :name, :string do
      allow_nil? false
      public? true
    end

    attribute :description, :string do
      public? true
    end

    attribute :program_type, :atom do
      allow_nil? false
      default :market_scan
      public? true

      constraints one_of: [
                    :market_scan,
                    :territory_watch,
                    :industry_watch,
                    :account_hunt,
                    :referral_network,
                    :custom
                  ]
    end

    attribute :priority, :atom do
      allow_nil? false
      default :normal
      public? true
      constraints one_of: [:low, :normal, :high, :strategic]
    end

    attribute :status, :atom do
      allow_nil? false
      default :draft
      public? true
      constraints one_of: [:draft, :active, :paused, :archived]
    end

    attribute :target_regions, {:array, :string} do
      allow_nil? false
      default []
      public? true
    end

    attribute :target_industries, {:array, :string} do
      allow_nil? false
      default []
      public? true
    end

    attribute :search_terms, {:array, :string} do
      allow_nil? false
      default []
      public? true
    end

    attribute :watch_channels, {:array, :string} do
      allow_nil? false
      default []
      public? true
    end

    attribute :cadence_hours, :integer do
      allow_nil? false
      default 168
      public? true
      constraints min: 1
    end

    attribute :last_run_at, :utc_datetime do
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
    belongs_to :owner_user, GnomeGarden.Accounts.User do
      public? true
    end

    has_many :target_accounts, GnomeGarden.Commercial.TargetAccount do
      destination_attribute :discovery_program_id
      public? true
    end

    has_many :target_observations, GnomeGarden.Commercial.TargetObservation do
      destination_attribute :discovery_program_id
      public? true
    end
  end

  calculations do
    calculate :status_variant,
              :atom,
              {GnomeGarden.Calculations.EnumVariant,
               field: :status,
               mapping: [
                 draft: :default,
                 active: :success,
                 paused: :warning,
                 archived: :default
               ],
               default: :default}

    calculate :priority_variant,
              :atom,
              {GnomeGarden.Calculations.EnumVariant,
               field: :priority,
               mapping: [
                 strategic: :success,
                 high: :warning,
                 normal: :info,
                 low: :default
               ],
               default: :default}
  end

  aggregates do
    count :target_account_count, :target_accounts do
      public? true
    end

    count :review_target_count, :target_accounts do
      filter expr(status in [:new, :reviewing])
      public? true
    end

    count :observation_count, :target_observations do
      public? true
    end

    first :latest_observed_at, :target_observations, :observed_at do
      sort observed_at: :desc
      public? true
    end
  end

  identities do
    identity :unique_name, [:name]
  end
end
