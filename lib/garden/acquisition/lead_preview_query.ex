defmodule GnomeGarden.Acquisition.LeadPreviewQuery do
  @moduledoc "One provider query execution within a durable lead preview run."

  use Ash.Resource,
    otp_app: :gnome_garden,
    domain: GnomeGarden.Acquisition,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshAdmin.Resource]

  postgres do
    table "acquisition_lead_preview_queries"
    repo GnomeGarden.Repo

    references do
      reference :lead_preview_run, on_delete: :delete
    end

    custom_indexes do
      index [:lead_preview_run_id, :query_index], name: "lead_preview_queries_run_index"
      index [:query, :inserted_at], name: "lead_preview_queries_query_inserted_index"
    end
  end

  actions do
    defaults [:read]

    create :create do
      primary? true
      upsert? true
      upsert_identity :unique_run_query_index
      upsert_fields []

      accept [
        :lead_preview_run_id,
        :query,
        :intent,
        :query_index,
        :status,
        :result_count,
        :cost,
        :reservation_key,
        :error,
        :metadata
      ]
    end

    read :for_run do
      argument :lead_preview_run_id, :uuid, allow_nil?: false
      filter expr(lead_preview_run_id == ^arg(:lead_preview_run_id))
      prepare build(sort: [query_index: :asc])
    end

    read :feedback_window do
      argument :recorded_since, :utc_datetime, allow_nil?: false

      filter expr(
               inserted_at >= ^arg(:recorded_since) and
                 not is_nil(lead_preview_run.program_source_id)
             )

      prepare build(sort: [inserted_at: :desc], load: [lead_preview_run: :program_source])
    end

    read :feedback_window_for_program_source do
      argument :program_source_id, :uuid, allow_nil?: false
      argument :recorded_since, :utc_datetime, allow_nil?: false

      filter expr(
               inserted_at >= ^arg(:recorded_since) and
                 lead_preview_run.program_source_id == ^arg(:program_source_id)
             )

      prepare build(sort: [inserted_at: :desc], load: [lead_preview_run: :program_source])
    end
  end

  attributes do
    uuid_primary_key :id
    attribute :query, :string, allow_nil?: false, public?: true

    attribute :intent, :atom do
      allow_nil? false
      default :company
      public? true
      constraints one_of: [:company]
    end

    attribute :query_index, :integer, allow_nil?: false, public?: true

    attribute :status, :atom do
      allow_nil? false
      public? true
      constraints one_of: [:completed, :failed, :blocked, :replayed_without_results]
    end

    attribute :result_count, :integer, allow_nil?: false, default: 0, public?: true
    attribute :cost, :decimal, allow_nil?: false, default: Decimal.new(0), public?: true
    attribute :reservation_key, :string, allow_nil?: false, public?: true
    attribute :error, :string, public?: true
    attribute :metadata, :map, allow_nil?: false, default: %{}, public?: true
    timestamps()
  end

  relationships do
    belongs_to :lead_preview_run, GnomeGarden.Acquisition.LeadPreviewRun do
      allow_nil? false
      public? true
    end
  end

  identities do
    identity :unique_run_query_index, [:lead_preview_run_id, :query_index]
  end
end
