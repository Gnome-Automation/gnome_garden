defmodule GnomeGarden.Acquisition.Program do
  @moduledoc """
  Operator-defined or agent-defined acquisition program.

  Programs represent why the system is scanning, not where it scans. A program
  might represent a market sweep, an industry watch, or a discovery lane.
  """

  use Ash.Resource,
    otp_app: :gnome_garden,
    domain: GnomeGarden.Acquisition,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshAdmin.Resource]

  admin do
    table_columns [:name, :program_family, :program_type, :status, :last_run_at]
  end

  postgres do
    table "acquisition_programs"
    repo GnomeGarden.Repo

    custom_indexes do
      index [:program_family, :status]
    end

    references do
      reference :legacy_discovery_program, on_delete: :nilify
      reference :owner_user, on_delete: :nilify
    end
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true

      accept [
        :name,
        :external_ref,
        :description,
        :program_family,
        :program_type,
        :status,
        :scope,
        :metadata,
        :last_run_at,
        :legacy_discovery_program_id,
        :owner_user_id
      ]
    end

    update :update do
      accept [
        :name,
        :description,
        :program_family,
        :program_type,
        :status,
        :scope,
        :metadata,
        :last_run_at,
        :legacy_discovery_program_id,
        :owner_user_id
      ]
    end

    read :by_external_ref do
      argument :external_ref, :string, allow_nil?: false
      get_by [:external_ref]
    end

    read :by_legacy_discovery_program do
      argument :legacy_discovery_program_id, :uuid, allow_nil?: false
      get_by [:legacy_discovery_program_id]
    end

    read :console do
      prepare build(
                sort: [status: :asc, last_run_at: :desc, inserted_at: :desc],
                load: [
                  :finding_count,
                  :review_finding_count,
                  :promoted_finding_count,
                  :noise_finding_count,
                  :runnable,
                  :health_status,
                  :health_variant,
                  :health_note,
                  :status_variant,
                  :latest_run_id
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

    attribute :external_ref, :string do
      allow_nil? false
      public? true
    end

    attribute :description, :string do
      public? true
    end

    attribute :program_family, :atom do
      allow_nil? false
      public? true
      constraints one_of: [:procurement, :discovery, :research, :operations, :other]
    end

    attribute :program_type, :atom do
      allow_nil? false
      public? true

      constraints one_of: [
                    :market_sweep,
                    :named_account_watch,
                    :discovery_run,
                    :coverage_lane,
                    :other
                  ]
    end

    attribute :status, :atom do
      allow_nil? false
      default :active
      public? true
      constraints one_of: [:active, :paused, :archived]
    end

    attribute :scope, :map do
      allow_nil? false
      default %{}
      public? true
    end

    attribute :metadata, :map do
      allow_nil? false
      default %{}
      public? true
    end

    attribute :last_run_at, :utc_datetime do
      public? true
    end

    timestamps()
  end

  relationships do
    belongs_to :legacy_discovery_program, GnomeGarden.Commercial.DiscoveryProgram do
      public? true
    end

    belongs_to :owner_user, GnomeGarden.Accounts.User do
      public? true
    end

    has_many :findings, GnomeGarden.Acquisition.Finding do
      destination_attribute :program_id
      public? true
    end
  end

  calculations do
    calculate :runnable,
              :boolean,
              expr(status == :active and not is_nil(legacy_discovery_program_id))

    calculate :health_status,
              :atom,
              {GnomeGarden.Calculations.AcquisitionProgramHealth, return: :status}

    calculate :health_variant,
              :atom,
              {GnomeGarden.Calculations.EnumVariant,
               field: :health_status,
               mapping: [
                 healthy: :success,
                 running: :info,
                 noisy: :warning,
                 stale: :warning,
                 cancelled: :warning,
                 paused: :default,
                 idle: :default,
                 failing: :error,
                 archived: :default
               ],
               default: :default}

    calculate :health_note,
              :string,
              {GnomeGarden.Calculations.AcquisitionProgramHealth, return: :note}

    calculate :status_variant,
              :atom,
              {GnomeGarden.Calculations.EnumVariant,
               field: :status,
               mapping: [
                 active: :success,
                 paused: :warning,
                 archived: :default
               ],
               default: :default}

    calculate :latest_run_id,
              :string,
              {GnomeGarden.Calculations.MetadataField, field: "last_agent_run_id"}

    calculate :last_run_state,
              :atom,
              {GnomeGarden.Calculations.MetadataField,
               field: "last_agent_run_state",
               cast: :atom,
               allowed: [:completed, :running, :failed, :cancelled]}

    calculate :last_run_state_variant,
              :atom,
              {GnomeGarden.Calculations.MetadataVariant,
               field: "last_agent_run_state",
               mapping: [
                 completed: :success,
                 running: :info,
                 failed: :error,
                 cancelled: :warning
               ],
               default: :default}
  end

  aggregates do
    first :latest_observed_at, :findings, :observed_at do
      public? true
      sort observed_at: :desc
    end

    count :finding_count, :findings do
      public? true
    end

    count :review_finding_count, :findings do
      public? true
      filter expr(status in [:new, :reviewing, :accepted])
    end

    count :promoted_finding_count, :findings do
      public? true
      filter expr(status == :promoted)
    end

    count :noise_finding_count, :findings do
      public? true
      filter expr(status in [:suppressed, :rejected])
    end
  end

  identities do
    identity :unique_external_ref, [:external_ref]
  end
end
