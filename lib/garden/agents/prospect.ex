defmodule GnomeGarden.Agents.Prospect do
  @moduledoc """
  Prospect company for sales outreach.

  Stores companies discovered through various signals:
  - Job postings for controls engineers
  - Facility expansions
  - Legacy system indicators
  - Industry/trade news
  """

  use Ash.Resource,
    otp_app: :gnome_garden,
    domain: GnomeGarden.Agents,
    data_layer: AshPostgres.DataLayer,
    notifiers: [Ash.Notifier.PubSub]

  postgres do
    table "prospects"
    repo GnomeGarden.Repo
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
        :size,
        :signals,
        :signal_strength,
        :tech_indicators,
        :discovered_via,
        :discovery_url,
        :notes,
        :metadata
      ]

      change set_attribute(:discovered_at, &DateTime.utc_now/0)
      change set_attribute(:status, :researched)
    end

    update :update do
      accept [
        :status,
        :signals,
        :signal_strength,
        :tech_indicators,
        :contacts,
        :notes,
        :next_action,
        :next_action_date,
        :metadata,
        :converted_organization_id,
        :converted_signal_id
      ]
    end

    update :convert_to_organization do
      description "Link prospect to an organization when it converts into durable operating data"
      argument :organization_id, :uuid, allow_nil?: false
      change set_attribute(:converted_organization_id, arg(:organization_id))
      change set_attribute(:status, :contacted)
    end

    update :convert_to_signal do
      description "Link prospect to a commercial signal for human review"
      argument :signal_id, :uuid, allow_nil?: false
      change set_attribute(:converted_signal_id, arg(:signal_id))
      change set_attribute(:status, :contacted)
    end

    update :add_contact do
      require_atomic? false
      argument :contact, :map, allow_nil?: false

      change fn changeset, _ctx ->
        contact = Ash.Changeset.get_argument(changeset, :contact)
        existing = Ash.Changeset.get_attribute(changeset, :contacts) || []
        Ash.Changeset.change_attribute(changeset, :contacts, existing ++ [contact])
      end
    end

    update :add_signal do
      require_atomic? false
      argument :signal, :string, allow_nil?: false

      change fn changeset, _ctx ->
        signal = Ash.Changeset.get_argument(changeset, :signal)
        existing = Ash.Changeset.get_attribute(changeset, :signals) || []

        if signal in existing do
          changeset
        else
          Ash.Changeset.change_attribute(changeset, :signals, existing ++ [signal])
        end
      end
    end

    read :by_industry do
      argument :industry, :atom, allow_nil?: false
      filter expr(industry == ^arg(:industry) and status not in [:lost, :dormant])
    end

    read :by_region do
      argument :region, :atom, allow_nil?: false
      filter expr(region == ^arg(:region) and status not in [:lost, :dormant])
    end

    read :strong_signals do
      filter expr(signal_strength == :strong and status in [:researched, :contacted])
    end

    read :needs_followup do
      filter expr(
               not is_nil(next_action_date) and
                 next_action_date <= ^Date.utc_today() and
                 status not in [:won, :lost, :dormant]
             )
    end

    read :active do
      filter expr(status not in [:won, :lost, :dormant])
    end

    read :needs_review do
      filter expr(status == :researched)
      prepare build(sort: [signal_strength: :desc, inserted_at: :desc])
    end

    update :reject do
      accept [:notes]
      change set_attribute(:status, :lost)
    end
  end

  pub_sub do
    module GnomeGardenWeb.Endpoint
    prefix "prospect"

    publish :create, "created"
    publish :update, "updated"
    publish :reject, "rejected"
  end

  attributes do
    uuid_primary_key :id

    attribute :name, :string, allow_nil?: false, public?: true
    attribute :website, :string, public?: true
    attribute :location, :string, public?: true

    attribute :region, :atom,
      public?: true,
      constraints: [one_of: [:oc, :la, :ie, :sd, :socal, :norcal, :ca, :national, :other]]

    attribute :industry, :atom,
      public?: true,
      constraints: [
        one_of: [
          :brewery,
          :food_bev,
          :biotech,
          :pharma,
          :water,
          :wastewater,
          :packaging,
          :warehouse,
          :plastics,
          :aerospace,
          :cosmetics,
          :other
        ]
      ]

    attribute :size, :atom,
      public?: true,
      constraints: [one_of: [:small, :medium, :large, :enterprise]],
      description: "small (<50), medium (50-200), large (200-500), enterprise (500+)"

    attribute :status, :atom,
      default: :researched,
      public?: true,
      constraints: [one_of: [:researched, :contacted, :meeting, :proposal, :won, :lost, :dormant]]

    # Signals that indicate they need help
    attribute :signals, {:array, :string},
      default: [],
      public?: true,
      description: "e.g., 'hiring_controls_engineer', 'legacy_plc', 'expansion'"

    attribute :signal_strength, :atom,
      default: :medium,
      public?: true,
      constraints: [one_of: [:strong, :medium, :weak]]

    # Tech stack indicators
    attribute :tech_indicators, {:array, :string},
      default: [],
      public?: true,
      description: "e.g., 'Rockwell', 'Ignition', 'SLC 500', 'PanelView Plus 6'"

    # Contacts
    attribute :contacts, {:array, :map},
      default: [],
      public?: true,
      description: "List of contact info: [{name, title, email, linkedin}]"

    # Discovery
    attribute :discovered_via, :string,
      public?: true,
      description: "How we found them: 'job_post', 'bid', 'news', 'directory', 'referral'"

    attribute :discovered_at, :utc_datetime, public?: true
    attribute :discovery_url, :string, public?: true

    attribute :notes, :string, public?: true
    attribute :next_action, :string, public?: true
    attribute :next_action_date, :date, public?: true

    attribute :metadata, :map, default: %{}, public?: true

    timestamps()
  end

  relationships do
    belongs_to :converted_organization, GnomeGarden.Operations.Organization do
      public? true
      description "Organization created or linked when prospect converts"
    end

    belongs_to :converted_signal, GnomeGarden.Commercial.Signal do
      public? true
      description "Commercial signal created when prospect needs human review"
    end
  end

  identities do
    identity :unique_name_location, [:name, :location]
  end
end
