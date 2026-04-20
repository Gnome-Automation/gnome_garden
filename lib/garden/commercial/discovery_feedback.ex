defmodule GnomeGarden.Commercial.DiscoveryFeedback do
  @moduledoc """
  Structured operator feedback for discovery-record review.

  Discovery and procurement should teach the same company profile. This module
  normalizes discovery-review feedback into a durable shape that can be written
  to discovery-record metadata and fed back into company-profile learning.
  """

  @reject_reasons [
    {"Too generic / weak signal", "weak_signal_generic"},
    {"Out of our scope", "out_of_scope"},
    {"Wrong industry or market", "wrong_industry_market"},
    {"Wrong buyer / admin-side target", "wrong_buyer_admin"},
    {"Bad fit for current profile mode", "profile_mode_mismatch"},
    {"Duplicate / already covered", "duplicate_already_covered"},
    {"Bad source / noisy discovery", "source_noise_or_misclassified"},
    {"Keep watching, not ready", "not_ready_yet"},
    {"Other", "other"}
  ]

  @reason_label_map Map.new(@reject_reasons, fn {label, code} -> {code, label} end)

  @source_feedback_categories %{
    "weak_signal_generic" => "weak_signal",
    "out_of_scope" => "fit_gap",
    "wrong_industry_market" => "fit_gap",
    "wrong_buyer_admin" => "fit_gap",
    "profile_mode_mismatch" => "fit_gap",
    "duplicate_already_covered" => "duplicate",
    "source_noise_or_misclassified" => "source_noise",
    "not_ready_yet" => "timing"
  }

  defstruct [
    :reason,
    :reason_code,
    :feedback_scope,
    :source_feedback_category,
    exclude_terms: []
  ]

  @spec reject_reason_options() :: [{String.t(), String.t()}]
  def reject_reason_options, do: @reject_reasons

  @spec reject_reason_label(String.t() | nil) :: String.t()
  def reject_reason_label(reason_code), do: reason_label(reason_code) || "Other"

  @spec normalize_feedback(map() | String.t() | nil) :: %__MODULE__{}
  def normalize_feedback(nil), do: %__MODULE__{}

  def normalize_feedback(feedback) when is_binary(feedback) do
    %__MODULE__{reason: blank_to_nil(feedback)}
  end

  def normalize_feedback(params) when is_map(params) do
    reason_code = params |> map_value(:reason_code) |> normalize_reason_code()
    reason_text = params |> map_value(:reason) |> blank_to_nil()
    feedback_scope = params |> map_value(:feedback_scope) |> blank_to_nil()

    %__MODULE__{
      reason: reason_text || reason_label(reason_code),
      reason_code: reason_code,
      feedback_scope: feedback_scope,
      source_feedback_category: source_feedback_category(reason_code),
      exclude_terms: normalize_terms(params |> map_value(:exclude_terms))
    }
  end

  @spec feedback_metadata(%__MODULE__{}) :: map()
  def feedback_metadata(%__MODULE__{} = feedback) do
    %{
      "reason" => feedback.reason,
      "reason_code" => feedback.reason_code,
      "feedback_scope" => feedback.feedback_scope,
      "exclude_terms" => feedback.exclude_terms,
      "source_feedback_category" => feedback.source_feedback_category
    }
    |> Enum.reject(fn {_key, value} -> value in [nil, [], ""] end)
    |> Map.new()
  end

  defp source_feedback_category(nil), do: nil

  defp source_feedback_category(reason_code),
    do: Map.get(@source_feedback_categories, reason_code, "other")

  defp normalize_reason_code(nil), do: nil

  defp normalize_reason_code(value) do
    value
    |> to_string()
    |> String.trim()
    |> case do
      "" -> nil
      code -> if Map.has_key?(@reason_label_map, code), do: code, else: "other"
    end
  end

  defp reason_label(nil), do: nil
  defp reason_label(reason_code), do: Map.get(@reason_label_map, reason_code)

  defp normalize_terms(nil), do: []

  defp normalize_terms(value) when is_binary(value) do
    value
    |> String.split(",")
    |> normalize_terms()
  end

  defp normalize_terms(values) do
    values
    |> List.wrap()
    |> Enum.map(&to_string/1)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq()
  end

  defp map_value(map, key) do
    Map.get(map, Atom.to_string(key)) || Map.get(map, key)
  end

  defp blank_to_nil(nil), do: nil

  defp blank_to_nil(value) do
    value
    |> to_string()
    |> String.trim()
    |> case do
      "" -> nil
      trimmed -> trimmed
    end
  end
end
