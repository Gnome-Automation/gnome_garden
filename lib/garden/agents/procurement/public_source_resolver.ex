defmodule GnomeGarden.Agents.Procurement.PublicSourceResolver do
  @moduledoc """
  Best-effort canonical public-source resolution for aggregated procurement hits.

  Aggregators and paid portals are useful discovery surfaces, but the operator
  should work from the free/public source when we can identify it confidently.
  """

  require Logger

  alias GnomeGarden.Agents.Tools.Procurement.QuerySamGov
  alias GnomeGarden.Procurement.SourceCredentials

  @default_resolution_limit 5
  @sam_match_threshold 0.86

  @spec resolve_bids([map()], map(), map()) :: {:ok, [map()]}
  def resolve_bids(bids, source, context \\ %{}) when is_list(bids) do
    if sam_resolution_source?(source, context) do
      resolve_sam_bids(bids, source, context)
    else
      {:ok, bids}
    end
  end

  defp resolve_sam_bids(bids, source, context) do
    case sam_api_key(context) do
      {:ok, api_key} ->
        query_context = Map.put(context, :sam_gov_api_key, api_key)
        limit = resolution_limit(source, context)
        {to_resolve, passthrough} = Enum.split(bids, limit)

        resolved =
          Enum.map(to_resolve, fn bid ->
            resolve_sam_bid(bid, query_context)
          end)

        {:ok, resolved ++ passthrough}

      {:error, reason} ->
        Logger.debug("Skipping SAM.gov public-source resolution: #{inspect(reason)}")
        {:ok, bids}
    end
  end

  defp resolve_sam_bid(bid, context) do
    title = bid_value(bid, :title)

    if blank?(title) do
      bid
    else
      params = %{keywords: title, naics_codes: [], limit: 5}

      case QuerySamGov.run(params, context) do
        {:ok, %{bids: sam_bids}} ->
          case best_sam_match(title, sam_bids) do
            {sam_bid, match_score} ->
              merge_sam_match(bid, sam_bid, match_score)

            nil ->
              bid
          end

        {:error, reason} ->
          Logger.debug("SAM.gov public-source resolution failed for #{title}: #{inspect(reason)}")
          bid
      end
    end
  end

  defp best_sam_match(title, sam_bids) do
    sam_bids
    |> Enum.map(fn sam_bid -> {sam_bid, title_match_score(title, bid_value(sam_bid, :title))} end)
    |> Enum.filter(fn {_sam_bid, score} -> score >= @sam_match_threshold end)
    |> Enum.max_by(fn {_sam_bid, score} -> score end, fn -> nil end)
  end

  defp merge_sam_match(bid, sam_bid, match_score) do
    canonical_url = bid_value(sam_bid, :url)
    canonical_source = canonical_source_metadata(sam_bid, match_score)

    alternate_urls =
      [
        bid_value(bid, :url),
        bid_value(bid, :link),
        bid_value(bid, :source_url)
      ]
      |> Enum.filter(&(is_binary(&1) and &1 != ""))
      |> Enum.uniq()

    metadata =
      bid
      |> bid_value(:metadata)
      |> metadata_map()
      |> deep_merge(%{
        "canonical_source" => canonical_source,
        "alternate_source_urls" => alternate_urls,
        "sam_gov" => %{
          "naics_code" => bid_value(sam_bid, :naics_code),
          "set_aside" => bid_value(sam_bid, :set_aside),
          "notice_type" => bid_value(sam_bid, :notice_type),
          "raw_metadata" => bid_value(sam_bid, :metadata) || %{}
        }
      })

    bid
    |> put_if_present(:url, canonical_url)
    |> put_if_present(:link, canonical_url)
    |> put_if_present(:external_id, bid_value(sam_bid, :external_id))
    |> put_if_present(:agency, bid_value(sam_bid, :agency))
    |> put_if_present(:location, bid_value(sam_bid, :location))
    |> put_if_present(:posted_at, bid_value(sam_bid, :posted_at))
    |> put_if_present(:due_at, bid_value(sam_bid, :due_date) || bid_value(sam_bid, :due_at))
    |> put_if_present(:description, preferred_description(bid, sam_bid))
    |> put_if_present(:naics_code, bid_value(sam_bid, :naics_code))
    |> put_if_present(:set_aside, bid_value(sam_bid, :set_aside))
    |> put_if_present(:notice_type, bid_value(sam_bid, :notice_type))
    |> Map.put(:source_type, :sam_gov)
    |> Map.put(:metadata, metadata)
  end

  defp canonical_source_metadata(sam_bid, match_score) do
    raw_metadata = bid_value(sam_bid, :metadata) || %{}

    %{
      "source_type" => "sam_gov",
      "url" => bid_value(sam_bid, :url),
      "notice_id" => bid_value(sam_bid, :external_id),
      "title" => bid_value(sam_bid, :title),
      "agency" => bid_value(sam_bid, :agency),
      "notice_type" => bid_value(sam_bid, :notice_type),
      "solicitation_number" => metadata_value(raw_metadata, "solicitationNumber"),
      "match_confidence" => Float.round(match_score, 2),
      "resolved_at" => DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()
    }
  end

  defp preferred_description(bid, sam_bid) do
    current = bid_value(bid, :description)
    sam_description = bid_value(sam_bid, :description)

    cond do
      blank?(sam_description) -> nil
      blank?(current) -> sam_description
      String.length(to_string(current)) < 80 -> sam_description
      true -> nil
    end
  end

  defp title_match_score(left, right) when is_binary(left) and is_binary(right) do
    normalized_left = normalize_title(left)
    normalized_right = normalize_title(right)

    cond do
      normalized_left == "" or normalized_right == "" ->
        0.0

      normalized_left == normalized_right ->
        1.0

      String.length(normalized_left) > 20 and String.contains?(normalized_right, normalized_left) ->
        0.95

      String.length(normalized_right) > 20 and String.contains?(normalized_left, normalized_right) ->
        0.95

      true ->
        token_similarity(normalized_left, normalized_right)
    end
  end

  defp title_match_score(_left, _right), do: 0.0

  defp token_similarity(left, right) do
    left_tokens = title_tokens(left)
    right_tokens = title_tokens(right)
    union_count = MapSet.union(left_tokens, right_tokens) |> MapSet.size()

    if union_count == 0 do
      0.0
    else
      intersection_count = MapSet.intersection(left_tokens, right_tokens) |> MapSet.size()
      intersection_count / union_count
    end
  end

  defp title_tokens(title) do
    title
    |> String.split(" ", trim: true)
    |> Enum.reject(&(String.length(&1) < 2))
    |> MapSet.new()
  end

  defp normalize_title(title) do
    title
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/, " ")
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
  end

  defp sam_resolution_source?(source, context) do
    source_type = Map.get(source, :source_type) || Map.get(source, "source_type")

    source_type in [:bidnet, "bidnet"] and
      not truthy?(context_value(context, [:disable_public_source_resolution?])) and
      not truthy?(
        metadata_value(Map.get(source, :metadata) || %{}, "disable_public_source_resolution")
      )
  end

  defp sam_api_key(context) do
    case context_value(context, [:sam_gov_api_key]) do
      value when is_binary(value) and value != "" -> {:ok, value}
      _ -> SourceCredentials.sam_gov_api_key()
    end
  end

  defp resolution_limit(source, context) do
    [
      context_value(context, [:public_source_resolution_limit]),
      metadata_value(Map.get(source, :metadata) || %{}, "public_source_resolution_limit"),
      @default_resolution_limit
    ]
    |> Enum.find_value(&positive_integer/1)
  end

  defp positive_integer(value) when is_integer(value) and value > 0, do: value

  defp positive_integer(value) when is_binary(value) do
    case Integer.parse(value) do
      {integer, ""} when integer > 0 -> integer
      _ -> nil
    end
  end

  defp positive_integer(_value), do: nil

  defp put_if_present(map, _key, nil), do: map
  defp put_if_present(map, _key, ""), do: map
  defp put_if_present(map, key, value), do: Map.put(map, key, value)

  defp metadata_map(metadata) when is_map(metadata), do: metadata
  defp metadata_map(_metadata), do: %{}

  defp metadata_value(metadata, key) when is_map(metadata) do
    Map.get(metadata, key) || Map.get(metadata, String.to_atom(key))
  rescue
    ArgumentError -> nil
  end

  defp metadata_value(_metadata, _key), do: nil

  defp bid_value(bid, key) when is_map(bid) and is_atom(key) do
    Map.get(bid, key) || Map.get(bid, Atom.to_string(key))
  end

  defp blank?(value), do: is_nil(value) or (is_binary(value) and String.trim(value) == "")

  defp truthy?(value), do: value in [true, "true", 1, "1"]

  defp context_value(context, [key]) when is_map(context) do
    tool_context = Map.get(context, :tool_context, context)
    Map.get(tool_context, key) || Map.get(tool_context, Atom.to_string(key))
  end

  defp context_value(context, [key | rest]) when is_map(context) do
    tool_context = Map.get(context, :tool_context, context)

    case Map.get(tool_context, key) || Map.get(tool_context, Atom.to_string(key)) do
      %{} = nested -> context_value(nested, rest)
      _ -> nil
    end
  end

  defp context_value(_context, _path), do: nil

  defp deep_merge(left, right) when is_map(left) and is_map(right) do
    Map.merge(left, right, fn _key, left_value, right_value ->
      deep_merge(left_value, right_value)
    end)
  end

  defp deep_merge(_left, right), do: right
end
