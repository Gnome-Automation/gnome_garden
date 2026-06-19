defmodule GnomeGarden.Acquisition.LeadPreviewRun do
  @moduledoc """
  A durable record of one lead-preview execution — what was searched, the
  promotable / needs-enrichment / suppressed split, and the cost.

  Previews used to be ephemeral (LiveView assigns only). Persisting them turns a
  week of operator use into data: cost history, query quality, the enrichment
  split, and which candidates were promoted. It is also the basis for scheduled
  preview "packets" later. Child rows live in `LeadPreviewCandidate`.
  """

  use Ash.Resource,
    otp_app: :gnome_garden,
    domain: GnomeGarden.Acquisition,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshAdmin.Resource]

  admin do
    table_columns [
      :id,
      :source,
      :status,
      :query_count,
      :candidate_count,
      :promotable_count,
      :needs_enrichment_count,
      :suppressed_count,
      :total_cost,
      :inserted_at
    ]
  end

  postgres do
    table "acquisition_lead_preview_runs"
    repo GnomeGarden.Repo
  end

  actions do
    defaults [:read]

    create :create do
      primary? true

      accept [
        :source,
        :status,
        :started_at,
        :finished_at,
        :query_count,
        :candidate_count,
        :promotable_count,
        :needs_enrichment_count,
        :suppressed_count,
        :total_cost,
        :errors,
        :metadata,
        :discovery_program_id,
        :created_by_id
      ]

      argument :candidates, {:array, :map}, allow_nil?: true

      change manage_relationship(:candidates, :candidates, type: :create)
    end

    read :recent do
      prepare build(sort: [inserted_at: :desc], limit: 50)
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :source, :atom do
      allow_nil? false
      default :exa
      public? true
      constraints one_of: [:exa, :manual]
    end

    attribute :status, :atom do
      allow_nil? false
      default :completed
      public? true
      constraints one_of: [:running, :completed, :partial_failure, :failed]
    end

    attribute :started_at, :utc_datetime, public?: true
    attribute :finished_at, :utc_datetime, public?: true

    attribute :query_count, :integer, default: 0, public?: true
    attribute :candidate_count, :integer, default: 0, public?: true
    attribute :promotable_count, :integer, default: 0, public?: true
    attribute :needs_enrichment_count, :integer, default: 0, public?: true
    attribute :suppressed_count, :integer, default: 0, public?: true

    attribute :total_cost, :decimal, default: Decimal.new(0), public?: true
    attribute :errors, {:array, :string}, default: [], public?: true
    attribute :metadata, :map, default: %{}, public?: true

    # External references (no FK — this is an append-only log).
    attribute :discovery_program_id, :uuid, public?: true
    attribute :created_by_id, :uuid, public?: true

    timestamps()
  end

  relationships do
    has_many :candidates, GnomeGarden.Acquisition.LeadPreviewCandidate do
      public? true
    end
  end
end
