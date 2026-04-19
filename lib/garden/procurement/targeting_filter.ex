defmodule GnomeGarden.Procurement.TargetingFilter do
  @moduledoc """
  Lightweight prefiltering for procurement intake using company-profile
  exclusions.

  This operates before scoring so obviously out-of-lane listings can be dropped
  earlier in the pipeline.
  """

  @spec filter_bids([map()], map()) :: %{kept: [map()], excluded: [map()]}
  def filter_bids(bids, profile_context) do
    exclude_keywords = Map.get(profile_context, :exclude_keywords, [])

    Enum.reduce(bids, %{kept: [], excluded: []}, fn bid, acc ->
      if excluded_bid?(bid, exclude_keywords) do
        %{acc | excluded: [bid | acc.excluded]}
      else
        %{acc | kept: [bid | acc.kept]}
      end
    end)
    |> then(fn result ->
      %{
        kept: Enum.reverse(result.kept),
        excluded: Enum.reverse(result.excluded)
      }
    end)
  end

  @spec excluded_bid?(map(), [String.t()]) :: boolean()
  def excluded_bid?(bid, exclude_keywords) do
    text =
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

    Enum.any?(exclude_keywords, &match_keyword?(text, &1))
  end

  defp match_keyword?(text, keyword) when is_binary(keyword) do
    pattern = "\\b" <> Regex.escape(String.downcase(keyword)) <> "\\b"

    case Regex.compile(pattern) do
      {:ok, regex} -> Regex.match?(regex, text)
      _ -> String.contains?(text, String.downcase(keyword))
    end
  end
end
