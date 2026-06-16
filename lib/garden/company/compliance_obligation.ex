defmodule GnomeGarden.Company.ComplianceObligation do
  @moduledoc """
  Company-level compliance obligation or renewal checkpoint.

  These are reusable Gnome obligations such as BOI, statement of information,
  registered agent renewal, franchise tax, and business license checks. Customer
  packet requirements stay in the Commercial domain.
  """

  use Ash.Resource,
    otp_app: :gnome_garden,
    domain: GnomeGarden.Company,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshAdmin.Resource],
    notifiers: [Ash.Notifier.PubSub]

  admin do
    table_columns [:key, :title, :category, :status, :due_on, :completed_on]
  end

  postgres do
    table "company_compliance_obligations"
    repo GnomeGarden.Repo

    identity_index_names unique_company_compliance_key: "company_compliance_profile_key_idx"

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
        :category,
        :status,
        :summary,
        :due_on,
        :completed_on,
        :source_path,
        :source_commit,
        :metadata
      ]
    end

    update :update do
      require_atomic? false

      accept [
        :title,
        :category,
        :status,
        :summary,
        :due_on,
        :completed_on,
        :source_path,
        :source_commit,
        :metadata
      ]
    end

    update :mark_complete do
      accept [:summary, :completed_on]
      change set_attribute(:status, :complete)
    end

    update :mark_needs_review do
      accept [:summary]
      change set_attribute(:status, :needs_review)
    end

    read :active do
      filter expr(status in [:active, :needs_review, :blocked])
      prepare build(sort: [category: :asc, due_on: :asc, title: :asc])
    end

    read :for_company_profile do
      argument :company_profile_id, :uuid, allow_nil?: false
      filter expr(company_profile_id == ^arg(:company_profile_id))
      prepare build(sort: [category: :asc, due_on: :asc, title: :asc])
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
    prefix "company_compliance_obligation"

    publish :create, "created"
    publish :update, "updated"
    publish :mark_complete, "updated"
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

    attribute :category, :atom do
      allow_nil? false
      default :other
      public? true
      constraints one_of: [:federal, :state, :registered_agent, :tax, :license, :other]
    end

    attribute :status, :atom do
      allow_nil? false
      default :needs_review
      public? true
      constraints one_of: [:needs_review, :active, :complete, :blocked, :not_applicable]
    end

    attribute :summary, :string do
      public? true
    end

    attribute :due_on, :date do
      public? true
    end

    attribute :completed_on, :date do
      public? true
    end

    attribute :source_path, :string do
      public? true
    end

    attribute :source_commit, :string do
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
    identity :unique_company_compliance_key, [:company_profile_id, :key]
  end
end
