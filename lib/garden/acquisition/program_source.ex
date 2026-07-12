defmodule GnomeGarden.Acquisition.ProgramSource do
  @moduledoc "Authoritative bounded execution policy joining one acquisition program to one source."

  use Ash.Resource,
    otp_app: :gnome_garden,
    domain: GnomeGarden.Acquisition,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshAdmin.Resource, AshStateMachine]

  @policy_fields [
    :priority,
    :query_templates,
    :cadence_minutes,
    :max_queries_per_run,
    :max_results_per_query,
    :spend_limit_per_run,
    :spend_limit_per_day,
    :enrichment_policy,
    :max_enrichments_per_run,
    :finding_limit_per_run,
    :finding_limit_per_day,
    :next_run_at,
    :last_run_at
  ]

  postgres do
    table "acquisition_program_sources"
    repo GnomeGarden.Repo

    identity_index_names unique_program_source: "acquisition_program_sources_program_source_index"

    custom_indexes do
      index [:status, :enabled, :next_run_at]
    end

    references do
      reference :program, on_delete: :delete
      reference :source, on_delete: :delete
    end
  end

  state_machine do
    state_attribute :status
    initial_states [:draft]
    default_initial_state :draft

    transitions do
      transition :activate, from: [:draft, :paused, :blocked], to: :active
      transition :pause, from: :active, to: :paused
      transition :block, from: [:draft, :active, :paused], to: :blocked
      transition :archive, from: :*, to: :archived
    end
  end

  actions do
    defaults [:read, :destroy]

    action :backfill, :map do
      run GnomeGarden.Acquisition.Actions.BackfillProgramSources
    end

    create :create do
      primary? true
      upsert? true
      upsert_identity :unique_program_source
      upsert_fields []
      accept @policy_fields ++ [:program_id, :source_id, :metadata]
      change set_attribute(:enabled, false)
      change set_attribute(:status, :draft)
    end

    update :update_policy do
      require_atomic? false
      accept @policy_fields ++ [:metadata]
    end

    update :activate do
      require_atomic? false
      accept []
      change GnomeGarden.Acquisition.Changes.ValidateProgramSourceActivation
      change transition_state(:active)
      change set_attribute(:enabled, true)
      change set_attribute(:blocked_reason, nil)
    end

    update :pause do
      require_atomic? false
      accept []
      change transition_state(:paused)
      change set_attribute(:enabled, false)
    end

    update :block do
      require_atomic? false
      accept [:blocked_reason]
      change transition_state(:blocked)
      change set_attribute(:enabled, false)
    end

    update :archive do
      require_atomic? false
      accept []
      change transition_state(:archived)
      change set_attribute(:enabled, false)
    end

    update :mark_scheduled do
      require_atomic? false
      accept []

      argument :scheduled_at, :utc_datetime do
        allow_nil? false
      end

      change GnomeGarden.Acquisition.Changes.AdvanceProgramSourceSchedule
    end

    read :for_program do
      argument :program_id, :uuid, allow_nil?: false
      filter expr(program_id == ^arg(:program_id))
      prepare build(sort: [priority: :desc, inserted_at: :asc], load: [:source])
    end

    read :for_source do
      argument :source_id, :uuid, allow_nil?: false
      filter expr(source_id == ^arg(:source_id))
      prepare build(sort: [priority: :desc, inserted_at: :asc], load: [:program])
    end

    read :runnable do
      argument :reference_time, :utc_datetime, allow_nil?: false

      filter expr(
               enabled == true and status == :active and
                 (is_nil(next_run_at) or next_run_at <= ^arg(:reference_time)) and
                 program.status == :active and source.enabled == true and source.status == :active
             )

      prepare build(sort: [priority: :desc, next_run_at: :asc], load: [:program, :source])
    end

    read :runnable_commercial_discovery do
      argument :reference_time, :utc_datetime, allow_nil?: false

      filter expr(
               enabled == true and status == :active and
                 (is_nil(next_run_at) or next_run_at <= ^arg(:reference_time)) and
                 program.status == :active and program.program_family == :discovery and
                 program.program_type == :discovery_run and
                 not is_nil(program.discovery_program_id) and source.enabled == true and
                 source.status == :active and source.external_ref == "provider:exa:search"
             )

      prepare build(
                sort: [priority: :desc, next_run_at: :asc],
                load: [program: :discovery_program, source: []]
              )
    end

    read :active_exa_for_discovery_program do
      argument :discovery_program_id, :uuid, allow_nil?: false
      get? true

      filter expr(
               enabled == true and status == :active and
                 program.status == :active and
                 program.discovery_program_id == ^arg(:discovery_program_id) and
                 source.enabled == true and source.status == :active and
                 source.external_ref == "provider:exa:search"
             )

      prepare build(load: [:program, :source])
    end

    read :workspace do
      argument :id, :uuid, allow_nil?: false
      get_by [:id]
      prepare build(load: [:program, :source, :findings])
    end
  end

  attributes do
    uuid_primary_key :id
    attribute :enabled, :boolean, allow_nil?: false, default: false, public?: true

    attribute :status, :atom do
      allow_nil? false
      default :draft
      public? true
      constraints one_of: [:draft, :active, :paused, :blocked, :archived]
    end

    attribute :priority, :integer, allow_nil?: false, default: 0, public?: true
    attribute :query_templates, {:array, :string}, allow_nil?: false, default: [], public?: true

    attribute :cadence_minutes, :integer,
      allow_nil?: false,
      default: 1_440,
      public?: true,
      constraints: [min: 1]

    attribute :max_queries_per_run, :integer,
      allow_nil?: false,
      default: 8,
      public?: true,
      constraints: [min: 1]

    attribute :max_results_per_query, :integer,
      allow_nil?: false,
      default: 8,
      public?: true,
      constraints: [min: 1]

    attribute :spend_limit_per_run, :money,
      allow_nil?: false,
      default: &default_run_spend/0,
      public?: true

    attribute :spend_limit_per_day, :money,
      allow_nil?: false,
      default: &default_daily_spend/0,
      public?: true

    attribute :enrichment_policy, :atom do
      allow_nil? false
      default :verify_promotable
      public? true
      constraints one_of: [:none, :verify_promotable, :verify_ranked]
    end

    attribute :max_enrichments_per_run, :integer,
      allow_nil?: false,
      default: 5,
      public?: true,
      constraints: [min: 0]

    attribute :finding_limit_per_run, :integer,
      allow_nil?: false,
      default: 5,
      public?: true,
      constraints: [min: 0]

    attribute :finding_limit_per_day, :integer,
      allow_nil?: false,
      default: 25,
      public?: true,
      constraints: [min: 0]

    attribute :next_run_at, :utc_datetime, public?: true
    attribute :last_run_at, :utc_datetime, public?: true
    attribute :blocked_reason, :string, public?: true
    attribute :metadata, :map, allow_nil?: false, default: %{}, public?: true
    timestamps()
  end

  relationships do
    belongs_to :program, GnomeGarden.Acquisition.Program, allow_nil?: false, public?: true
    belongs_to :source, GnomeGarden.Acquisition.Source, allow_nil?: false, public?: true

    has_many :findings, GnomeGarden.Acquisition.Finding do
      destination_attribute :program_source_id
      public? true
    end
  end

  identities do
    identity :unique_program_source, [:program_id, :source_id]
  end

  defp default_run_spend, do: Money.new!(:USD, "0.25")
  defp default_daily_spend, do: Money.new!(:USD, "10.00")
end
