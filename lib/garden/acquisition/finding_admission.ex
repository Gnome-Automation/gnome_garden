defmodule GnomeGarden.Acquisition.FindingAdmission do
  @moduledoc """
  Idempotent provenance ledger for a verified candidate admitted as a Finding.

  The normalized identity prevents the same company domain from entering the
  review queue through multiple preview runs.
  """

  use Ash.Resource,
    otp_app: :gnome_garden,
    domain: GnomeGarden.Acquisition,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshAdmin.Resource]

  postgres do
    table "acquisition_finding_admissions"
    repo GnomeGarden.Repo

    references do
      reference :lead_candidate_verification, on_delete: :restrict
      reference :lead_preview_candidate, on_delete: :restrict
      reference :lead_preview_run, on_delete: :restrict
      reference :finding, on_delete: :restrict
    end

    custom_indexes do
      index [:lead_preview_run_id, :admitted_at]
    end
  end

  actions do
    defaults [:read]

    action :verify_preview_run, :map do
      argument :lead_preview_run_id, :uuid, allow_nil?: false
      run GnomeGarden.Acquisition.Actions.VerifyLeadPreviewRun
    end

    create :create do
      accept [
        :lead_candidate_verification_id,
        :lead_preview_candidate_id,
        :lead_preview_run_id,
        :finding_id,
        :identity_key,
        :admitted_at,
        :metadata
      ]
    end

    read :by_identity_key do
      argument :identity_key, :string, allow_nil?: false
      get_by [:identity_key]
      prepare build(load: [:finding, :lead_candidate_verification])
    end

    read :by_candidate do
      argument :lead_preview_candidate_id, :uuid, allow_nil?: false
      get_by [:lead_preview_candidate_id]
      prepare build(load: [:finding, :lead_candidate_verification])
    end

    read :for_run do
      argument :lead_preview_run_id, :uuid, allow_nil?: false
      filter expr(lead_preview_run_id == ^arg(:lead_preview_run_id))
      prepare build(sort: [admitted_at: :asc], load: [:finding, :lead_candidate_verification])
    end
  end

  attributes do
    uuid_primary_key :id
    attribute :identity_key, :string, allow_nil?: false, public?: true
    attribute :admitted_at, :utc_datetime, allow_nil?: false, public?: true
    attribute :metadata, :map, allow_nil?: false, default: %{}, public?: true
    timestamps()
  end

  relationships do
    belongs_to :lead_candidate_verification, GnomeGarden.Acquisition.LeadCandidateVerification do
      allow_nil? false
      public? true
    end

    belongs_to :lead_preview_candidate, GnomeGarden.Acquisition.LeadPreviewCandidate do
      allow_nil? false
      public? true
    end

    belongs_to :lead_preview_run, GnomeGarden.Acquisition.LeadPreviewRun do
      allow_nil? false
      public? true
    end

    belongs_to :finding, GnomeGarden.Acquisition.Finding do
      allow_nil? false
      public? true
    end
  end

  identities do
    identity :unique_identity_key, [:identity_key]
    identity :unique_candidate, [:lead_preview_candidate_id]
    identity :unique_verification, [:lead_candidate_verification_id]
    identity :unique_finding, [:finding_id]
  end
end
