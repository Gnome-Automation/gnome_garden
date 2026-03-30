defmodule GnomeGarden.Agents.LeadSource do
  @moduledoc """
  Lead source for bid scanning.

  Stores procurement portals, APIs, and other sources that the
  BidScanner agent monitors for new opportunities.
  """

  use Ash.Resource,
    otp_app: :gnome_garden,
    domain: GnomeGarden.Agents,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "lead_sources"
    repo GnomeGarden.Repo
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
        :discovered_by,
        :discovery_notes
      ]
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
        :last_scanned_at,
        :discovery_status,
        :discovered_at
      ]
    end

    update :mark_scanned do
      accept []
      change set_attribute(:last_scanned_at, &DateTime.utc_now/0)
    end

    update :save_discovery do
      description "Save discovered scraping configuration from SmartScanner"
      accept [:scrape_config]
      change set_attribute(:discovery_status, :discovered)
      change set_attribute(:discovered_at, &DateTime.utc_now/0)
    end

    update :mark_discovery_failed do
      accept []
      change set_attribute(:discovery_status, :failed)
    end

    read :due_for_scan do
      argument :since_hours, :integer, default: 24

      filter expr(
               enabled == true and
                 (is_nil(last_scanned_at) or
                    last_scanned_at < ago(^arg(:since_hours), :hour))
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

    read :needs_discovery do
      description "Find sources that need discovery (no scrape_config yet)"

      filter expr(
               enabled == true and
                 requires_login == false and
                 discovery_status == :pending
             )
    end

    read :ready_for_scan do
      description "Find sources with discovered config ready for deterministic scanning"

      filter expr(
               enabled == true and
                 discovery_status == :discovered and
                 (is_nil(last_scanned_at) or last_scanned_at < ago(^arg(:since_hours), :hour))
             )

      argument :since_hours, :integer, default: 24
    end
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
          :custom
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

    # Discovered scraping configuration (populated by SmartScanner)
    attribute :scrape_config, :map,
      default: %{},
      public?: true,
      description: """
      Discovered scraping configuration:
      - listing_selector: CSS selector for bid rows
      - title_selector: CSS selector for title within row
      - date_selector: CSS selector for due date
      - link_selector: CSS selector for detail link
      - pagination: %{type: :numbered | :load_more | :infinite, selector: "..."}
      - search_enabled: boolean
      - search_selector: CSS selector for search input
      """

    attribute :discovery_status, :atom,
      default: :pending,
      public?: true,
      constraints: [one_of: [:pending, :discovered, :failed, :manual]]

    attribute :discovered_at, :utc_datetime, public?: true

    attribute :last_scanned_at, :utc_datetime, public?: true
    attribute :scan_frequency_hours, :integer, default: 24, public?: true
    attribute :enabled, :boolean, default: true, public?: true

    attribute :metadata, :map,
      default: %{},
      public?: true,
      description: "Additional config: API keys, endpoints, etc."

    attribute :discovered_by, :atom,
      public?: true,
      constraints: [one_of: [:manual, :agent, :import]],
      description: "How this source was added"

    attribute :discovery_notes, :string, public?: true

    timestamps()
  end

  identities do
    identity :unique_url, [:url]
  end
end
