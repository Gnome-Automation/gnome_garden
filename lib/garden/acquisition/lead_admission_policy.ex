defmodule GnomeGarden.Acquisition.LeadAdmissionPolicy do
  @moduledoc """
  Persisted operator policy for commercial candidate verification and admission.

  The singleton default is created idempotently on first use. Thresholds are
  database state so operators can tune evidence quality without a deploy.
  Per-source execution and admission caps belong to `ProgramSource`.
  """

  use Ash.Resource,
    otp_app: :gnome_garden,
    domain: GnomeGarden.Acquisition,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshAdmin.Resource]

  @default_key "commercial-default"

  postgres do
    table "acquisition_lead_admission_policies"
    repo GnomeGarden.Repo
  end

  actions do
    defaults [:read]

    create :ensure_default do
      accept [:key]
      upsert? true
      upsert_identity :unique_key
      upsert_fields []
    end

    update :update do
      accept [
        :min_search_score,
        :min_evidence_characters
      ]
    end

    read :by_key do
      argument :key, :string, allow_nil?: false
      get_by [:key]
    end
  end

  attributes do
    uuid_primary_key :id
    attribute :key, :string, allow_nil?: false, default: @default_key, public?: true

    attribute :min_search_score, :decimal do
      allow_nil? false
      default Decimal.new("0.10")
      public? true
      constraints min: Decimal.new(0)
    end

    attribute :min_evidence_characters, :integer do
      allow_nil? false
      default 300
      public? true
      constraints min: 1
    end

    timestamps()
  end

  identities do
    identity :unique_key, [:key]
  end

  def default_key, do: @default_key
end
