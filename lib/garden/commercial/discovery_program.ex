defmodule GnomeGarden.Commercial.DiscoveryProgram do
  @moduledoc """
  Durable definition of an outbound discovery or scouting motion.

  Discovery programs describe where Gnome wants agents and operators to look
  for new work. They scope the target industries, regions, search terms, and
  watch channels that should produce discovery records and supporting evidence. The
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
      reference :owner_team_member, on_delete: :nilify
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
        :owner_team_member_id
      ]

      change GnomeGarden.Commercial.Changes.SyncAcquisitionProgram
    end

    update :update do
      require_atomic? false

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
        :owner_team_member_id
      ]

      change GnomeGarden.Commercial.Changes.SyncAcquisitionProgram
    end

    update :activate do
      require_atomic? false
      accept []
      change transition_state(:active)
      change GnomeGarden.Commercial.Changes.SyncAcquisitionProgram
    end

    update :pause do
      require_atomic? false
      accept []
      change transition_state(:paused)
      change GnomeGarden.Commercial.Changes.SyncAcquisitionProgram
    end

    update :archive do
      require_atomic? false
      accept []
      change transition_state(:archived)
      change GnomeGarden.Commercial.Changes.SyncAcquisitionProgram
    end

    update :reopen do
      require_atomic? false
      accept []
      change transition_state(:draft)
      change GnomeGarden.Commercial.Changes.SyncAcquisitionProgram
    end

    update :mark_ran do
      require_atomic? false
      accept []
      change set_attribute(:last_run_at, &DateTime.utc_now/0)
      change GnomeGarden.Commercial.Changes.SyncAcquisitionProgram
    end

    read :active do
      filter expr(status == :active)

      prepare build(
                sort: [priority: :desc, inserted_at: :desc],
                load: [
                  :status_variant,
                  :priority_variant,
                  :is_due_to_run,
                  :run_status_variant,
                  :run_status_label,
                  :discovery_record_count,
                  :review_discovery_record_count,
                  :discovery_evidence_count,
                  :latest_evidence_at
                ]
              )
    end

    read :due_for_run do
      filter expr(
               status == :active and
                 (is_nil(last_run_at) or last_run_at < ago(cadence_hours, :hour))
             )

      prepare build(
                sort: [priority: :desc, last_run_at: :asc, inserted_at: :asc],
                load: [
                  :status_variant,
                  :priority_variant,
                  :is_due_to_run,
                  :run_status_variant,
                  :run_status_label,
                  :review_discovery_record_count
                ]
              )
    end

    read :for_owner do
      argument :owner_team_member_id, :uuid, allow_nil?: false
      filter expr(owner_team_member_id == ^arg(:owner_team_member_id))

      prepare build(
                sort: [priority: :desc, inserted_at: :desc],
                load: [
                  :discovery_record_count,
                  :review_discovery_record_count,
                  :is_due_to_run,
                  :run_status_variant,
                  :run_status_label
                ]
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
    belongs_to :owner_team_member, GnomeGarden.Operations.TeamMember do
      public? true
    end

    has_many :discovery_records, GnomeGarden.Commercial.DiscoveryRecord do
      destination_attribute :discovery_program_id
      public? true
    end

    has_many :discovery_evidence, GnomeGarden.Commercial.DiscoveryEvidence do
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

    calculate :is_due_to_run,
              :boolean,
              expr(
                status == :active and
                  (is_nil(last_run_at) or last_run_at < ago(cadence_hours, :hour))
              )

    calculate :run_status_variant,
              :atom,
              expr(
                cond do
                  status != :active -> :default
                  is_nil(last_run_at) -> :warning
                  last_run_at < ago(cadence_hours, :hour) -> :warning
                  true -> :success
                end
              )

    calculate :run_status_label,
              :string,
              expr(
                cond do
                  status != :active -> "Inactive"
                  is_nil(last_run_at) -> "Never run"
                  last_run_at < ago(cadence_hours, :hour) -> "Due now"
                  true -> "On cadence"
                end
              )
  end

  aggregates do
    count :discovery_record_count, :discovery_records do
      public? true
    end

    count :review_discovery_record_count, :discovery_records do
      filter expr(status in [:new, :reviewing])
      public? true
    end

    count :discovery_evidence_count, :discovery_evidence do
      public? true
    end

    first :latest_evidence_at, :discovery_evidence, :observed_at do
      sort observed_at: :desc
      public? true
    end
  end

  identities do
    identity :unique_name, [:name]
  end
end
