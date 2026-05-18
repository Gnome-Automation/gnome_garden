defmodule GnomeGarden.Procurement.SourceSearchFilter do
  @moduledoc """
  Persisted search filter for a procurement source.

  SAM.gov sources use these records as the operator-tunable NAICS search list.
  Additional filter types are allowed so the same model can grow into keyword or
  location filtering without changing the scanner contract again.
  """

  use Ash.Resource,
    otp_app: :gnome_garden,
    domain: GnomeGarden.Procurement,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshAdmin.Resource],
    notifiers: [Ash.Notifier.PubSub]

  admin do
    table_columns [:procurement_source_id, :filter_type, :value, :label, :enabled, :priority]
  end

  postgres do
    table "procurement_source_search_filters"
    repo GnomeGarden.Repo

    custom_indexes do
      index [:procurement_source_id, :enabled, :priority]
      index [:filter_type, :value]
    end

    references do
      reference :procurement_source, on_delete: :delete
    end
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true
      upsert? true
      upsert_identity :unique_source_filter
      upsert_fields [:label, :priority, :enabled, :per_run_limit, :notes, :metadata]

      accept [
        :procurement_source_id,
        :filter_type,
        :value,
        :label,
        :priority,
        :enabled,
        :per_run_limit,
        :notes,
        :metadata
      ]
    end

    update :update do
      accept [:label, :priority, :enabled, :per_run_limit, :notes, :metadata]
    end

    update :record_run do
      accept [:last_returned_count, :last_saved_count]

      change set_attribute(:last_run_at, &DateTime.utc_now/0)
    end

    update :disable_noisy do
      require_atomic? false
      accept []

      change set_attribute(:enabled, false)

      change fn changeset, _context ->
        record_operator_decision(changeset, "disable_noisy")
      end
    end

    update :keep_searching do
      require_atomic? false
      accept []

      change set_attribute(:enabled, true)

      change fn changeset, _context ->
        record_operator_decision(changeset, "keep_searching")
      end
    end

    read :for_source do
      argument :procurement_source_id, :uuid, allow_nil?: false

      filter expr(procurement_source_id == ^arg(:procurement_source_id))

      prepare build(
                sort: [priority: :asc, filter_type: :asc, value: :asc],
                load: [
                  :accepted_feedback_count,
                  :parked_feedback_count,
                  :rejected_feedback_count,
                  :suppressed_feedback_count,
                  :performance_recommendation,
                  :performance_note,
                  :performance_variant
                ]
              )
    end

    read :enabled_for_source do
      argument :procurement_source_id, :uuid, allow_nil?: false

      filter expr(procurement_source_id == ^arg(:procurement_source_id) and enabled == true)

      prepare build(
                sort: [priority: :asc, filter_type: :asc, value: :asc],
                load: [
                  :accepted_feedback_count,
                  :parked_feedback_count,
                  :rejected_feedback_count,
                  :suppressed_feedback_count,
                  :performance_recommendation,
                  :performance_note,
                  :performance_variant
                ]
              )
    end
  end

  pub_sub do
    module GnomeGardenWeb.Endpoint
    prefix "procurement_source_search_filter"

    publish :create, "created"
    publish :update, "updated"
    publish :record_run, "updated"
    publish :destroy, "destroyed"
  end

  attributes do
    uuid_primary_key :id

    attribute :filter_type, :atom do
      allow_nil? false
      default :naics
      public? true
      constraints one_of: [:naics, :keyword, :state]
    end

    attribute :value, :string do
      allow_nil? false
      public? true
    end

    attribute :label, :string do
      public? true
    end

    attribute :priority, :atom do
      allow_nil? false
      default :medium
      public? true
      constraints one_of: [:high, :medium, :low]
    end

    attribute :enabled, :boolean do
      allow_nil? false
      default true
      public? true
    end

    attribute :per_run_limit, :integer do
      allow_nil? false
      default 5
      public? true
    end

    attribute :last_returned_count, :integer do
      allow_nil? false
      default 0
      public? true
    end

    attribute :last_saved_count, :integer do
      allow_nil? false
      default 0
      public? true
    end

    attribute :last_run_at, :utc_datetime do
      public? true
    end

    attribute :notes, :string do
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
    belongs_to :procurement_source, GnomeGarden.Procurement.ProcurementSource do
      allow_nil? false
      public? true
    end

    has_many :feedback_events, GnomeGarden.Procurement.SourceSearchFilterFeedback do
      destination_attribute :source_search_filter_id
      public? true
    end
  end

  calculations do
    calculate :performance_recommendation,
              :string,
              {GnomeGarden.Calculations.SourceSearchFilterPerformance, return: :recommendation}

    calculate :performance_note,
              :string,
              {GnomeGarden.Calculations.SourceSearchFilterPerformance, return: :note}

    calculate :performance_variant,
              :atom,
              {GnomeGarden.Calculations.SourceSearchFilterPerformance, return: :variant}
  end

  aggregates do
    count :accepted_feedback_count, :feedback_events do
      public? true
      filter expr(decision == :accepted)
    end

    count :parked_feedback_count, :feedback_events do
      public? true
      filter expr(decision == :parked)
    end

    count :rejected_feedback_count, :feedback_events do
      public? true
      filter expr(decision == :rejected)
    end

    count :suppressed_feedback_count, :feedback_events do
      public? true
      filter expr(decision == :suppressed)
    end
  end

  identities do
    identity :unique_source_filter, [:procurement_source_id, :filter_type, :value]
  end

  defp record_operator_decision(changeset, decision) do
    metadata =
      changeset
      |> Ash.Changeset.get_data(:metadata)
      |> normalize_metadata()
      |> Map.put("operator_recommendation", decision)
      |> Map.put("operator_recommendation_at", DateTime.utc_now() |> DateTime.to_iso8601())

    Ash.Changeset.change_attribute(changeset, :metadata, metadata)
  end

  defp normalize_metadata(metadata) when is_map(metadata) do
    Map.new(metadata, fn {key, value} -> {to_string(key), value} end)
  end

  defp normalize_metadata(_metadata), do: %{}
end
