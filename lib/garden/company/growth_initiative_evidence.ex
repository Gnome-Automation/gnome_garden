defmodule GnomeGarden.Company.GrowthInitiativeEvidence do
  @moduledoc """
  One piece of evidence supporting a growth initiative.

  Explicit rows, never metadata arrays: many bids can support one initiative
  and one bid can expose several gaps. Each row records what the bid asked
  for, what Gnome had, and how confident the observation is.
  """

  use Ash.Resource,
    otp_app: :gnome_garden,
    domain: GnomeGarden.Company,
    data_layer: AshPostgres.DataLayer,
    notifiers: [Ash.Notifier.PubSub]

  postgres do
    table "company_growth_initiative_evidence"
    repo GnomeGarden.Repo

    references do
      reference :growth_initiative, on_delete: :delete
      reference :bid, on_delete: :nilify
      reference :finding, on_delete: :nilify
      reference :created_by_team_member, on_delete: :nilify
    end
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true

      accept [
        :growth_initiative_id,
        :bid_id,
        :finding_id,
        :gap_category,
        :quoted_requirement,
        :observed_value,
        :required_value,
        :confidence,
        :note
      ]

      change GnomeGarden.Company.Changes.StampInitiativeActors
    end

    read :for_initiative do
      argument :growth_initiative_id, :uuid, allow_nil?: false
      filter expr(growth_initiative_id == ^arg(:growth_initiative_id))
      prepare build(sort: [inserted_at: :desc], load: [bid: [:title], finding: [:title]])
    end
  end

  pub_sub do
    module GnomeGardenWeb.Endpoint
    prefix "growth_initiative_evidence"

    publish_all :create, ["initiative", :growth_initiative_id]
    publish_all :destroy, ["initiative", :growth_initiative_id]
  end

  attributes do
    uuid_primary_key :id

    attribute :gap_category, :atom do
      allow_nil? false
      default :other
      public? true

      constraints one_of: [
                    :missing_certification,
                    :bond_capacity,
                    :license_class,
                    :insurance_limit,
                    :tech_platform,
                    :other
                  ]
    end

    attribute :quoted_requirement, :string do
      public? true
    end

    attribute :observed_value, :string do
      public? true
    end

    attribute :required_value, :string do
      public? true
    end

    attribute :confidence, :atom do
      allow_nil? false
      default :medium
      public? true
      constraints one_of: [:low, :medium, :high]
    end

    attribute :note, :string do
      public? true
    end

    timestamps()
  end

  relationships do
    belongs_to :growth_initiative, GnomeGarden.Company.GrowthInitiative do
      allow_nil? false
      public? true
    end

    belongs_to :bid, GnomeGarden.Procurement.Bid do
      public? true
    end

    belongs_to :finding, GnomeGarden.Acquisition.Finding do
      public? true
    end

    belongs_to :created_by_team_member, GnomeGarden.Operations.TeamMember do
      public? true
    end
  end
end
