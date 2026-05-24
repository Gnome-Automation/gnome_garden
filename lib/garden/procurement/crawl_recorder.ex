defmodule GnomeGarden.Procurement.CrawlRecorder do
  @moduledoc """
  Persists scan/crawl evidence without owning scanner behavior.
  """

  require Logger

  alias GnomeGarden.Procurement

  @max_artifact_chars 40_000

  def record_listing_scan(source, attrs) when is_map(attrs) do
    seed_url = Map.get(attrs, :listing_url) || source.url
    diagnostics = Map.get(attrs, :diagnostics, %{})
    extraction = Map.get(diagnostics, "extraction") || %{}
    scored = Map.get(attrs, :scored, [])
    saved = Map.get(attrs, :saved, [])
    excluded = Map.get(attrs, :excluded, [])

    with {:ok, run} <-
           Procurement.start_crawl_run(%{
             procurement_source_id: source.id,
             seed_url: seed_url,
             run_kind: :scan,
             max_depth: 0,
             max_pages: 1,
             metadata: %{
               "scanner" => "listing_scanner",
               "source_type" => Atom.to_string(source.source_type)
             }
           }),
         {:ok, page} <-
           Procurement.record_crawl_page(%{
             crawl_run_id: run.id,
             url: seed_url,
             normalized_url: normalize_url(seed_url),
             final_url: seed_url,
             title: source.name,
             depth: 0,
             content_hash: hash(extraction),
             fetch_status: :fetched,
             diagnostics: diagnostics,
             metadata: %{
               "source_name" => source.name,
               "source_url" => source.url
             }
           }),
         {:ok, _artifact} <- record_extraction_artifact(page, extraction),
         :ok <- record_candidates(run, page, scored, saved, excluded),
         {:ok, run} <-
           Procurement.complete_crawl_run(run, %{
             summary: summary(attrs),
             diagnostics: diagnostics
           }) do
      {:ok, run}
    else
      {:error, error} ->
        Logger.warning("Could not record crawl evidence for #{source.name}: #{inspect(error)}")
        {:error, error}
    end
  end

  defp record_extraction_artifact(page, extraction) do
    body =
      extraction
      |> Jason.encode!(pretty: true)
      |> String.slice(0, @max_artifact_chars)

    Procurement.record_page_artifact(%{
      crawl_page_id: page.id,
      kind: :extraction,
      body: body,
      byte_size: byte_size(body),
      content_hash: hash(body),
      metadata: %{
        "truncated" => String.length(body) >= @max_artifact_chars
      }
    })
  end

  defp record_candidates(run, page, scored, saved, excluded) do
    saved_keys =
      saved
      |> Enum.flat_map(fn result -> [value(result, :url), value(result, :title)] end)
      |> Enum.reject(&is_nil/1)
      |> MapSet.new()

    scored
    |> Enum.take(250)
    |> Enum.with_index()
    |> Enum.each(fn {bid, index} ->
      status = candidate_status(bid, saved_keys)

      _ =
        Procurement.propose_extraction_candidate(%{
          crawl_run_id: run.id,
          crawl_page_id: page.id,
          candidate_type: :bid,
          status: status,
          payload: payload_for_bid(bid),
          confidence: confidence_for_bid(bid),
          evidence: evidence_for_bid(bid, index),
          rejection_reason: rejection_reason(status, bid),
          content_hash: hash(payload_for_bid(bid)),
          metadata: %{"ordinal" => index}
        })
    end)

    excluded
    |> Enum.take(100)
    |> Enum.with_index()
    |> Enum.each(fn {bid, index} ->
      _ =
        Procurement.propose_extraction_candidate(%{
          crawl_run_id: run.id,
          crawl_page_id: page.id,
          candidate_type: :bid,
          status: :rejected,
          payload: payload_for_bid(bid),
          confidence: Decimal.new("0.0"),
          evidence: evidence_for_bid(bid, index),
          rejection_reason: "filtered_out",
          content_hash: hash(payload_for_bid(bid)),
          metadata: %{"ordinal" => index, "source" => "targeting_filter"}
        })
    end)

    :ok
  end

  defp candidate_status(bid, saved_keys) do
    if MapSet.member?(saved_keys, value(bid, :url)) or
         MapSet.member?(saved_keys, value(bid, :title)) do
      :accepted
    else
      :proposed
    end
  end

  defp rejection_reason(:accepted, _bid), do: nil
  defp rejection_reason(:proposed, bid), do: score_value(bid, :recommendation) || "not_saved"

  defp payload_for_bid(bid) do
    %{
      "title" => value(bid, :title),
      "url" => value(bid, :url) || value(bid, :link),
      "agency" => value(bid, :agency),
      "location" => value(bid, :location),
      "due_at" => value(bid, :due_at) || value(bid, :date),
      "description" => value(bid, :description),
      "score_total" => score_value(bid, :score_total),
      "score_tier" => score_value(bid, :score_tier)
    }
    |> Enum.reject(fn {_key, value} -> is_nil(value) or value == "" end)
    |> Map.new()
  end

  defp evidence_for_bid(bid, index) do
    %{
      "ordinal" => index,
      "score" => score_payload(value(bid, :score)),
      "source_url" => value(bid, :source_url)
    }
  end

  defp score_payload(nil), do: %{}

  defp score_payload(score) when is_map(score) do
    score
    |> Map.take([
      :score_total,
      :score_tier,
      :recommendation,
      :risk_flags,
      :icp_matches,
      :save_candidate?
    ])
    |> Enum.map(fn {key, value} -> {Atom.to_string(key), stringify_atom(value)} end)
    |> Map.new()
  end

  defp confidence_for_bid(bid) do
    case score_value(bid, :score_total) do
      total when is_integer(total) -> Decimal.div(Decimal.new(total), Decimal.new(100))
      total when is_float(total) -> Decimal.from_float(total / 100)
      _ -> nil
    end
  end

  defp summary(attrs) do
    %{
      "extracted" => length(Map.get(attrs, :bids, [])),
      "excluded" => length(Map.get(attrs, :excluded, [])),
      "scored" => length(Map.get(attrs, :scored, [])),
      "saved" => length(Map.get(attrs, :saved, [])),
      "enriched" => Map.get(attrs, :enriched, 0),
      "recorded_at" => DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()
    }
  end

  defp normalize_url(url) when is_binary(url) do
    url
    |> String.replace(~r/#.*$/, "")
    |> String.trim_trailing("/")
  end

  defp normalize_url(_), do: ""

  defp hash(value) do
    value
    |> stable_binary()
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end

  defp stable_binary(value) when is_binary(value), do: value
  defp stable_binary(value), do: Jason.encode!(value)

  defp value(map, key) when is_map(map),
    do: Map.get(map, key) || Map.get(map, Atom.to_string(key))

  defp value(_map, _key), do: nil

  defp score_value(bid, key) do
    case value(bid, :score) do
      score when is_map(score) -> Map.get(score, key) || Map.get(score, Atom.to_string(key))
      _ -> nil
    end
  end

  defp stringify_atom(value) when is_atom(value), do: Atom.to_string(value)
  defp stringify_atom(values) when is_list(values), do: Enum.map(values, &stringify_atom/1)
  defp stringify_atom(value), do: value
end
