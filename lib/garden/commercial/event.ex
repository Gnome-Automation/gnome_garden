defmodule GnomeGarden.Commercial.Event do
  @moduledoc """
  Append-only decision/audit log.

  Records every meaningful state change across the commercial flow — passes,
  pursues, stage advances, wins, losses — with who did it, why, and
  what changed. Never edited or deleted.

  Use for:
  - Audit trail ("why did we pass on this?")
  - Pattern analysis ("what do we keep passing on?")
  - Team accountability ("who moved this forward?")
  """

  use Ash.Resource,
    otp_app: :gnome_garden,
    domain: GnomeGarden.Commercial,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshAdmin.Resource]

  admin do
    table_columns [:id, :event_type, :subject_type, :summary, :inserted_at]
  end

  postgres do
    table "commercial_events"
    repo GnomeGarden.Repo
  end

  actions do
    defaults [:read]

    create :log do
      primary? true

      accept [
        :event_type,
        :subject_type,
        :subject_id,
        :summary,
        :reason,
        :from_state,
        :to_state,
        :metadata,
        :actor_id,
        :organization_id
      ]
    end

    read :for_subject do
      argument :subject_type, :string, allow_nil?: false
      argument :subject_id, :uuid, allow_nil?: false
      filter expr(subject_type == ^arg(:subject_type) and subject_id == ^arg(:subject_id))
      prepare build(sort: [inserted_at: :desc])
    end

    read :recent do
      argument :days, :integer, default: 30
      filter expr(inserted_at > ago(^arg(:days), :day))
      prepare build(sort: [inserted_at: :desc])
    end

    read :passes do
      filter expr(event_type == :passed)
      prepare build(sort: [inserted_at: :desc])
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :event_type, :atom do
      allow_nil? false
      public? true

      constraints one_of: [
                    :pursued,
                    :passed,
                    :parked,
                    :stage_advanced,
                    :closed_won,
                    :closed_lost,
                    :created,
                    :note
                  ]

      description "What happened"
    end

    attribute :subject_type, :string do
      allow_nil? false
      public? true
      description "Type of record: bid, finding, signal, pursuit"
    end

    attribute :subject_id, :uuid do
      allow_nil? false
      public? true
      description "ID of the record this event is about"
    end

    attribute :summary, :string do
      allow_nil? false
      public? true
      description "Human-readable one-liner: 'Passed on SCADA bid — not in our area'"
    end

    attribute :reason, :string do
      public? true
      description "Why this decision was made"
    end

    attribute :from_state, :string do
      public? true
      description "State before the transition"
    end

    attribute :to_state, :string do
      public? true
      description "State after the transition"
    end

    attribute :metadata, :map do
      default %{}
      public? true
      description "Extra context: score, workflow, source, etc."
    end

    timestamps()
  end

  relationships do
    belongs_to :actor, GnomeGarden.Accounts.User do
      public? true
      description "Who made this decision"
    end

    belongs_to :organization, GnomeGarden.Operations.Organization do
      public? true
      description "Related organization (if exists)"
    end
  end
end
