defmodule GnomeGarden.Agents.LeadSource do
  @moduledoc """
  Universal monitored URL.

  Every URL we check periodically — whether it's a government procurement
  portal, a company website, a job board, or an industry directory. The
  `source_type` determines which scanner strategy to use.

  ## Source Types & Scanners

  | Type | Scanner | What it finds |
  |------|---------|---------------|
  | planetbids, opengov, cal_eprocure, utility, school, port, custom | DeterministicScanner | Bids/RFPs |
  | company_site | CompanyScanner | Contacts, hiring signals, news |
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
    domain: GnomeGarden.Agents,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshOban, AshStateMachine],
    notifiers: [Ash.Notifier.PubSub]

  postgres do
    table "lead_sources"
    repo GnomeGarden.Repo
  end

  oban do
    triggers do
      trigger :scheduled_scan do
        action :scan
        scheduler_cron "0 */6 * * *"
        queue :lead_scanning
        max_attempts 3

        where expr(
                enabled == true and
                  config_status == :configured and
                  (is_nil(last_scanned_at) or
                     last_scanned_at < ago(scan_frequency_hours, :hour))
              )
      end
    end
  end

  state_machine do
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
        :company_id
      ]
    end

    create :create_for_company do
      description "Create a pre-configured source for a company website"

      accept [
        :name,
        :url,
        :source_type,
        :region,
        :priority,
        :scan_frequency_hours,
        :enabled,
        :notes,
        :company_id
      ]

      change set_attribute(:config_status, :configured)
      change set_attribute(:configured_at, &DateTime.utc_now/0)
      change set_attribute(:added_by, :agent)
    end

    update :update do
      accept [
        :name,
        :url,
        :priority,
        :enabled,
        :scan_frequency_hours,
        :scrape_selector,
        :scrape_config,
        :metadata,
        :last_scanned_at
      ]
    end

    # State transitions

    update :queue do
      description "Queue source for SmartScanner configuration"
      accept []
    end

    update :configure do
      description "Save discovered scraping configuration"
      accept [:scrape_config]
      change set_attribute(:configured_at, &DateTime.utc_now/0)
    end

    update :config_fail do
      accept []
    end

    update :scan do
      description "Run scanner on this source (routed by source_type)"
      accept []

      change fn changeset, _ctx ->
        changeset
        |> Ash.Changeset.after_action(fn _changeset, record ->
          Task.start(fn ->
            GnomeGarden.Agents.ScannerRouter.scan(record)
          end)

          {:ok, record}
        end)
      end
    end

    update :scan_fail do
      accept []
    end

    update :retry_config do
      accept []
      change set_attribute(:scrape_config, %{})
      change set_attribute(:configured_at, nil)
    end

    update :retry_scan do
      accept []
    end

    update :set_manual do
      accept [:scrape_config]
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
                 requires_login == false and
                 config_status in [:found, :pending]
             )
    end

    read :ready_for_scan do
      description "Configured sources due for scanning"
      argument :since_hours, :integer, default: 24

      filter expr(
               enabled == true and
                 config_status == :configured and
                 (is_nil(last_scanned_at) or last_scanned_at < ago(^arg(:since_hours), :hour))
             )
    end

    read :by_type do
      argument :source_type, :atom, allow_nil?: false
      filter expr(source_type == ^arg(:source_type) and enabled == true)
    end

    read :by_region do
      argument :region, :atom, allow_nil?: false
      filter expr(region == ^arg(:region) and enabled == true)
    end

    read :by_company do
      argument :company_id, :uuid, allow_nil?: false
      filter expr(company_id == ^arg(:company_id))
    end

    read :failed do
      filter expr(config_status in [:config_failed, :scan_failed])
    end
  end

  pub_sub do
    module GnomeGardenWeb.Endpoint
    prefix "lead_source"

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
      public?: true,
      constraints: [
        one_of: [:found, :pending, :configured, :config_failed, :scan_failed, :manual]
      ]

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
    belongs_to :company, GnomeGarden.Sales.Company do
      public? true
      description "Company this source belongs to (for company_site type)"
    end
  end

  identities do
    identity :unique_url, [:url]
  end

  @doc "Returns the scanner strategy for a given source type atom."
  def scanner_strategy(source_type) when is_atom(source_type) do
    case source_type do
      t when t in [:planetbids, :opengov, :cal_eprocure, :utility, :school, :port, :custom] ->
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
