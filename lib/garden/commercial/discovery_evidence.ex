defmodule GnomeGarden.Commercial.DiscoveryEvidence do
  @moduledoc """
  Raw discovery evidence supporting a discovery record.

  Observations capture the exact evidence that caused a company to enter the
  discovery record queue: hiring posts, expansion news, legacy stack mentions,
  directory listings, or direct referrals.
  """

  use Ash.Resource,
    otp_app: :gnome_garden,
    domain: GnomeGarden.Commercial,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshAdmin.Resource]

  alias GnomeGarden.Commercial

  admin do
    table_columns [
      :id,
      :discovery_record_id,
      :observation_type,
      :source_channel,
      :confidence_score,
      :observed_at,
      :inserted_at
    ]
  end

  postgres do
    table "commercial_discovery_evidence"
    repo GnomeGarden.Repo

    references do
      reference :discovery_program, on_delete: :nilify
      reference :discovery_record, on_delete: :delete
    end
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true

      accept [
        :discovery_record_id,
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

      change after_action(fn _changeset, observation, _context ->
               sync_discovery_record_finding(observation)
             end)
    end

    update :update do
      require_atomic? false

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

      change after_action(fn _changeset, observation, _context ->
               sync_discovery_record_finding(observation)
             end)
    end

    read :recent do
      prepare build(sort: [observed_at: :desc, inserted_at: :desc], load: [:discovery_record])
    end

    read :for_discovery_record do
      argument :discovery_record_id, :uuid, allow_nil?: false
      filter expr(discovery_record_id == ^arg(:discovery_record_id))
      prepare build(sort: [observed_at: :desc, inserted_at: :desc], load: [:discovery_record])
    end

    read :for_discovery_program do
      argument :discovery_program_id, :uuid, allow_nil?: false
      filter expr(discovery_program_id == ^arg(:discovery_program_id))
      prepare build(sort: [observed_at: :desc, inserted_at: :desc], load: [:discovery_record])
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

    attribute :discovery_record_id, :uuid do
      public? true
    end

    timestamps()
  end

  relationships do
    belongs_to :discovery_program, GnomeGarden.Commercial.DiscoveryProgram do
      public? true
    end

    belongs_to :discovery_record, GnomeGarden.Commercial.DiscoveryRecord do
      source_attribute :discovery_record_id
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

  defp sync_discovery_record_finding(%{discovery_record_id: discovery_record_id} = observation)
       when is_binary(discovery_record_id) do
    with :ok <- sync_discovery_record_source_category(observation),
         {:ok, discovery_record} <- load_discovery_record_for_projection(discovery_record_id),
         {:ok, _finding} <-
           GnomeGarden.Acquisition.sync_discovery_record_finding(discovery_record) do
      {:ok, observation}
    else
      {:error, error} -> {:error, error}
    end
  end

  defp sync_discovery_record_finding(observation), do: {:ok, observation}

  defp sync_discovery_record_source_category(%{
         discovery_record_id: discovery_record_id,
         observation_type: observation_type
       })
       when is_binary(discovery_record_id) do
    case source_category_for_observation(observation_type) do
      nil ->
        :ok

      source_category ->
        with {:ok, discovery_record} <- Commercial.get_discovery_record(discovery_record_id),
             updated_metadata <-
               put_target_source_category(discovery_record.metadata, source_category),
             :ok <-
               maybe_update_discovery_record_metadata(discovery_record, updated_metadata) do
          :ok
        else
          {:error, error} -> {:error, error}
        end
    end
  end

  defp sync_discovery_record_source_category(_observation), do: :ok

  defp load_discovery_record_for_projection(discovery_record_id) do
    Commercial.get_discovery_record(
      discovery_record_id,
      load: [
        :organization,
        :promoted_signal,
        :latest_evidence_at,
        :latest_evidence_summary,
        :discovery_program
      ]
    )
  end

  defp maybe_update_discovery_record_metadata(discovery_record, updated_metadata) do
    if updated_metadata == (discovery_record.metadata || %{}) do
      :ok
    else
      case Commercial.update_discovery_record(discovery_record, %{metadata: updated_metadata}) do
        {:ok, _discovery_record} -> :ok
        {:error, error} -> {:error, error}
      end
    end
  end

  defp put_target_source_category(metadata, source_category) do
    metadata = metadata || %{}

    market_focus =
      metadata
      |> Map.get("market_focus", %{})
      |> Map.put("source_category", source_category)

    Map.put(metadata, "market_focus", market_focus)
  end

  defp source_category_for_observation(:hiring), do: "hiring"
  defp source_category_for_observation(:expansion), do: "expansion"
  defp source_category_for_observation(:website_contact), do: "contact"
  defp source_category_for_observation(:referral), do: "contact"
  defp source_category_for_observation(:directory), do: "contact"
  defp source_category_for_observation(_type), do: nil
end
