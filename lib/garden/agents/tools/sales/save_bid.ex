defmodule GnomeGarden.Agents.Tools.SaveBid do
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
      lead_source_id: [type: :string, doc: "ID of the LeadSource"],
      posted_at: [type: :string, doc: "Posted date (ISO8601)"],
      due_at: [type: :string, doc: "Due date (ISO8601)"],
      estimated_value: [type: :float, doc: "Estimated value"],
      scores: [type: :map, doc: "Pre-calculated scores"]
    ]

  require Logger

  @impl true
  def run(params, _context) do
    # Check if bid already exists
    case find_existing(params) do
      {:ok, existing} ->
        {:ok,
         %{
           id: existing.id,
           title: existing.title,
           already_exists: true,
           message: "Bid already exists: #{existing.title}"
         }}

      :not_found ->
        create_bid(params)
    end
  end

  defp find_existing(%{url: url}) do
    case Ash.read(GnomeGarden.Agents.Bid, filter: [url: url]) do
      {:ok, [existing | _]} -> {:ok, existing}
      {:ok, []} -> :not_found
      _ -> :not_found
    end
  end

  defp create_bid(params) do
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
        lead_source_id: Map.get(params, :lead_source_id),
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
        keywords_matched: Map.get(params, :keywords_matched, []),
        keywords_rejected: Map.get(params, :keywords_rejected, [])
      }
      |> Enum.reject(fn {_k, v} -> is_nil(v) end)
      |> Map.new()

    case Ash.create(GnomeGarden.Agents.Bid, attrs) do
      {:ok, bid} ->
        Logger.info(
          "[SaveBid] Created bid: #{bid.title} (score: #{bid.score_total}, tier: #{bid.score_tier})"
        )

        {:ok,
         %{
           id: bid.id,
           title: bid.title,
           score_total: bid.score_total,
           score_tier: bid.score_tier,
           message: "Saved bid: #{bid.title}"
         }}

      {:error, error} ->
        {:error, "Failed to save bid: #{inspect(error)}"}
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
end
