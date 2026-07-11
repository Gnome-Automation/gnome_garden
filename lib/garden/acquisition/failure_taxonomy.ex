defmodule GnomeGarden.Acquisition.FailureTaxonomy do
  @moduledoc """
  Canonical failure categories for acquisition source execution.

  Providers retain their detailed diagnosis in source metadata. This module
  maps those provider-specific details into stable categories used by baseline
  reporting, telemetry, and future routing policy.
  """

  @categories [
    :api,
    :http,
    :selectors,
    :credentials,
    :browser_runtime,
    :extraction,
    :scoring,
    :dedupe,
    :promotion,
    :unknown
  ]

  @spec categories() :: [atom()]
  def categories, do: @categories

  @spec classify(map()) :: atom() | nil
  def classify(source) when is_map(source) do
    diagnosis =
      source
      |> metadata_value(:metadata)
      |> metadata_value("last_scan_summary")
      |> metadata_value("diagnosis")

    reason =
      source
      |> metadata_value(:metadata)
      |> metadata_value("last_scan_summary")
      |> metadata_value("reason")

    classify_values(metadata_value(source, :health_status), diagnosis, reason)
  end

  defp classify_values(health, diagnosis, reason) do
    text = Enum.join(Enum.reject([diagnosis, reason], &is_nil/1), " ")

    cond do
      health in [:needs_login, :credentials_pending, :credentials_invalid] ->
        :credentials

      diagnosis == "login_required" ->
        :credentials

      health == :selector_failed ->
        :selectors

      diagnosis in [
        "selector_failed",
        "listing_selector_matched_no_rows",
        "title_selector_matched_no_titles"
      ] ->
        :selectors

      health == :document_capture_failed ->
        :extraction

      diagnosis in ["no_candidates_extracted", "document_capture_failed"] ->
        :extraction

      diagnosis in [
        "all_candidates_filtered_before_scoring",
        "scored_but_below_save_threshold",
        "candidates_rejected_by_scoring"
      ] ->
        :scoring

      contains_any?(text, ["rate limit", "quota", "api key", "api_error", "api error"]) ->
        :api

      contains_any?(text, ["http", "status 4", "status 5", "connection", "dns"]) ->
        :http

      contains_any?(text, ["browser", "chromium", "playwright", "waf"]) ->
        :browser_runtime

      contains_any?(text, ["duplicate", "already covered"]) ->
        :dedupe

      contains_any?(text, ["promotion", "promote"]) ->
        :promotion

      health in [:failing, :blocked] or
          diagnosis in ["scan_failed", "scanner_not_implemented", "page_unavailable"] ->
        :unknown

      true ->
        nil
    end
  end

  defp contains_any?(value, needles) when is_binary(value) do
    normalized = String.downcase(value)
    Enum.any?(needles, &String.contains?(normalized, &1))
  end

  defp metadata_value(map, key) when is_map(map) do
    Map.get(map, key) || Map.get(map, to_string(key))
  end

  defp metadata_value(_value, _key), do: nil
end
