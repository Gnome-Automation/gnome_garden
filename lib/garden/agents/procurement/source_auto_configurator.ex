defmodule GnomeGarden.Agents.Procurement.SourceAutoConfigurator do
  @moduledoc """
  Configures known procurement portals immediately and delegates unknown portals to discovery.
  """

  alias GnomeGarden.Agents.Procurement.SourceConfigurator
  alias GnomeGarden.Procurement
  alias GnomeGarden.Procurement.ProcurementSource

  @type configure_result ::
          {:ok,
           %{
             source: ProcurementSource.t(),
             mode:
               :auto_configured
               | :already_configured
               | :discovery_started
               | :already_pending
           }}
          | {:error, term()}

  @spec configure_source(ProcurementSource.t() | Ecto.UUID.t(), keyword()) :: configure_result
  def configure_source(source_or_id, opts \\ []) do
    actor = Keyword.get(opts, :actor)
    async? = Keyword.get(opts, :async?, true)

    with {:ok, source} <- fetch_source(source_or_id, actor),
         :ok <- ensure_approved(source) do
      cond do
        source.config_status == :configured ->
          {:ok, %{source: source, mode: :already_configured}}

        source.config_status == :pending ->
          {:ok, %{source: source, mode: :already_pending}}

        config = known_provider_config(source) ->
          configure_known_provider(source, config, actor)

        true ->
          start_discovery(source, actor, async?)
      end
    end
  end

  defp fetch_source(%ProcurementSource{} = source, _actor), do: {:ok, source}

  defp fetch_source(id, actor) when is_binary(id) do
    Procurement.get_procurement_source(id, actor_opts(actor))
  end

  defp ensure_approved(%{status: :approved}), do: :ok
  defp ensure_approved(_source), do: {:error, "Only approved sources can be configured."}

  defp configure_known_provider(source, config, actor) do
    case Procurement.configure_procurement_source(
           source,
           %{scrape_config: config},
           actor_opts(actor)
         ) do
      {:ok, configured_source} ->
        {:ok, %{source: configured_source, mode: :auto_configured}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp start_discovery(source, actor, async?) do
    case SourceConfigurator.discover_source(
           source,
           Keyword.put(actor_opts(actor), :async?, async?)
         ) do
      {:ok, %{source: source, mode: :started}} ->
        {:ok, %{source: source, mode: :discovery_started}}

      {:ok, %{source: source, mode: :already_pending}} ->
        {:ok, %{source: source, mode: :already_pending}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp known_provider_config(%{source_type: :planetbids} = source) do
    %{
      listing_url: source.url,
      listing_selector: "table tbody tr",
      title_selector: "td:nth-child(2)",
      date_selector: "td:nth-child(4)",
      link_selector: "td:nth-child(2)",
      pagination: %{
        type: "numbered",
        selector: ".pagination a"
      },
      notes: "Standard PlanetBids table configuration applied automatically."
    }
  end

  defp known_provider_config(%{source_type: :bidnet} = source) do
    %{
      listing_url: source.url,
      provider: "bidnet_direct",
      strategy: "bidnet_direct",
      search_keywords: metadata_value(source.metadata, "search_keywords") || [],
      notes: "Keyword-filtered BidNet Direct configuration applied automatically."
    }
  end

  defp known_provider_config(_source), do: nil

  defp metadata_value(metadata, key) when is_map(metadata) do
    Map.get(metadata, key) || Map.get(metadata, String.to_existing_atom(key))
  rescue
    ArgumentError -> nil
  end

  defp metadata_value(_metadata, _key), do: nil

  defp actor_opts(nil), do: []
  defp actor_opts(actor), do: [actor: actor]
end
