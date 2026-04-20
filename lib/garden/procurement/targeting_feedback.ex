defmodule GnomeGarden.Procurement.TargetingFeedback do
  @moduledoc """
  Normalizes operator feedback about bids that should not stay in the active
  procurement lane, and provides lightweight term suggestions for learning.
  """

  @cctv_terms ["cctv", "video surveillance", "security camera"]
  @access_control_terms ["access control", "badge system", "card access"]
  @fire_alarm_terms ["fire alarm", "alarm monitoring"]
  @audio_visual_terms ["audio visual", "av system", "conference room"]
  @pass_reasons [
    {"not_our_service_lane", "Not our service lane"},
    {"wrong_industry", "Wrong industry"},
    {"too_large_or_complex", "Too large or too complex"},
    {"too_small_or_low_value", "Too small or low value"},
    {"insufficient_capacity", "Insufficient capacity right now"},
    {"pricing_or_contract_risk", "Pricing or contract risk"},
    {"source_noise_or_misclassified", "Source noise or misclassified"},
    {"duplicate_or_already_covered", "Duplicate or already covered"},
    {"other", "Other"}
  ]

  @source_feedback_categories %{
    "source_noise_or_misclassified" => "noisy_source",
    "duplicate_or_already_covered" => "duplicate_intake",
    "pricing_or_contract_risk" => "commercial_risk",
    "too_large_or_complex" => "scope_mismatch",
    "too_small_or_low_value" => "value_mismatch",
    "wrong_industry" => "industry_mismatch",
    "not_our_service_lane" => "service_mismatch",
    "insufficient_capacity" => "timing_capacity"
  }

  @reason_label_map Map.new(@pass_reasons)

  @spec normalize_pass_feedback(map() | String.t()) :: map()
  def normalize_pass_feedback(reason) when is_binary(reason) do
    %{
      reason: String.trim(reason),
      reason_code: nil,
      feedback_scope: nil,
      exclude_terms: [],
      source_feedback_category: nil
    }
  end

  def normalize_pass_feedback(%{} = params) do
    reason_code = params |> map_value(:reason_code) |> normalize_reason_code()
    reason_text = params |> map_value(:reason) |> normalize_text()

    %{
      reason: reason_text || reason_label(reason_code),
      reason_code: reason_code,
      feedback_scope: map_value(params, :feedback_scope) |> normalize_text(),
      exclude_terms: params |> map_value(:exclude_terms) |> parse_terms(),
      source_feedback_category: source_feedback_category(reason_code)
    }
  end

  @spec pass_reason_options() :: [{String.t(), String.t()}]
  def pass_reason_options, do: Enum.map(@pass_reasons, fn {value, label} -> {label, value} end)

  @spec pass_reason_label(String.t() | nil) :: String.t()
  def pass_reason_label(nil), do: "Other"
  def pass_reason_label(reason_code), do: reason_label(reason_code) || "Other"

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
      "reason_code" => feedback.reason_code,
      "feedback_scope" => feedback.feedback_scope,
      "exclude_terms" => feedback.exclude_terms,
      "source_feedback_category" => feedback.source_feedback_category,
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

  defp normalize_reason_code(nil), do: nil

  defp normalize_reason_code(value) do
    value
    |> to_string()
    |> String.trim()
    |> case do
      "" ->
        nil

      code ->
        if Map.has_key?(@reason_label_map, code), do: code, else: "other"
    end
  end

  defp source_feedback_category(nil), do: nil

  defp source_feedback_category(reason_code),
    do: Map.get(@source_feedback_categories, reason_code, "other")

  defp reason_label(nil), do: nil
  defp reason_label(reason_code), do: Map.get(@reason_label_map, reason_code)

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
