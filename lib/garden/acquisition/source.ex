defmodule GnomeGarden.Acquisition.Source do
  @moduledoc """
  Durable registry of places the platform can scan for work.
  """

  use Ash.Resource,
    otp_app: :gnome_garden,
    domain: GnomeGarden.Acquisition,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshAdmin.Resource],
    notifiers: [Ash.Notifier.PubSub]

  @console_loads [
    :organization,
    :finding_count,
    :review_finding_count,
    :accepted_finding_count,
    :parked_finding_count,
    :rejected_finding_count,
    :promoted_finding_count,
    :noise_finding_count,
    :source_family_label,
    :source_kind_label,
    :scan_strategy_label,
    :status_label,
    :health_label,
    :runnable,
    :health_status,
    :health_variant,
    :health_note,
    :status_variant,
    :latest_run_id,
    :last_run_state,
    :last_run_state_variant,
    :procurement_source
  ]

  @workspace_loads List.delete(@console_loads, :procurement_source) ++
                     [procurement_source: [:provider_budget_state]]

  admin do
    table_columns [:name, :source_family, :source_kind, :status, :enabled, :scan_strategy]
  end

  postgres do
    table "acquisition_sources"
    repo GnomeGarden.Repo

    custom_indexes do
      index [:source_family, :status]
      index [:enabled, :status]
    end

    references do
      reference :procurement_source, on_delete: :nilify
      reference :organization, on_delete: :nilify
    end
  end

  actions do
    defaults [:read]

    create :create do
      primary? true

      accept [
        :name,
        :external_ref,
        :url,
        :source_family,
        :source_kind,
        :status,
        :enabled,
        :scan_strategy,
        :description,
        :metadata,
        :last_run_at,
        :last_success_at,
        :procurement_source_id,
        :organization_id
      ]
    end

    update :update do
      accept [
        :name,
        :url,
        :source_family,
        :source_kind,
        :status,
        :enabled,
        :scan_strategy,
        :description,
        :metadata,
        :last_run_at,
        :last_success_at,
        :procurement_source_id,
        :organization_id
      ]
    end

    read :by_external_ref do
      argument :external_ref, :string, allow_nil?: false
      get_by [:external_ref]
    end

    read :workspace do
      argument :id, :uuid, allow_nil?: false
      get? true
      filter expr(id == ^arg(:id))
      prepare {GnomeGarden.Acquisition.Preparations.SourceConsole, loads: @workspace_loads}
    end

    read :by_url do
      argument :url, :string, allow_nil?: false
      get_by [:url]
    end

    read :search do
      argument :query, :string, allow_nil?: false
      filter expr(fragment("? ILIKE '%' || ? || '%'", name, ^arg(:query)))
      prepare build(sort: [inserted_at: :desc], limit: 50)
    end

    read :console do
      pagination offset?: true, countable: true, required?: false
      prepare {GnomeGarden.Acquisition.Preparations.SourceConsole, loads: @console_loads}
    end

    read :console_needs_configuration do
      pagination offset?: true, countable: true, required?: false
      filter expr(procurement_source.config_status in [:found, :pending, :config_failed, :manual])

      prepare {GnomeGarden.Acquisition.Preparations.SourceConsole, loads: @console_loads}
    end

    read :console_ready do
      pagination offset?: true, countable: true, required?: false

      filter expr(
               enabled == true and status == :active and
                 ((not is_nil(procurement_source_id) and
                     procurement_source.config_status in [:configured, :scan_failed] and
                     procurement_source.portfolio_decision == :adopt and
                     procurement_source.compliance_decision == :adopt and
                     (is_nil(procurement_source.deferred_until) or
                        procurement_source.deferred_until <= now())) or
                    (is_nil(procurement_source_id) and scan_strategy in [:agentic, :deterministic]))
             )

      prepare {GnomeGarden.Acquisition.Preparations.SourceConsole, loads: @console_loads}
    end

    read :console_credentials_needed do
      pagination offset?: true, countable: true, required?: false

      filter expr(
               procurement_source.requires_login == true or
                 procurement_source.source_type == :bidnet
             )

      prepare {GnomeGarden.Acquisition.Preparations.SourceConsole, loads: @console_loads}
    end

    read :console_attention do
      pagination offset?: true, countable: true, required?: false

      filter expr(
               status == :blocked or
                 procurement_source.config_status in [:config_failed, :scan_failed] or
                 fragment("? ->> 'last_agent_run_state' in ('failed', 'cancelled')", metadata) or
                 fragment("? -> 'packet' ->> 'status' = 'download_failed'", metadata) or
                 fragment(
                   "? -> 'last_scan_summary' ->> 'diagnosis' in ('selector_failed', 'listing_selector_matched_no_rows', 'title_selector_matched_no_titles', 'scanner_not_implemented', 'scan_failed', 'all_candidates_filtered_before_scoring', 'no_candidates_extracted')",
                   metadata
                 ) or
                 fragment(
                   "nullif(? -> 'last_scan_summary' ->> 'extracted', '')::integer = 0",
                   metadata
                 ) or
                 fragment(
                   "nullif(? -> 'last_scan_summary' ->> 'extracted', '')::integer > 0 and coalesce(nullif(? -> 'last_scan_summary' ->> 'saved', '')::integer, 0) = 0",
                   metadata,
                   metadata
                 )
             )

      prepare {GnomeGarden.Acquisition.Preparations.SourceConsole, loads: @console_loads}
    end
  end

  pub_sub do
    module GnomeGardenWeb.Endpoint
    prefix "source"

    publish :create, "created"
    publish :update, "updated"
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

    attribute :url, :string do
      allow_nil? false
      public? true
    end

    attribute :source_family, :atom do
      allow_nil? false
      public? true
      constraints one_of: [:procurement, :discovery, :research, :operations, :other]
    end

    attribute :source_kind, :atom do
      allow_nil? false
      public? true
      constraints one_of: [:portal, :company_site, :directory, :job_board, :news_feed, :other]
    end

    attribute :status, :atom do
      allow_nil? false
      default :active
      public? true
      constraints one_of: [:active, :paused, :candidate, :blocked, :archived]
    end

    attribute :enabled, :boolean do
      allow_nil? false
      default true
      public? true
    end

    attribute :scan_strategy, :atom do
      allow_nil? false
      default :deterministic
      public? true
      constraints one_of: [:deterministic, :agentic, :manual]
    end

    attribute :description, :string do
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

    attribute :last_success_at, :utc_datetime do
      public? true
    end

    timestamps()
  end

  relationships do
    belongs_to :procurement_source, GnomeGarden.Procurement.ProcurementSource do
      public? true
    end

    belongs_to :organization, GnomeGarden.Operations.Organization do
      public? true
    end

    has_many :findings, GnomeGarden.Acquisition.Finding do
      destination_attribute :source_id
      public? true
    end
  end

  calculations do
    calculate :source_family_label,
              :string,
              {GnomeGarden.Calculations.EnumLabel, field: :source_family}

    calculate :source_kind_label,
              :string,
              {GnomeGarden.Calculations.EnumLabel, field: :source_kind}

    calculate :scan_strategy_label,
              :string,
              {GnomeGarden.Calculations.EnumLabel, field: :scan_strategy}

    calculate :status_label,
              :string,
              {GnomeGarden.Calculations.EnumLabel, field: :status}

    calculate :health_label,
              :string,
              {GnomeGarden.Calculations.EnumLabel, field: :health_status}

    calculate :runnable, :boolean, GnomeGarden.Calculations.AcquisitionSourceRunnable

    calculate :health_status,
              :atom,
              {GnomeGarden.Calculations.AcquisitionSourceHealth, return: :status}

    calculate :health_variant,
              :atom,
              {GnomeGarden.Calculations.EnumVariant,
               field: :health_status,
               mapping: [
                 healthy: :success,
                 ready: :success,
                 running: :info,
                 configuring: :info,
                 needs_configuration: :info,
                 credentials_pending: :warning,
                 needs_login: :warning,
                 no_results: :warning,
                 zero_saved: :warning,
                 noisy: :warning,
                 stale: :warning,
                 cancelled: :warning,
                 paused: :default,
                 disabled: :default,
                 manual: :default,
                 idle: :default,
                 blocked: :error,
                 failing: :error,
                 credentials_invalid: :error,
                 selector_failed: :error,
                 document_capture_failed: :error,
                 archived: :default
               ],
               default: :default}

    calculate :health_note,
              :string,
              {GnomeGarden.Calculations.AcquisitionSourceHealth, return: :note}

    calculate :status_variant,
              :atom,
              {GnomeGarden.Calculations.EnumVariant,
               field: :status,
               mapping: [
                 active: :success,
                 paused: :warning,
                 candidate: :info,
                 blocked: :error,
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

    calculate :last_retrieval_path,
              :atom,
              {GnomeGarden.Calculations.MetadataField,
               field: ["last_retrieval", "retrieval_path"],
               cast: :atom,
               allowed: [:provider_api, :http, :browser, :playwright, :browserless]}

    calculate :last_retrieval_status,
              :atom,
              {GnomeGarden.Calculations.MetadataField,
               field: ["last_retrieval", "status"],
               cast: :atom,
               allowed: [:running, :completed, :failed, :blocked]}

    calculate :last_retrieval_blocked,
              :boolean,
              {GnomeGarden.Calculations.MetadataField,
               field: ["last_retrieval", "blocked"], cast: :raw}
  end

  aggregates do
    count :finding_count, :findings do
      public? true
    end

    count :review_finding_count, :findings do
      public? true
      filter expr(status in [:new, :reviewing])
    end

    count :accepted_finding_count, :findings do
      public? true
      filter expr(status == :accepted)
    end

    count :parked_finding_count, :findings do
      public? true
      filter expr(status == :parked)
    end

    count :rejected_finding_count, :findings do
      public? true
      filter expr(status == :rejected)
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
    identity :unique_url, [:url]
  end
end
