defmodule GnomeGarden.Commercial.CompanyProfile do
  @moduledoc """
  Durable internal profile for how the company should describe and target itself.

  This is the canonical business-facing source of truth for:

  - positioning and specialty
  - target industries and disqualifiers
  - preferred language and tone guidance
  - keyword modes that can later drive discovery and scoring

  Agents and prompts can read from this profile, but the runtime layer should
  not become the only place that knows what the company is.
  """

  use Ash.Resource,
    otp_app: :gnome_garden,
    domain: GnomeGarden.Commercial,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshAdmin.Resource],
    notifiers: [Ash.Notifier.PubSub]

  admin do
    table_columns [:id, :key, :name, :default_profile_mode, :inserted_at]
  end

  postgres do
    table "commercial_company_profiles"
    repo GnomeGarden.Repo
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true

      accept [
        :key,
        :name,
        :legal_name,
        :positioning_summary,
        :specialty_summary,
        :voice_summary,
        :core_capabilities,
        :adjacent_capabilities,
        :target_industries,
        :preferred_engagements,
        :disqualifiers,
        :voice_principles,
        :preferred_phrases,
        :avoid_phrases,
        :default_profile_mode,
        :keyword_profiles,
        :metadata
      ]
    end

    update :update do
      accept [
        :name,
        :legal_name,
        :positioning_summary,
        :specialty_summary,
        :voice_summary,
        :core_capabilities,
        :adjacent_capabilities,
        :target_industries,
        :preferred_engagements,
        :disqualifiers,
        :voice_principles,
        :preferred_phrases,
        :avoid_phrases,
        :default_profile_mode,
        :keyword_profiles,
        :metadata
      ]
    end

    read :by_key do
      argument :key, :string, allow_nil?: false
      get? true
      filter expr(key == ^arg(:key))
    end

    read :primary do
      get? true
      filter expr(key == "primary")
    end
  end

  pub_sub do
    module GnomeGardenWeb.Endpoint
    prefix "company_profile"

    publish :create, "created"
    publish :update, "updated"
  end

  attributes do
    uuid_primary_key :id

    attribute :key, :string do
      allow_nil? false
      default "primary"
      public? true
    end

    attribute :name, :string do
      allow_nil? false
      public? true
    end

    attribute :legal_name, :string do
      public? true
    end

    attribute :positioning_summary, :string do
      public? true
    end

    attribute :specialty_summary, :string do
      public? true
    end

    attribute :voice_summary, :string do
      public? true
    end

    attribute :core_capabilities, {:array, :string} do
      allow_nil? false
      default []
      public? true
    end

    attribute :adjacent_capabilities, {:array, :string} do
      allow_nil? false
      default []
      public? true
    end

    attribute :target_industries, {:array, :string} do
      allow_nil? false
      default []
      public? true
    end

    attribute :preferred_engagements, {:array, :string} do
      allow_nil? false
      default []
      public? true
    end

    attribute :disqualifiers, {:array, :string} do
      allow_nil? false
      default []
      public? true
    end

    attribute :voice_principles, {:array, :string} do
      allow_nil? false
      default []
      public? true
    end

    attribute :preferred_phrases, {:array, :string} do
      allow_nil? false
      default []
      public? true
    end

    attribute :avoid_phrases, {:array, :string} do
      allow_nil? false
      default []
      public? true
    end

    attribute :default_profile_mode, :atom do
      allow_nil? false
      default :industrial_plus_software
      constraints one_of: [:industrial_core, :industrial_plus_software, :broad_software]
      public? true
    end

    attribute :keyword_profiles, :map do
      allow_nil? false
      default %{}
      public? true
    end

    attribute :metadata, :map do
      allow_nil? false
      default %{}
      public? true
    end

    timestamps()
  end

  identities do
    identity :unique_key, [:key]
  end
end
