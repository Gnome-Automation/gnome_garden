defmodule GnomeGarden.Mercury.AliasEvent do
  @moduledoc """
  Audit log for client bank alias lifecycle actions.

  Every alias creation and deletion is recorded here with actor, timestamp,
  the counterparty fragment, and the organization it was mapped to.
  """

  use Ash.Resource,
    otp_app: :gnome_garden,
    domain: GnomeGarden.Mercury,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshAdmin.Resource]

  admin do
    table_columns [
      :id,
      :action,
      :actor_id,
      :counterparty_name_fragment,
      :organization_id,
      :inserted_at
    ]
  end

  postgres do
    table "mercury_alias_events"
    repo GnomeGarden.Repo
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true
      accept [:action, :actor_id, :counterparty_name_fragment, :organization_id]
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :action, :atom do
      allow_nil? false
      public? true
      constraints one_of: [:created, :deleted]
    end

    attribute :actor_id, :uuid do
      allow_nil? true
      public? true
      description "ID of the user who performed the action."
    end

    attribute :counterparty_name_fragment, :string do
      allow_nil? false
      public? true
    end

    attribute :organization_id, :uuid do
      allow_nil? true
      public? true
    end

    timestamps()
  end
end
