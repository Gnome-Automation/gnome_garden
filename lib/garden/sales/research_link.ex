defmodule GnomeGarden.Sales.ResearchLink do
  @moduledoc """
  Join resource linking ResearchRequests to any entity.

  Enables a research request to be linked to multiple bids, companies,
  opportunities, events, leads, or prospects. Each link carries optional
  context explaining the connection.
  """

  use Ash.Resource,
    otp_app: :gnome_garden,
    domain: GnomeGarden.Sales,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "research_links"
    repo GnomeGarden.Repo
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true

      accept [
        :context,
        :research_request_id,
        :bid_id,
        :company_id,
        :opportunity_id,
        :event_id,
        :lead_id,
        :prospect_id
      ]
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :context, :string do
      public? true
      description "Why this research is linked to this entity"
    end

    timestamps()
  end

  relationships do
    belongs_to :research_request, GnomeGarden.Sales.ResearchRequest do
      allow_nil? false
      public? true
    end

    belongs_to :bid, GnomeGarden.Procurement.Bid do
      public? true
    end

    belongs_to :company, GnomeGarden.Sales.Company do
      public? true
    end

    belongs_to :opportunity, GnomeGarden.Sales.Opportunity do
      public? true
    end

    belongs_to :event, GnomeGarden.Sales.Event do
      public? true
    end

    belongs_to :lead, GnomeGarden.Sales.Lead do
      public? true
    end

    belongs_to :prospect, GnomeGarden.Agents.Prospect do
      public? true
    end
  end
end
