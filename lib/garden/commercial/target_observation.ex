defmodule GnomeGarden.Commercial.TargetObservation do
  @moduledoc """
  Raw observation supporting a discovered target account.

  Observations capture the exact evidence that caused a company to enter the
  target-account queue: hiring posts, expansion news, legacy stack mentions,
  directory listings, or direct referrals.
  """

  use Ash.Resource,
    otp_app: :gnome_garden,
    domain: GnomeGarden.Commercial,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshAdmin.Resource]

  admin do
    table_columns [
      :id,
      :target_account_id,
      :observation_type,
      :source_channel,
      :confidence_score,
      :observed_at,
      :inserted_at
    ]
  end

  postgres do
    table "commercial_target_observations"
    repo GnomeGarden.Repo

    references do
      reference :discovery_program, on_delete: :nilify
      reference :target_account, on_delete: :delete
    end
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true

      accept [
        :target_account_id,
        :observation_type,
        :source_channel,
        :external_ref,
        :source_url,
        :observed_at,
        :confidence_score,
        :summary,
        :raw_excerpt,
        :evidence_points,
        :discovery_program_id,
        :metadata
      ]
    end

    update :update do
      accept [
        :observation_type,
        :source_channel,
        :external_ref,
        :source_url,
        :observed_at,
        :confidence_score,
        :summary,
        :raw_excerpt,
        :evidence_points,
        :discovery_program_id,
        :metadata
      ]
    end

    read :recent do
      prepare build(sort: [observed_at: :desc, inserted_at: :desc], load: [:target_account])
    end

    read :for_target_account do
      argument :target_account_id, :uuid, allow_nil?: false
      filter expr(target_account_id == ^arg(:target_account_id))
      prepare build(sort: [observed_at: :desc, inserted_at: :desc], load: [:target_account])
    end

    read :for_discovery_program do
      argument :discovery_program_id, :uuid, allow_nil?: false
      filter expr(discovery_program_id == ^arg(:discovery_program_id))
      prepare build(sort: [observed_at: :desc, inserted_at: :desc], load: [:target_account])
    end

    read :by_external_ref do
      argument :external_ref, :string, allow_nil?: false
      get_by [:external_ref]
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :observation_type, :atom do
      allow_nil? false
      default :other
      public? true

      constraints one_of: [
                    :hiring,
                    :expansion,
                    :legacy_stack,
                    :directory,
                    :news,
                    :referral,
                    :website_contact,
                    :bid_notice,
                    :manual,
                    :other
                  ]
    end

    attribute :source_channel, :atom do
      allow_nil? false
      default :agent_discovery
      public? true

      constraints one_of: [
                    :company_website,
                    :job_board,
                    :directory,
                    :news_site,
                    :referral,
                    :agent_discovery,
                    :manual,
                    :other
                  ]
    end

    attribute :external_ref, :string do
      public? true
    end

    attribute :source_url, :string do
      public? true
    end

    attribute :observed_at, :utc_datetime do
      public? true
    end

    attribute :confidence_score, :integer do
      allow_nil? false
      default 50
      public? true
      constraints min: 0, max: 100
    end

    attribute :summary, :string do
      allow_nil? false
      public? true
    end

    attribute :raw_excerpt, :string do
      public? true
    end

    attribute :evidence_points, {:array, :string} do
      allow_nil? false
      default []
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
    belongs_to :discovery_program, GnomeGarden.Commercial.DiscoveryProgram do
      public? true
    end

    belongs_to :target_account, GnomeGarden.Commercial.TargetAccount do
      allow_nil? false
      public? true
    end
  end

  calculations do
    calculate :confidence_variant,
              :atom,
              {GnomeGarden.Calculations.ScoreVariant, field: :confidence_score}
  end

  identities do
    identity :unique_external_ref, [:external_ref]
  end
end
