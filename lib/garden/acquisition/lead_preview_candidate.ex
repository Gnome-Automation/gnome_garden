defmodule GnomeGarden.Acquisition.LeadPreviewCandidate do
  @moduledoc """
  One candidate from a `LeadPreviewRun`: the page, how it was found, how it was
  classified/routed, and what (if anything) it was promoted into. Keeps the
  preview survivable across refresh and gives a history of promote decisions.
  """

  use Ash.Resource,
    otp_app: :gnome_garden,
    domain: GnomeGarden.Acquisition,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshAdmin.Resource]

  admin do
    table_columns [
      :id,
      :lead_preview_run_id,
      :title,
      :website_domain,
      :candidate_type,
      :route,
      :status
    ]
  end

  postgres do
    table "acquisition_lead_preview_candidates"
    repo GnomeGarden.Repo

    references do
      reference :lead_preview_run, on_delete: :delete
    end

    custom_indexes do
      index [:lead_preview_run_id]
    end
  end

  actions do
    defaults [:read]

    create :create do
      primary? true

      accept [
        :lead_preview_run_id,
        :title,
        :url,
        :website_domain,
        :query,
        :published_date,
        :candidate_type,
        :dedupe_context,
        :route,
        :suppressed,
        :recommendation,
        :rank,
        :status,
        :metadata
      ]
    end

    update :mark_promoted do
      accept [:promoted_record_id]
      change set_attribute(:status, :promoted)
      change set_attribute(:promoted_at, &DateTime.utc_now/0)
    end

    update :mark_status do
      accept [:status]
    end

    read :for_run do
      argument :lead_preview_run_id, :uuid, allow_nil?: false
      filter expr(lead_preview_run_id == ^arg(:lead_preview_run_id))
      prepare build(sort: [rank: :asc])
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :title, :string, public?: true
    attribute :url, :string, allow_nil?: false, public?: true
    attribute :website_domain, :string, public?: true
    attribute :query, :string, public?: true
    attribute :published_date, :string, public?: true

    attribute :candidate_type, :atom do
      public? true
      constraints one_of: [:company, :signal]
    end

    attribute :dedupe_context, :atom do
      public? true

      constraints one_of: [
                    :new,
                    :duplicate_existing_lead,
                    :known_organization_new_signal,
                    :existing_bid_related,
                    :known_procurement_source,
                    :known_bid_source
                  ]
    end

    attribute :route, :atom do
      public? true
      constraints one_of: [:promote, :needs_enrichment, :skip]
    end

    attribute :suppressed, :boolean, default: false, public?: true
    attribute :recommendation, :string, public?: true
    attribute :rank, :integer, public?: true

    attribute :status, :atom do
      allow_nil? false
      default :pending
      public? true
      constraints one_of: [:pending, :promoted, :skipped, :needs_enrichment]
    end

    attribute :promoted_record_id, :uuid, public?: true
    attribute :promoted_at, :utc_datetime, public?: true
    attribute :metadata, :map, default: %{}, public?: true

    timestamps()
  end

  relationships do
    belongs_to :lead_preview_run, GnomeGarden.Acquisition.LeadPreviewRun do
      allow_nil? false
      public? true
    end

    has_one :verification, GnomeGarden.Acquisition.LeadCandidateVerification do
      destination_attribute :lead_preview_candidate_id
      public? true
    end

    has_one :finding_admission, GnomeGarden.Acquisition.FindingAdmission do
      destination_attribute :lead_preview_candidate_id
      public? true
    end
  end
end
