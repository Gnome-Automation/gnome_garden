defmodule GnomeGarden.Agents.Tools.Procurement.SaveBid do
  @moduledoc """
  Save a discovered bid opportunity to the database.

  Includes scoring and deduplication.
  """

  use Jido.Action,
    name: "save_bid",
    description: "Save a bid opportunity to the database with scoring",
    schema: [
      title: [type: :string, required: true, doc: "Bid title"],
      url: [type: :string, required: true, doc: "Bid URL"],
      external_id: [type: :string, doc: "External bid ID"],
      description: [type: :string, doc: "Bid description"],
      agency: [type: :string, doc: "Issuing agency"],
      location: [type: :string, doc: "Location"],
      region: [type: :atom, doc: "Region code"],
      source_url: [type: :string, doc: "URL of the source that found this"],
      procurement_source_id: [type: :string, doc: "ID of the ProcurementSource"],
      posted_at: [type: :string, doc: "Posted date (ISO8601)"],
      due_at: [type: :string, doc: "Due date (ISO8601)"],
      estimated_value: [type: :float, doc: "Estimated value"],
      score_recommendation: [type: :string, doc: "Human-readable scoring recommendation"],
      score_icp_matches: [type: {:array, :string}, doc: "Matched ICP lanes from scoring"],
      score_risk_flags: [type: {:array, :string}, doc: "Risk flags from scoring"],
      score_company_profile_key: [type: :string, doc: "Company profile key used to score"],
      score_company_profile_mode: [type: :string, doc: "Company profile mode used to score"],
      score_source_confidence: [type: :atom, doc: "Confidence level for the source family"],
      scores: [type: :map, doc: "Pre-calculated scores"],
      metadata: [type: :map, doc: "Additional source and scoring metadata"]
    ]

  require Logger

  alias GnomeGarden.Agents.RunOutputLogger
  alias GnomeGarden.Procurement

  @impl true
  def run(params, context) do
    # Check if bid already exists
    case find_existing(params) do
      {:ok, existing} ->
        existing = maybe_refresh_existing(existing, params, context)
        log_output(context, :existing, existing)

        {:ok,
         %{
           id: existing.id,
           title: existing.title,
           url: existing.url,
           already_exists: true,
           message: "Bid already exists: #{existing.title}"
         }}

      :not_found ->
        create_bid(params, context)
    end
  end

  defp find_existing(%{url: url}) do
    case Procurement.get_bid_by_url(url) do
      {:ok, existing} -> {:ok, existing}
      {:error, %Ash.Error.Query.NotFound{}} -> :not_found
      {:error, _error} -> :not_found
    end
  end

  defp create_bid(params, context) do
    attrs =
      %{
        title: params.title,
        url: params.url,
        external_id: Map.get(params, :external_id),
        description: Map.get(params, :description),
        agency: Map.get(params, :agency),
        location: Map.get(params, :location),
        region: Map.get(params, :region),
        source_url: Map.get(params, :source_url),
        procurement_source_id: Map.get(params, :procurement_source_id),
        posted_at: parse_datetime(Map.get(params, :posted_at)),
        due_at: parse_datetime(Map.get(params, :due_at)),
        estimated_value: Map.get(params, :estimated_value),
        # Include scores if provided at top level
        score_service_match: Map.get(params, :score_service_match),
        score_geography: Map.get(params, :score_geography),
        score_value: Map.get(params, :score_value),
        score_tech_fit: Map.get(params, :score_tech_fit),
        score_industry: Map.get(params, :score_industry),
        score_opportunity_type: Map.get(params, :score_opportunity_type),
        score_total: Map.get(params, :score_total),
        score_tier: Map.get(params, :score_tier),
        score_recommendation: Map.get(params, :score_recommendation),
        score_icp_matches: Map.get(params, :score_icp_matches, []),
        score_risk_flags: Map.get(params, :score_risk_flags, []),
        score_company_profile_key: Map.get(params, :score_company_profile_key),
        score_company_profile_mode: Map.get(params, :score_company_profile_mode),
        score_source_confidence: Map.get(params, :score_source_confidence),
        keywords_matched: Map.get(params, :keywords_matched, []),
        keywords_rejected: Map.get(params, :keywords_rejected, []),
        metadata:
          params
          |> metadata_param()
          |> Map.new()
          |> put_incoming_agent_run_id(agent_run_id_from_context(context))
      }
      |> Enum.reject(fn {_k, v} -> is_nil(v) end)
      |> Map.new()

    case Procurement.create_bid(attrs) do
      {:ok, bid} ->
        Logger.info(
          "[SaveBid] Created bid: #{bid.title} (score: #{bid.score_total}, tier: #{bid.score_tier})"
        )

        log_output(context, :created, bid)

        {:ok,
         %{
           id: bid.id,
           title: bid.title,
           url: bid.url,
           score_total: bid.score_total,
           score_tier: bid.score_tier,
           message: "Saved bid: #{bid.title}"
         }}

      {:error, error} ->
        {:error, "Failed to save bid: #{inspect(error)}"}
    end
  end

  defp maybe_refresh_existing(existing, params, context) do
    updates =
      %{}
      |> maybe_put_if_missing(:description, existing.description, Map.get(params, :description))
      |> maybe_put_if_missing(:due_at, existing.due_at, parse_datetime(Map.get(params, :due_at)))
      |> maybe_put_metadata(existing.metadata, params, agent_run_id_from_context(context))

    if map_size(updates) == 0 do
      existing
    else
      case Procurement.update_bid(existing, updates) do
        {:ok, bid} -> bid
        {:error, _error} -> existing
      end
    end
  end

  defp maybe_put_if_missing(updates, _key, existing, _value) when not is_nil(existing),
    do: updates

  defp maybe_put_if_missing(updates, _key, _existing, nil), do: updates
  defp maybe_put_if_missing(updates, _key, _existing, ""), do: updates
  defp maybe_put_if_missing(updates, key, _existing, value), do: Map.put(updates, key, value)

  defp maybe_put_metadata(updates, existing_metadata, params, agent_run_id) do
    incoming_metadata =
      params
      |> metadata_param()
      |> Map.new()
      |> put_incoming_agent_run_id(agent_run_id)

    existing_metadata = existing_metadata || %{}
    merged_metadata = deep_merge(existing_metadata, incoming_metadata)

    if merged_metadata == existing_metadata do
      updates
    else
      Map.put(updates, :metadata, merged_metadata)
    end
  end

  defp put_incoming_agent_run_id(metadata, nil), do: metadata

  defp put_incoming_agent_run_id(metadata, agent_run_id) do
    source =
      metadata
      |> Map.get(:source, Map.get(metadata, "source", %{}))
      |> case do
        source when is_map(source) -> source
        _ -> %{}
      end
      |> Map.put(:agent_run_id, agent_run_id)

    Map.put(metadata, :source, source)
  end

  defp metadata_param(params) do
    case Map.get(params, :metadata) do
      metadata when is_map(metadata) -> metadata
      _ -> %{}
    end
  end

  defp parse_datetime(nil), do: nil
  defp parse_datetime(%DateTime{} = dt), do: dt

  defp parse_datetime(str) when is_binary(str) do
    case DateTime.from_iso8601(str) do
      {:ok, dt, _} -> dt
      _ -> nil
    end
  end

  defp parse_datetime(_), do: nil

  defp deep_merge(left, right) when is_map(left) and is_map(right) do
    Map.merge(left, right, fn _key, left_value, right_value ->
      deep_merge(left_value, right_value)
    end)
  end

  defp deep_merge(_left, right), do: right

  defp agent_run_id_from_context(context) when is_map(context) do
    [
      nested_value(context, [:tool_context, :agent_run_id]),
      nested_value(context, [:tool_context, :runtime_instance_id]),
      nested_value(context, [:tool_context, :run_id]),
      nested_value(context, [:agent_run_id]),
      nested_value(context, [:runtime_instance_id]),
      nested_value(context, [:run_id])
    ]
    |> Enum.find(&persisted_run_id?/1)
  end

  defp agent_run_id_from_context(_context), do: nil

  defp persisted_run_id?(run_id) when is_binary(run_id) do
    match?({:ok, _run}, GnomeGarden.Agents.get_agent_run(run_id))
  end

  defp persisted_run_id?(_run_id), do: false

  defp nested_value(map, [key]) when is_map(map) do
    Map.get(map, key) || Map.get(map, Atom.to_string(key))
  end

  defp nested_value(map, [key | rest]) when is_map(map) do
    case nested_value(map, [key]) do
      %{} = nested -> nested_value(nested, rest)
      _ -> nil
    end
  end

  defp log_output(context, event, bid) do
    RunOutputLogger.log(context, %{
      output_type: :bid,
      output_id: bid.id,
      event: event,
      label: bid.title,
      summary: "#{event_label(event)} bid #{bid.title}",
      metadata: %{
        url: bid.url,
        agency: bid.agency,
        score_total: bid.score_total,
        score_tier: bid.score_tier,
        procurement_source_id: bid.procurement_source_id,
        signal_id: bid.signal_id
      }
    })
  end

  defp event_label(:created), do: "Created"
  defp event_label(:existing), do: "Reused existing"
end
