defmodule GnomeGarden.Company.SourceReviewItem do
  @moduledoc """
  Reviewed source evidence for company data.

  This records what a source file claims, whether it should be trusted, and how
  it maps to Company resources. It is deliberately not an automatic importer.
  """

  use Ash.Resource,
    otp_app: :gnome_garden,
    domain: GnomeGarden.Company,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshAdmin.Resource],
    notifiers: [Ash.Notifier.PubSub]

  admin do
    table_columns [:key, :title, :status, :source_path, :target_resource]
  end

  postgres do
    table "company_source_review_items"
    repo GnomeGarden.Repo

    identity_index_names unique_company_source_review_key: "company_source_review_profile_key_idx"

    references do
      reference :company_profile, on_delete: :delete
    end
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true

      accept [
        :company_profile_id,
        :key,
        :title,
        :status,
        :source_path,
        :source_commit,
        :evidence_date,
        :target_resource,
        :summary,
        :recommendation,
        :metadata
      ]
    end

    update :update do
      require_atomic? false

      accept [
        :title,
        :status,
        :source_path,
        :source_commit,
        :evidence_date,
        :target_resource,
        :summary,
        :recommendation,
        :metadata
      ]
    end

    update :mark_applied do
      accept [:recommendation]
      change set_attribute(:status, :applied)
    end

    update :ignore do
      accept [:recommendation]
      change set_attribute(:status, :ignored)
    end

    update :mark_needs_review do
      accept [:recommendation]
      change set_attribute(:status, :needs_review)
    end

    read :for_company_profile do
      argument :company_profile_id, :uuid, allow_nil?: false
      filter expr(company_profile_id == ^arg(:company_profile_id))
      prepare build(sort: [status: :asc, source_path: :asc])
    end

    read :by_status do
      argument :status, :atom, allow_nil?: false
      filter expr(status == ^arg(:status))
      prepare build(sort: [source_path: :asc])
    end

    read :by_key do
      argument :company_profile_id, :uuid, allow_nil?: false
      argument :key, :string, allow_nil?: false
      get? true
      filter expr(company_profile_id == ^arg(:company_profile_id) and key == ^arg(:key))
    end
  end

  pub_sub do
    module GnomeGardenWeb.Endpoint
    prefix "company_source_review_item"

    publish :create, "created"
    publish :update, "updated"
    publish :mark_applied, "updated"
    publish :ignore, "updated"
    publish :mark_needs_review, "updated"
    publish :destroy, "destroyed"
  end

  attributes do
    uuid_primary_key :id

    attribute :key, :string do
      allow_nil? false
      public? true
    end

    attribute :title, :string do
      allow_nil? false
      public? true
    end

    attribute :status, :atom do
      allow_nil? false
      default :needs_review
      public? true

      constraints one_of: [
                    :high_confidence,
                    :needs_review,
                    :conflict,
                    :missing,
                    :applied,
                    :ignored
                  ]
    end

    attribute :source_path, :string do
      allow_nil? false
      public? true
    end

    attribute :source_commit, :string do
      public? true
    end

    attribute :evidence_date, :date do
      public? true
    end

    attribute :target_resource, :string do
      public? true
    end

    attribute :summary, :string do
      public? true
    end

    attribute :recommendation, :string do
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
    belongs_to :company_profile, GnomeGarden.Company.Profile do
      allow_nil? false
      public? true
    end
  end

  identities do
    identity :unique_company_source_review_key, [:company_profile_id, :key]
  end
end
