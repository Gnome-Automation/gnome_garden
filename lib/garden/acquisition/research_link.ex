defmodule GnomeGarden.Acquisition.ResearchLink do
  @moduledoc """
  Join resource linking ResearchRequests to any entity.

  Enables a research request to be linked to multiple bids, organizations,
  people, events, or discovery records. Each link carries optional
  context explaining the connection.
  """

  use Ash.Resource,
    otp_app: :gnome_garden,
    domain: GnomeGarden.Acquisition,
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
        :organization_id,
        :person_id,
        :event_id,
        :discovery_record_id
      ]
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :context, :string do
      public? true
      description "Why this research is linked to this entity"
    end

    attribute :discovery_record_id, :uuid do
      public? true
    end

    timestamps()
  end

  relationships do
    belongs_to :research_request, GnomeGarden.Acquisition.ResearchRequest do
      allow_nil? false
      public? true
    end

    belongs_to :bid, GnomeGarden.Procurement.Bid do
      public? true
    end

    belongs_to :organization, GnomeGarden.Operations.Organization do
      public? true
    end

    belongs_to :person, GnomeGarden.Operations.Person do
      public? true
    end

    belongs_to :event, GnomeGarden.Commercial.Event do
      public? true
    end

    belongs_to :discovery_record, GnomeGarden.Commercial.DiscoveryRecord do
      source_attribute :discovery_record_id
      public? true
    end
  end
end
