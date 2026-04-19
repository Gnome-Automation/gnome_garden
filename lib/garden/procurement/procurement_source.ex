defmodule GnomeGarden.Procurement.ProcurementSource do
  @moduledoc """
  Universal monitored URL.

  Every URL we check periodically — whether it's a government procurement
  portal, a company website, a job board, or an industry directory. The
  `source_type` determines which scanner strategy to use.

  ## Source Types & Scanners

  | Type | Scanner | What it finds |
  |------|---------|---------------|
  | planetbids, opengov, bidnet, cal_eprocure, utility, school, port, custom | ListingScanner | Bids/RFPs |
  | company_site | SiteScanner | Contacts, hiring signals, news |
  | sam_gov | SAM.gov API (future) | Federal opportunities |
  | job_board | JobScanner (future) | Hiring signals |
  | directory | DirectoryScanner (future) | Company listings |

  ## State Machine

      found ──→ pending ──→ configured ──→ scanning (loops on cron)
                  │              │              │
                  ▼              ▼              ▼
             config_failed   scan_failed    (loops)
                  │              │
                  ▼              ▼
              pending        configured (retry)
                  │
                  ▼
               manual

  Company sites can be created directly in `:configured` state since they
  don't need CSS selector discovery.
  """

  use Ash.Resource,
    otp_app: :gnome_garden,
    domain: GnomeGarden.Procurement,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshOban, AshStateMachine],
    notifiers: [Ash.Notifier.PubSub]

  postgres do
    table "lead_sources"
    repo GnomeGarden.Repo

    references do
      reference :organization, on_delete: :nilify
    end
  end

  oban do
    triggers do
      trigger :scheduled_scan do
        action :scan
        scheduler_cron "0 */6 * * *"
        worker_module_name __MODULE__.AshOban.Worker.ScheduledScan
        scheduler_module_name __MODULE__.AshOban.Scheduler.ScheduledScan
        queue :lead_scanning
        max_attempts 3

        where expr(
                enabled == true and
                  status == :approved and
                  config_status == :configured and
                  (is_nil(last_scanned_at) or
                     last_scanned_at < ago(scan_frequency_hours, :hour))
              )
      end
    end
  end

  state_machine do
    state_attribute :config_status
    initial_states [:found, :configured]
    default_initial_state :found

    transitions do
      transition :queue, from: [:found], to: :pending
      transition :configure, from: [:found, :pending, :config_failed, :manual], to: :configured
      transition :config_fail, from: [:found, :pending], to: :config_failed
      transition :scan, from: [:configured, :scan_failed], to: :configured
      transition :scan_fail, from: [:configured], to: :scan_failed
      transition :retry_config, from: [:config_failed], to: :pending
      transition :retry_scan, from: [:scan_failed], to: :configured
      transition :set_manual, from: [:found, :pending, :config_failed], to: :manual
    end
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true

      accept [
        :name,
        :url,
        :source_type,
        :portal_id,
        :region,
        :priority,
        :api_available,
        :requires_login,
        :scrape_selector,
        :scan_frequency_hours,
        :enabled,
        :metadata,
        :added_by,
        :notes,
        :organization_id,
        :status
      ]
    end

    create :create_for_organization do
      description "Create a pre-configured source for an organization website"

      accept [
        :name,
        :url,
        :source_type,
        :region,
        :priority,
        :scan_frequency_hours,
        :enabled,
        :notes,
        :organization_id
      ]

      change set_attribute(:config_status, :configured)
      change set_attribute(:configured_at, &DateTime.utc_now/0)
      change set_attribute(:added_by, :agent)
      change set_attribute(:status, :approved)
    end

    update :update do
      accept [
        :name,
        :url,
        :organization_id,
        :priority,
        :enabled,
        :scan_frequency_hours,
        :scrape_selector,
        :scrape_config,
        :metadata,
        :last_scanned_at,
        :status
      ]
    end

    update :approve do
      description "Approve this source for configuration and scanning"
      accept []
      change set_attribute(:status, :approved)
      change set_attribute(:enabled, true)
    end

    update :ignore do
      description "Ignore this source without scanning it"
      accept []
      change set_attribute(:status, :ignored)
      change set_attribute(:enabled, false)
    end

    update :block do
      description "Block this source from future scanning"
      accept []
      change set_attribute(:status, :blocked)
      change set_attribute(:enabled, false)
    end

    update :reconsider do
      description "Move this source back into the candidate pool"
      accept []
      change set_attribute(:status, :candidate)
      change set_attribute(:enabled, true)
    end

    # State transitions

    update :queue do
      description "Queue source for SmartScanner configuration"
      accept []
      change transition_state(:pending)
    end

    update :configure do
      description "Save discovered scraping configuration"
      accept [:scrape_config]
      change transition_state(:configured)
      change set_attribute(:configured_at, &DateTime.utc_now/0)
    end

    update :config_fail do
      accept []
      change transition_state(:config_failed)
    end

    update :scan do
      description "Run scanner on this source (routed by source_type)"
      require_atomic? false
      accept []
      change transition_state(:configured)

      change fn changeset, _ctx ->
        changeset
        |> Ash.Changeset.after_action(fn _changeset, record ->
          Task.start(fn ->
            GnomeGarden.Agents.Procurement.ScannerRouter.scan(record)
          end)

          {:ok, record}
        end)
      end
    end

    update :scan_fail do
      accept []
      change transition_state(:scan_failed)
    end

    update :retry_config do
      accept []
      change transition_state(:pending)
      change set_attribute(:scrape_config, %{})
      change set_attribute(:configured_at, nil)
    end

    update :retry_scan do
      accept []
      change transition_state(:configured)
    end

    update :set_manual do
      accept [:scrape_config]
      change transition_state(:manual)
      change set_attribute(:configured_at, &DateTime.utc_now/0)
    end

    update :mark_scanned do
      accept []
      change set_attribute(:last_scanned_at, &DateTime.utc_now/0)
    end

    # Reads

    read :needs_configuration do
      description "Sources needing scrape config discovery"

      filter expr(
               enabled == true and
                 status == :approved and
                 requires_login == false and
                 config_status in [:found, :pending]
             )
    end

    read :ready_for_scan do
      description "Configured sources due for scanning"
      argument :since_hours, :integer, default: 24

      filter expr(
               enabled == true and
                 status == :approved and
                 config_status == :configured and
                 (is_nil(last_scanned_at) or last_scanned_at < ago(^arg(:since_hours), :hour))
             )
    end

    read :by_type do
      argument :source_type, :atom, allow_nil?: false
      filter expr(source_type == ^arg(:source_type) and enabled == true and status == :approved)
    end

    read :by_region do
      argument :region, :atom, allow_nil?: false
      filter expr(region == ^arg(:region) and enabled == true and status == :approved)
    end

    read :by_url do
      argument :url, :string, allow_nil?: false
      get_by [:url]
    end

    read :by_organization do
      argument :organization_id, :uuid, allow_nil?: false
      filter expr(organization_id == ^arg(:organization_id))
    end

    read :failed do
      filter expr(config_status in [:config_failed, :scan_failed])
    end

    read :console do
      prepare build(
                sort: [updated_at: :desc, inserted_at: :desc],
                load: [:status_variant, :config_status_variant, :enabled_variant]
              )
    end
  end

  pub_sub do
    module GnomeGardenWeb.Endpoint
    prefix "procurement_source"

    publish :configure, "configured"
    publish :config_fail, "config_failed"
    publish :scan, "scanned"
    publish :scan_fail, "scan_failed"
    publish :mark_scanned, "scanned"
    publish :queue, "queued"
  end

  attributes do
    uuid_primary_key :id

    attribute :name, :string, allow_nil?: false, public?: true
    attribute :url, :string, allow_nil?: false, public?: true

    attribute :source_type, :atom,
      allow_nil?: false,
      public?: true,
      constraints: [
        one_of: [
          :planetbids,
          :opengov,
          :bidnet,
          :sam_gov,
          :cal_eprocure,
          :utility,
          :school,
          :port,
          :custom,
          :company_site,
          :job_board,
          :directory
        ]
      ]

    attribute :portal_id, :string,
      public?: true,
      description: "External portal ID (e.g., PlanetBids portal number)"

    attribute :region, :atom,
      default: :socal,
      public?: true,
      constraints: [one_of: [:oc, :la, :ie, :sd, :socal, :norcal, :ca, :national]]

    attribute :priority, :atom,
      default: :medium,
      public?: true,
      constraints: [one_of: [:high, :medium, :low]]

    attribute :api_available, :boolean, default: false, public?: true
    attribute :requires_login, :boolean, default: false, public?: true

    attribute :scrape_selector, :string,
      public?: true,
      description: "CSS selector for bid listings if scraping"

    attribute :scrape_config, :map,
      default: %{},
      public?: true,
      description: "CSS selectors for deterministic scanning (procurement sources)"

    attribute :config_status, :atom,
      default: :found,
      allow_nil?: false,
      public?: true,
      constraints: [
        one_of: [:found, :pending, :configured, :config_failed, :scan_failed, :manual]
      ]

    attribute :status, :atom do
      allow_nil? false
      default :candidate
      public? true
      constraints one_of: [:candidate, :approved, :ignored, :blocked]
    end

    attribute :configured_at, :utc_datetime do
      public? true
      description "When scrape config was saved or source was marked ready"
    end

    attribute :last_scanned_at, :utc_datetime, public?: true
    attribute :scan_frequency_hours, :integer, default: 24, public?: true
    attribute :enabled, :boolean, default: true, public?: true

    attribute :metadata, :map,
      default: %{},
      public?: true,
      description: "Additional config: API keys, endpoints, etc."

    attribute :added_by, :atom,
      public?: true,
      constraints: [one_of: [:manual, :agent, :import]],
      description: "How this source was added"

    attribute :notes, :string, public?: true

    timestamps()
  end

  relationships do
    belongs_to :organization, GnomeGarden.Operations.Organization do
      public? true
      description "Organization this source belongs to (for company_site type)"
    end
  end

  calculations do
    calculate :status_variant,
              :atom,
              {GnomeGarden.Calculations.EnumVariant,
               field: :status,
               mapping: [
                 candidate: :warning,
                 approved: :success,
                 ignored: :default,
                 blocked: :error
               ],
               default: :default}

    calculate :config_status_variant,
              :atom,
              {GnomeGarden.Calculations.EnumVariant,
               field: :config_status,
               mapping: [
                 found: :default,
                 pending: :warning,
                 configured: :success,
                 config_failed: :error,
                 scan_failed: :error,
                 manual: :info
               ],
               default: :default}

    calculate :enabled_variant,
              :atom,
              {GnomeGarden.Calculations.EnumVariant,
               field: :enabled,
               mapping: [
                 true: :success,
                 false: :default
               ],
               default: :default}
  end

  identities do
    identity :unique_url, [:url]
  end

  @doc "Returns the scanner strategy for a given source type atom."
  def scanner_strategy(source_type) when is_atom(source_type) do
    case source_type do
      t
      when t in [:planetbids, :opengov, :bidnet, :cal_eprocure, :utility, :school, :port, :custom] ->
        :deterministic

      :company_site ->
        :company

      :sam_gov ->
        :sam_gov_api

      :job_board ->
        :job

      :directory ->
        :directory
    end
  end
end
