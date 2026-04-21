defmodule GnomeGarden.Acquisition.FindingReviewDecision do
  @moduledoc """
  Durable operator review history for acquisition findings.

  This keeps acceptance, rejection, suppression, parking, reopening, and
  promotion rationale attached to the finding instead of scattering it across
  origin metadata or transient UI state.
  """

  use Ash.Resource,
    otp_app: :gnome_garden,
    domain: GnomeGarden.Acquisition,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshAdmin.Resource]

  admin do
    table_columns [:recorded_at, :decision, :reason, :reason_code, :finding_id, :actor_user_id]
  end

  postgres do
    table "acquisition_finding_review_decisions"
    repo GnomeGarden.Repo

    custom_indexes do
      index [:finding_id, :recorded_at]
      index [:decision, :recorded_at]
    end

    references do
      reference :finding, on_delete: :delete
      reference :actor_user, on_delete: :nilify
    end
  end

  actions do
    defaults [:read, :destroy]

    create :record do
      primary? true

      accept [
        :decision,
        :reason,
        :reason_code,
        :feedback_scope,
        :exclude_terms,
        :recorded_at,
        :metadata,
        :finding_id
      ]

      change set_new_attribute(:recorded_at, &DateTime.utc_now/0)
      change relate_actor(:actor_user, allow_nil?: true)
    end

    read :for_finding do
      argument :finding_id, :uuid, allow_nil?: false
      filter expr(finding_id == ^arg(:finding_id))
      prepare build(sort: [recorded_at: :desc, inserted_at: :desc])
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :decision, :atom do
      allow_nil? false
      public? true

      constraints one_of: [
                    :started_review,
                    :accepted,
                    :rejected,
                    :suppressed,
                    :parked,
                    :reopened,
                    :promoted
                  ]
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

    attribute :exclude_terms, {:array, :string} do
      allow_nil? false
      default []
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
    belongs_to :finding, GnomeGarden.Acquisition.Finding do
      allow_nil? false
      public? true
    end

    belongs_to :actor_user, GnomeGarden.Accounts.User do
      public? true
    end
  end
end
