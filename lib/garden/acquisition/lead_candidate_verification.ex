defmodule GnomeGarden.Acquisition.LeadCandidateVerification do
  @moduledoc """
  Durable evidence and decision for one persisted lead-preview candidate.

  Verification is intentionally separate from admission. A candidate may be
  verified without entering the Finding queue when admission capacity is full.
  """

  use Ash.Resource,
    otp_app: :gnome_garden,
    domain: GnomeGarden.Acquisition,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshAdmin.Resource]

  postgres do
    table "acquisition_lead_candidate_verifications"
    repo GnomeGarden.Repo

    references do
      reference :lead_preview_candidate, on_delete: :restrict
    end

    custom_indexes do
      index [:status, :verified_at]
    end
  end

  actions do
    defaults [:read]

    create :record do
      accept [
        :lead_preview_candidate_id,
        :status,
        :reason,
        :website_domain,
        :search_score,
        :verification_score,
        :evidence,
        :provider_reservation_key,
        :actual_cost,
        :verified_at
      ]

      upsert? true
      upsert_identity :unique_candidate

      upsert_fields [
        :status,
        :reason,
        :website_domain,
        :search_score,
        :verification_score,
        :evidence,
        :provider_reservation_key,
        :actual_cost,
        :verified_at
      ]
    end

    read :by_candidate do
      argument :lead_preview_candidate_id, :uuid, allow_nil?: false
      get_by [:lead_preview_candidate_id]
      prepare build(load: [:admission])
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :status, :atom do
      allow_nil? false
      public? true
      constraints one_of: [:verified, :ineligible, :unresolved]
    end

    attribute :reason, :atom do
      allow_nil? false
      public? true

      constraints one_of: [
                    :qualified,
                    :not_promote_routed,
                    :suppressed,
                    :duplicate_context,
                    :invalid_company_identity,
                    :below_search_score,
                    :insufficient_evidence,
                    :enrichment_disabled,
                    :verification_limit_reached,
                    :provider_budget_exhausted,
                    :provider_failure
                  ]
    end

    attribute :website_domain, :string, public?: true
    attribute :search_score, :decimal, public?: true

    attribute :verification_score, :integer do
      public? true
      constraints min: 0, max: 100
    end

    attribute :evidence, :map, allow_nil?: false, default: %{}, public?: true
    attribute :provider_reservation_key, :string, public?: true
    attribute :actual_cost, :decimal, allow_nil?: false, default: Decimal.new(0), public?: true
    attribute :verified_at, :utc_datetime, allow_nil?: false, public?: true

    timestamps()
  end

  relationships do
    belongs_to :lead_preview_candidate, GnomeGarden.Acquisition.LeadPreviewCandidate do
      allow_nil? false
      public? true
    end

    has_one :admission, GnomeGarden.Acquisition.FindingAdmission do
      destination_attribute :lead_candidate_verification_id
      public? true
    end
  end

  identities do
    identity :unique_candidate, [:lead_preview_candidate_id]
  end
end
