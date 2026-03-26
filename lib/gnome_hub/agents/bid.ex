defmodule GnomeHub.Agents.Bid do
  @moduledoc """
  Discovered bid/RFP opportunity.

  Stores procurement opportunities found by the BidScanner agent,
  including scoring based on service match, geography, value, and tech fit.
  """

  use Ash.Resource,
    otp_app: :gnome_hub,
    domain: GnomeHub.Agents,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "bids"
    repo GnomeHub.Repo
  end

  attributes do
    uuid_primary_key :id

    attribute :title, :string, allow_nil?: false, public?: true
    attribute :description, :string, public?: true
    attribute :external_id, :string, public?: true, description: "ID from the source system"

    attribute :url, :string, allow_nil?: false, public?: true
    attribute :source_url, :string, public?: true, description: "URL of the lead source that found this"

    attribute :agency, :string, public?: true
    attribute :location, :string, public?: true
    attribute :region, :atom,
      public?: true,
      constraints: [one_of: [:oc, :la, :ie, :sd, :socal, :norcal, :ca, :national, :other]]

    attribute :status, :atom,
      default: :new,
      public?: true,
      constraints: [one_of: [:new, :reviewing, :pursuing, :submitted, :won, :lost, :expired, :rejected]]

    # Dates
    attribute :posted_at, :utc_datetime, public?: true
    attribute :due_at, :utc_datetime, public?: true
    attribute :discovered_at, :utc_datetime, public?: true

    # Value
    attribute :estimated_value, :decimal, public?: true
    attribute :value_range, :string, public?: true, description: "e.g., '$100K-$500K'"

    # Scoring (based on lead-scoring rubric from target-customers.md)
    attribute :score_service_match, :integer, default: 0, public?: true,
      description: "0-30: SCADA/PLC/controls = 30, adjacent = 15, unrelated = 0"
    attribute :score_geography, :integer, default: 0, public?: true,
      description: "0-20: SoCal = 20, NorCal = 12, Other CA = 8, Out of state = 0"
    attribute :score_value, :integer, default: 0, public?: true,
      description: "0-20: >$500K = 20, $100-500K = 15, $50-100K = 10, <$50K = 5"
    attribute :score_tech_fit, :integer, default: 0, public?: true,
      description: "0-15: Rockwell/Siemens/Ignition = 15, Other industrial = 10, IT = 5"
    attribute :score_industry, :integer, default: 0, public?: true,
      description: "0-10: Water/biotech/brewery = 10, Food/pharma = 7, Other mfg = 4"
    attribute :score_opportunity_type, :integer, default: 0, public?: true,
      description: "0-5: Direct RFP = 5, Subcontract = 3, Long-shot = 1"
    attribute :score_total, :integer, default: 0, public?: true,
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
    attribute :assigned_to, :string, public?: true

    attribute :metadata, :map, default: %{}, public?: true

    timestamps()
  end

  relationships do
    belongs_to :lead_source, GnomeHub.Agents.LeadSource, public?: true
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true
      accept [:title, :description, :external_id, :url, :source_url, :agency,
              :location, :region, :posted_at, :due_at, :estimated_value, :value_range,
              :score_service_match, :score_geography, :score_value, :score_tech_fit,
              :score_industry, :score_opportunity_type, :score_total, :score_tier,
              :keywords_matched, :keywords_rejected, :metadata, :lead_source_id]

      change set_attribute(:discovered_at, &DateTime.utc_now/0)
      change set_attribute(:status, :new)
    end

    update :update do
      accept [:status, :notes, :assigned_to, :metadata]
    end

    update :score do
      accept [:score_service_match, :score_geography, :score_value, :score_tech_fit,
              :score_industry, :score_opportunity_type]

      change fn changeset, _ctx ->
        # Calculate total and tier
        total =
          (Ash.Changeset.get_attribute(changeset, :score_service_match) || 0) +
          (Ash.Changeset.get_attribute(changeset, :score_geography) || 0) +
          (Ash.Changeset.get_attribute(changeset, :score_value) || 0) +
          (Ash.Changeset.get_attribute(changeset, :score_tech_fit) || 0) +
          (Ash.Changeset.get_attribute(changeset, :score_industry) || 0) +
          (Ash.Changeset.get_attribute(changeset, :score_opportunity_type) || 0)

        tier = cond do
          total >= 75 -> :hot
          total >= 50 -> :warm
          true -> :prospect
        end

        changeset
        |> Ash.Changeset.change_attribute(:score_total, total)
        |> Ash.Changeset.change_attribute(:score_tier, tier)
      end
    end

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
  end

  identities do
    identity :unique_url, [:url]
  end
end
