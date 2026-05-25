defmodule GnomeGarden.Procurement.SourceSearchFilterFeedback do
  @moduledoc """
  Durable review feedback event for a source search filter.

  These records connect acquisition review outcomes back to the exact search
  filter that produced the finding, so filter recommendations can be computed
  from queryable history instead of opaque metadata.
  """

  use Ash.Resource,
    otp_app: :gnome_garden,
    domain: GnomeGarden.Procurement,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshAdmin.Resource, AshLua.Resource],
    notifiers: [Ash.Notifier.PubSub]

  admin do
    table_columns [
      :source_search_filter_id,
      :finding_id,
      :decision,
      :reason_code,
      :feedback_scope,
      :recorded_at
    ]
  end

  postgres do
    table "procurement_source_search_filter_feedback"
    repo GnomeGarden.Repo
    identity_index_names unique_filter_finding_decision: "source_filter_feedback_unique_idx"

    custom_indexes do
      index [:source_search_filter_id, :decision]
      index [:reason_code]
      index [:recorded_at]
    end

    references do
      reference :source_search_filter,
        on_delete: :delete,
        name: "source_filter_feedback_filter_id_fkey"

      reference :finding,
        on_delete: :delete,
        name: "source_filter_feedback_finding_id_fkey"
    end
  end

  actions do
    defaults [:read, :destroy]

    create :record do
      primary? true
      upsert? true
      upsert_identity :unique_filter_finding_decision

      upsert_fields [
        :reason,
        :reason_code,
        :feedback_scope,
        :source_feedback_category,
        :recorded_at,
        :metadata
      ]

      accept [
        :source_search_filter_id,
        :finding_id,
        :decision,
        :reason,
        :reason_code,
        :feedback_scope,
        :source_feedback_category,
        :recorded_at,
        :metadata
      ]

      change set_new_attribute(:recorded_at, &DateTime.utc_now/0)
    end

    read :for_filter do
      argument :source_search_filter_id, :uuid, allow_nil?: false
      filter expr(source_search_filter_id == ^arg(:source_search_filter_id))
      prepare build(sort: [recorded_at: :desc])
    end

    read :for_finding do
      argument :finding_id, :uuid, allow_nil?: false
      filter expr(finding_id == ^arg(:finding_id))
      prepare build(sort: [recorded_at: :desc])
    end
  end

  pub_sub do
    module GnomeGardenWeb.Endpoint
    prefix "procurement_source_search_filter_feedback"

    publish :record, "recorded"
    publish :destroy, "destroyed"
  end

  attributes do
    uuid_primary_key :id

    attribute :decision, :atom do
      allow_nil? false
      public? true
      constraints one_of: [:accepted, :rejected, :parked, :suppressed]
    end

    attribute :reason, :string do
      public? true
    end

    attribute :reason_code, :string do
      public? true
    end

    attribute :feedback_scope, :string do
      public? true
    end

    attribute :source_feedback_category, :string do
      public? true
    end

    attribute :recorded_at, :utc_datetime do
      public? true
    end

    attribute :metadata, :map do
      allow_nil? false
      default %{}
      public? true
    end

    timestamps()
  end

  relationships do
    belongs_to :source_search_filter, GnomeGarden.Procurement.SourceSearchFilter do
      allow_nil? false
      public? true
    end

    belongs_to :finding, GnomeGarden.Acquisition.Finding do
      allow_nil? false
      public? true
    end
  end

  identities do
    identity :unique_filter_finding_decision, [:source_search_filter_id, :finding_id, :decision]
  end
end
