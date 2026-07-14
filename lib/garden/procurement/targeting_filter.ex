defmodule GnomeGarden.Procurement.TargetingFilter do
  @moduledoc """
  Lightweight prefiltering for procurement intake using company-profile
  exclusions and persisted source targeting policy.

  This operates before scoring so obviously out-of-lane listings can be dropped
  earlier in the pipeline. Source filters only affect intake when their
  metadata contains `targeting_mode` set to `"include"` or `"exclude"`.
  Existing provider query filters therefore remain query-only until an
  operator explicitly promotes them into an intake policy.
  """

  @type filter_result :: %{
          kept: [map()],
          excluded: [map()],
          filter_stats: [map()]
        }

  @spec filter_bids([map()], map(), keyword()) :: filter_result()
  def filter_bids(bids, profile_context, opts \\ []) do
    exclude_keywords = Map.get(profile_context, :exclude_keywords, [])
    source_filters = Keyword.get(opts, :source_filters, [])
    policy = targeting_policy(source_filters)

    result =
      Enum.reduce(bids, %{kept: [], excluded: [], matched: %{}}, fn bid, acc ->
        text = bid_text(bid)
        include_matches = matching_filters(text, policy.include)
        exclude_matches = matching_filters(text, policy.exclude)

        acc = record_matches(acc, include_matches ++ exclude_matches)

        cond do
          excluded_bid?(bid, exclude_keywords) ->
            %{acc | excluded: [bid | acc.excluded]}

          exclude_matches != [] ->
            %{acc | excluded: [annotate_bid(bid, List.first(exclude_matches)) | acc.excluded]}

          policy.include != [] and include_matches == [] ->
            %{acc | excluded: [bid | acc.excluded]}

          true ->
            %{acc | kept: [annotate_bid(bid, List.first(include_matches)) | acc.kept]}
        end
      end)

    %{
      kept: Enum.reverse(result.kept),
      excluded: Enum.reverse(result.excluded),
      filter_stats: filter_stats(source_filters, result.matched)
    }
  end

  @spec excluded_bid?(map(), [String.t()]) :: boolean()
  def excluded_bid?(bid, exclude_keywords) do
    text = bid_text(bid)

    Enum.any?(exclude_keywords, &match_keyword?(text, &1))
  end

  defp targeting_policy(source_filters) do
    Enum.reduce(source_filters, %{include: [], exclude: []}, fn filter, acc ->
      mode = metadata_value(filter, "targeting_mode")

      if filter_type(filter) == :keyword and mode in ["include", "exclude"] and
           filter_value(filter) not in [nil, ""] do
        Map.update!(acc, String.to_existing_atom(mode), &[filter | &1])
      else
        acc
      end
    end)
  end

  defp matching_filters(text, filters) do
    Enum.filter(filters, fn filter ->
      match_keyword?(text, filter_value(filter))
    end)
  end

  defp record_matches(acc, filters) do
    Enum.reduce(filters, acc, fn filter, acc ->
      key = filter_id(filter)

      Map.update(acc.matched, key, 1, &(&1 + 1))
      |> then(&%{acc | matched: &1})
    end)
  end

  defp filter_stats(source_filters, matched) do
    source_filters
    |> Enum.filter(fn filter ->
      filter_type(filter) == :keyword and
        metadata_value(filter, "targeting_mode") in ["include", "exclude"] and
        filter_value(filter) not in [nil, ""]
    end)
    |> Enum.map(fn filter ->
      %{
        "id" => filter_id(filter),
        "type" => Atom.to_string(filter_type(filter)),
        "value" => filter_value(filter),
        "mode" => metadata_value(filter, "targeting_mode"),
        "matched" => Map.get(matched, filter_id(filter), 0)
      }
    end)
  end

  defp annotate_bid(bid, nil), do: bid

  defp annotate_bid(bid, filter) do
    bid
    |> Map.put(:search_filter_id, filter_id(filter))
    |> Map.put(:search_filter_type, filter_type(filter))
    |> Map.put(:search_filter_value, filter_value(filter))
  end

  defp bid_text(bid) do
    [
      Map.get(bid, :title),
      Map.get(bid, :description),
      Map.get(bid, "title"),
      Map.get(bid, "description")
    ]
    |> List.flatten()
    |> Enum.reject(&is_nil/1)
    |> Enum.map(&to_string/1)
    |> Enum.join(" ")
    |> String.downcase()
  end

  defp filter_id(filter),
    do: Map.get(filter, :id) || Map.get(filter, "id") || filter_value(filter)

  defp filter_type(filter) do
    case Map.get(filter, :filter_type) || Map.get(filter, "filter_type") do
      "keyword" -> :keyword
      value -> value
    end
  end

  defp filter_value(filter), do: Map.get(filter, :value) || Map.get(filter, "value") || ""

  defp metadata_value(filter, key) do
    metadata = Map.get(filter, :metadata) || Map.get(filter, "metadata") || %{}
    Map.get(metadata, key) || Map.get(metadata, String.to_atom(key))
  end

  defp match_keyword?(text, keyword) when is_binary(keyword) do
    pattern = "\\b" <> Regex.escape(String.downcase(keyword)) <> "\\b"

    case Regex.compile(pattern) do
      {:ok, regex} -> Regex.match?(regex, text)
      _ -> String.contains?(text, String.downcase(keyword))
    end
  end

  defp match_keyword?(_text, _keyword), do: false
end
