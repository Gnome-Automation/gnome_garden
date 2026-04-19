defmodule GnomeGarden.Procurement.Bid do
  @moduledoc """
  Discovered bid/RFP opportunity.

  Stores procurement opportunities found by the BidScanner agent,
  including scoring based on service match, geography, value, and tech fit.
  """

  use Ash.Resource,
    otp_app: :gnome_garden,
    domain: GnomeGarden.Procurement,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshJido, AshStateMachine],
    notifiers: [AshJido.Notifier, Ash.Notifier.PubSub]

  postgres do
    table "bids"
    repo GnomeGarden.Repo

    references do
      reference :signal, on_delete: :nilify
      reference :organization, on_delete: :nilify
    end
  end

  jido do
    signal_bus(GnomeGarden.SignalBus)

    publish :create, "procurement.bid.created", include: :all
    publish :score, "procurement.bid.scored", include: :all
  end

  state_machine do
    initial_states [:new]
    default_initial_state :new
    state_attribute :status

    transitions do
      transition :start_review, from: :new, to: :reviewing
      transition :pursue, from: [:new, :reviewing], to: :pursuing
      transition :submit, from: :pursuing, to: :submitted
      transition :mark_won, from: :submitted, to: :won
      transition :mark_lost, from: [:submitted, :pursuing], to: :lost
      transition :reject, from: [:new, :reviewing], to: :rejected
      transition :park, from: [:new, :reviewing], to: :parked
      transition :unpark, from: :parked, to: :new
      transition :expire, from: :*, to: :expired
    end
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true

      accept [
        :title,
        :description,
        :external_id,
        :bid_type,
        :url,
        :source_url,
        :agency,
        :location,
        :region,
        :posted_at,
        :due_at,
        :estimated_value,
        :value_range,
        :score_service_match,
        :score_geography,
        :score_value,
        :score_tech_fit,
        :score_industry,
        :score_opportunity_type,
        :score_total,
        :score_tier,
        :keywords_matched,
        :keywords_rejected,
        :metadata,
        :procurement_source_id
      ]

      change set_attribute(:discovered_at, &DateTime.utc_now/0)
      change {GnomeGarden.Procurement.Changes.CreateSignalForBid, []}
    end

    update :update do
      accept [:description, :bid_type, :due_at, :notes, :metadata, :owner_id, :organization_id]
    end

    update :link_signal do
      accept []
      argument :signal_id, :uuid, allow_nil?: false
      change set_attribute(:signal_id, arg(:signal_id))
    end

    update :link_organization do
      accept []
      argument :organization_id, :uuid, allow_nil?: false
      change set_attribute(:organization_id, arg(:organization_id))
    end

    # -- State transitions --

    update :start_review do
      accept []
      change transition_state(:reviewing)
    end

    update :pursue do
      accept []
      change transition_state(:pursuing)
    end

    update :submit do
      accept []
      change transition_state(:submitted)
    end

    update :mark_won do
      accept []
      change transition_state(:won)
    end

    update :mark_lost do
      accept [:notes]
      change transition_state(:lost)
    end

    update :reject do
      accept [:notes]
      change transition_state(:rejected)
    end

    update :park do
      accept [:notes]
      change transition_state(:parked)
    end

    update :unpark do
      accept []
      change transition_state(:new)
    end

    update :expire do
      accept []
      change transition_state(:expired)
    end

    update :score do
      require_atomic? false

      accept [
        :score_service_match,
        :score_geography,
        :score_value,
        :score_tech_fit,
        :score_industry,
        :score_opportunity_type
      ]

      change fn changeset, _ctx ->
        total =
          (Ash.Changeset.get_attribute(changeset, :score_service_match) || 0) +
            (Ash.Changeset.get_attribute(changeset, :score_geography) || 0) +
            (Ash.Changeset.get_attribute(changeset, :score_value) || 0) +
            (Ash.Changeset.get_attribute(changeset, :score_tech_fit) || 0) +
            (Ash.Changeset.get_attribute(changeset, :score_industry) || 0) +
            (Ash.Changeset.get_attribute(changeset, :score_opportunity_type) || 0)

        tier =
          cond do
            total >= 75 -> :hot
            total >= 50 -> :warm
            true -> :prospect
          end

        changeset
        |> Ash.Changeset.change_attribute(:score_total, total)
        |> Ash.Changeset.change_attribute(:score_tier, tier)
      end
    end

    # -- Reads --

    read :hot do
      filter expr(score_tier == :hot and status in [:new, :reviewing])
    end

    read :warm do
      filter expr(score_tier == :warm and status in [:new, :reviewing])
    end

    read :due_soon do
      argument :days, :integer, default: 7

      filter expr(
               status in [:new, :reviewing, :pursuing] and
                 not is_nil(due_at) and
                 due_at < from_now(^arg(:days), :day)
             )
    end

    read :by_status do
      argument :status, :atom, allow_nil?: false
      filter expr(status == ^arg(:status))
    end

    read :needs_review do
      filter expr(status == :new)
      prepare build(sort: [score_total: :desc, inserted_at: :desc])
    end

    read :by_url do
      argument :url, :string, allow_nil?: false
      get_by [:url]
    end

    read :for_organization do
      argument :organization_id, :uuid, allow_nil?: false
      filter expr(organization_id == ^arg(:organization_id))
      prepare build(sort: [inserted_at: :desc], load: [:organization, :signal])
    end

    read :parked do
      filter expr(status == :parked)
      prepare build(sort: [updated_at: :desc])
    end
  end

  pub_sub do
    module GnomeGardenWeb.Endpoint
    prefix "bid"

    publish :create, "created"
    publish :update, "updated"
    publish :score, "scored"
  end

  attributes do
    uuid_primary_key :id

    attribute :title, :string, allow_nil?: false, public?: true
    attribute :description, :string, public?: true
    attribute :external_id, :string, public?: true, description: "ID from the source system"

    attribute :bid_type, :atom,
      public?: true,
      constraints: [one_of: [:rfi, :rfp, :rfq, :ifb, :soq, :other]],
      description: "RFI, RFP, RFQ, IFB, SOQ"

    attribute :url, :string, allow_nil?: false, public?: true

    attribute :source_url, :string,
      public?: true,
      description: "URL of the procurement source that found this"

    attribute :agency, :string, public?: true
    attribute :location, :string, public?: true

    attribute :region, :atom,
      public?: true,
      constraints: [one_of: [:oc, :la, :ie, :sd, :socal, :norcal, :ca, :national, :other]]

    attribute :status, :atom,
      allow_nil?: false,
      default: :new,
      public?: true,
      constraints: [
        one_of: [
          :new,
          :reviewing,
          :pursuing,
          :submitted,
          :won,
          :lost,
          :expired,
          :rejected,
          :parked
        ]
      ]

    # Dates
    attribute :posted_at, :utc_datetime, public?: true
    attribute :due_at, :utc_datetime, public?: true
    attribute :discovered_at, :utc_datetime, public?: true

    # Value
    attribute :estimated_value, :decimal, public?: true
    attribute :value_range, :string, public?: true, description: "e.g., '$100K-$500K'"

    # Scoring (based on lead-scoring rubric from target-customers.md)
    attribute :score_service_match, :integer,
      default: 0,
      public?: true,
      description: "0-30: SCADA/PLC/controls = 30, adjacent = 15, unrelated = 0"

    attribute :score_geography, :integer,
      default: 0,
      public?: true,
      description: "0-20: SoCal = 20, NorCal = 12, Other CA = 8, Out of state = 0"

    attribute :score_value, :integer,
      default: 0,
      public?: true,
      description: "0-20: >$500K = 20, $100-500K = 15, $50-100K = 10, <$50K = 5"

    attribute :score_tech_fit, :integer,
      default: 0,
      public?: true,
      description: "0-15: Rockwell/Siemens/Ignition = 15, Other industrial = 10, IT = 5"

    attribute :score_industry, :integer,
      default: 0,
      public?: true,
      description: "0-10: Water/biotech/brewery = 10, Food/pharma = 7, Other mfg = 4"

    attribute :score_opportunity_type, :integer,
      default: 0,
      public?: true,
      description: "0-5: Direct RFP = 5, Subcontract = 3, Long-shot = 1"

    attribute :score_total, :integer,
      default: 0,
      public?: true,
      description: "Sum of all scores (max 100)"

    attribute :score_tier, :atom,
      public?: true,
      constraints: [one_of: [:hot, :warm, :prospect]],
      description: "HOT (75+), WARM (50-74), PROSPECT (<50)"

    # Keywords matched
    attribute :keywords_matched, {:array, :string}, default: [], public?: true
    attribute :keywords_rejected, {:array, :string}, default: [], public?: true

    # Tracking
    attribute :notes, :string, public?: true

    attribute :metadata, :map, default: %{}, public?: true

    timestamps()
  end

  relationships do
    belongs_to :procurement_source, GnomeGarden.Procurement.ProcurementSource do
      public? true
    end

    belongs_to :owner, GnomeGarden.Accounts.User do
      public? true
      description "User assigned to this bid"
    end

    belongs_to :signal, GnomeGarden.Commercial.Signal do
      public? true
      description "Commercial signal created from this bid"
    end

    belongs_to :organization, GnomeGarden.Operations.Organization do
      public? true
      description "Durable organization record for the issuing agency or customer"
    end

    has_many :pursuits, GnomeGarden.Commercial.Pursuit do
      source_attribute :signal_id
      destination_attribute :signal_id
      public? true
      description "Commercial pursuits created from this bid's signal"
    end

    has_many :activities, GnomeGarden.Sales.Activity do
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
                 pursuing: :warning,
                 submitted: :info,
                 won: :success,
                 lost: :error,
                 expired: :warning,
                 rejected: :default,
                 parked: :warning
               ],
               default: :default}

    calculate :score_tier_variant,
              :atom,
              {GnomeGarden.Calculations.EnumVariant,
               field: :score_tier,
               mapping: [
                 hot: :error,
                 warm: :warning,
                 prospect: :info
               ],
               default: :default}
  end

  identities do
    identity :unique_url, [:url]
  end
end
