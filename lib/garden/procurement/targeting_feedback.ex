defmodule GnomeGarden.Procurement.TargetingFeedback do
  @moduledoc """
  Normalizes operator feedback about bids that should not stay in the active
  procurement lane, and provides lightweight term suggestions for learning.
  """

  @cctv_terms ["cctv", "video surveillance", "security camera"]
  @access_control_terms ["access control", "badge system", "card access"]
  @fire_alarm_terms ["fire alarm", "alarm monitoring"]
  @audio_visual_terms ["audio visual", "av system", "conference room"]

  @spec normalize_pass_feedback(map() | String.t()) :: map()
  def normalize_pass_feedback(reason) when is_binary(reason) do
    %{
      reason: String.trim(reason),
      feedback_scope: nil,
      exclude_terms: []
    }
  end

  def normalize_pass_feedback(%{} = params) do
    %{
      reason: map_value(params, :reason) |> normalize_text(),
      feedback_scope: map_value(params, :feedback_scope) |> normalize_text(),
      exclude_terms: params |> map_value(:exclude_terms) |> parse_terms()
    }
  end

  @spec suggested_exclude_terms(map()) :: [String.t()]
  def suggested_exclude_terms(bid) do
    text = searchable_text([Map.get(bid, :title), Map.get(bid, :description)])

    []
    |> Kernel.++(List.wrap(Map.get(bid, :keywords_rejected)))
    |> maybe_add_group(text, ["cctv", "surveillance", "security camera"], @cctv_terms)
    |> maybe_add_group(text, ["access control", "badge", "card access"], @access_control_terms)
    |> maybe_add_group(text, ["fire alarm", "alarm monitoring"], @fire_alarm_terms)
    |> maybe_add_group(text, ["audio visual", "a/v", "conference room"], @audio_visual_terms)
    |> normalize_terms()
  end

  @spec suggested_exclude_terms_csv(map()) :: String.t()
  def suggested_exclude_terms_csv(bid) do
    bid
    |> suggested_exclude_terms()
    |> Enum.join(", ")
  end

  @spec metadata(map(), map()) :: map()
  def metadata(bid, feedback) do
    %{
      "reason" => feedback.reason,
      "feedback_scope" => feedback.feedback_scope,
      "exclude_terms" => feedback.exclude_terms,
      "captured_at" => DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601(),
      "company_profile_key" => Map.get(bid, :score_company_profile_key),
      "company_profile_mode" => Map.get(bid, :score_company_profile_mode)
    }
  end

  defp maybe_add_group(list, text, triggers, values) do
    if Enum.any?(triggers, &String.contains?(text, &1)) do
      list ++ values
    else
      list
    end
  end

  defp searchable_text(values) do
    values
    |> List.wrap()
    |> Enum.reject(&is_nil/1)
    |> Enum.map(&to_string/1)
    |> Enum.join(" ")
    |> String.downcase()
  end

  defp parse_terms(nil), do: []

  defp parse_terms(value) when is_binary(value) do
    value
    |> String.split([",", "\n"], trim: true)
    |> normalize_terms()
  end

  defp parse_terms(values), do: normalize_terms(values)

  defp normalize_terms(values) do
    values
    |> List.wrap()
    |> Enum.map(&to_string/1)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq()
  end

  defp map_value(map, key) do
    Map.get(map, key) || Map.get(map, Atom.to_string(key))
  end

  defp normalize_text(nil), do: nil
  defp normalize_text(value), do: value |> to_string() |> String.trim() |> blank_to_nil()

  defp blank_to_nil(""), do: nil
  defp blank_to_nil(value), do: value
end
