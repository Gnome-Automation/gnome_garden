defmodule GnomeGarden.Agents.Procurement.SamGovScanner do
  @moduledoc """
  Scanner route for SAM.gov opportunities.

  The lower-level tool handles the public SAM.gov API request. This module keeps
  source-run behavior aligned with listing scanners: apply targeting, score,
  save qualified bids, and record source scan diagnostics.
  """

  require Logger

  alias GnomeGarden.Agents.Tools.Procurement.QuerySamGov
  alias GnomeGarden.Agents.Tools.Procurement.SaveBid
  alias GnomeGarden.Agents.Tools.Procurement.ScoreBid
  alias GnomeGarden.Commercial.CompanyProfileContext
  alias GnomeGarden.Procurement
  alias GnomeGarden.Procurement.ProcurementSource
  alias GnomeGarden.Procurement.TargetingFilter

  @default_limit 100

  def scan(%ProcurementSource{} = source, context \\ %{}) do
    profile_context = profile_context_for_source(source)

    with {:ok, query_result} <- QuerySamGov.run(query_params(source, profile_context), context),
         bids = Map.get(query_result, :bids, []),
         filtered = TargetingFilter.filter_bids(bids, profile_context),
         {:ok, scored} <- score_bids(filtered.kept, source, profile_context),
         {:ok, saved} <- save_qualifying_bids(scored, source, context) do
      complete_scan(source, bids, filtered.excluded, scored, saved, query_result)
    end
  end

  defp query_params(source, profile_context) do
    config = source.scrape_config || %{}

    %{
      keywords: config_value(config, "keywords") || config_value(config, "query"),
      naics_codes: config_value(config, "naics_codes") || profile_context.sam_gov_naics_codes,
      state: config_value(config, "state") || state_filter(source.region),
      limit:
        config_value(config, "limit") || config_value(config, "max_results") || @default_limit
    }
    |> Enum.reject(fn {_key, value} -> blank?(value) end)
    |> Map.new()
  end

  defp score_bids(bids, source, profile_context) do
    scored =
      bids
      |> Enum.map(fn bid ->
        params = %{
          title: bid_value(bid, :title) || "",
          description: bid_value(bid, :description) || "",
          agency: bid_value(bid, :agency) || source.name,
          location: bid_value(bid, :location) || region_to_location(source.region),
          estimated_value: estimated_value_for_scoring(bid_value(bid, :estimated_value)),
          region: source.region,
          source_type: source.source_type,
          source_name: source.name,
          source_url: source.url,
          company_profile_key: profile_context.company_profile_key,
          company_profile_mode: profile_context.company_profile_mode
        }

        {:ok, score_result} = ScoreBid.run(params, %{})

        Map.merge(bid, %{
          score: score_result,
          source_id: source.id,
          source_url: source.url
        })
      end)
      |> Enum.reject(&is_nil(bid_value(&1, :score)))

    {:ok, scored}
  end

  defp save_qualifying_bids(scored_bids, source, context) do
    saved =
      scored_bids
      |> Enum.filter(fn bid ->
        score = bid_value(bid, :score)
        score && score.score_tier != :rejected && Map.get(score, :save_candidate?, false)
      end)
      |> Enum.reject(fn bid ->
        due = bid_value(bid, :due_date) || bid_value(bid, :due_at)
        due != nil and DateTime.compare(due, DateTime.utc_now()) == :lt
      end)
      |> Enum.map(fn bid ->
        score = bid_value(bid, :score)

        params = %{
          title: bid_value(bid, :title),
          description: bid_value(bid, :description) || "",
          url: bid_value(bid, :url) || source.url,
          agency: bid_value(bid, :agency) || source.name,
          location: bid_value(bid, :location) || region_to_location(source.region),
          region: source.region,
          posted_at: bid_value(bid, :posted_at),
          due_at: bid_value(bid, :due_date) || bid_value(bid, :due_at),
          external_id: bid_value(bid, :external_id),
          source_url: bid_value(bid, :source_url) || source.url,
          estimated_value: bid_value(bid, :estimated_value),
          score_total: score.score_total,
          score_tier: score.score_tier,
          score_service_match: score.score_service_match,
          score_geography: score.score_geography,
          score_value: score.score_value,
          score_tech_fit: score.score_tech_fit,
          score_industry: score.score_industry,
          score_opportunity_type: score.score_opportunity_type,
          score_recommendation: Map.get(score, :recommendation),
          score_icp_matches: Map.get(score, :icp_matches, []),
          score_risk_flags: Map.get(score, :risk_flags, []),
          score_company_profile_key: Map.get(score, :company_profile_key),
          score_company_profile_mode: Map.get(score, :company_profile_mode),
          score_source_confidence: Map.get(score, :source_confidence),
          keywords_matched: score.keywords_matched,
          keywords_rejected: score.keywords_rejected,
          metadata: %{
            source: %{
              procurement_source_id: source.id,
              source_type: source.source_type,
              source_name: source.name,
              source_url: source.url,
              agent_run_id: agent_run_id_from_context(context)
            },
            sam_gov: %{
              naics_code: bid_value(bid, :naics_code),
              set_aside: bid_value(bid, :set_aside),
              notice_type: bid_value(bid, :notice_type),
              raw_metadata: bid_value(bid, :metadata) || %{}
            },
            scoring: %{
              recommendation: score.recommendation,
              company_profile_key: Map.get(score, :company_profile_key),
              company_profile_mode: Map.get(score, :company_profile_mode),
              icp_matches: Map.get(score, :icp_matches, []),
              risk_flags: Map.get(score, :risk_flags, []),
              source_confidence: Map.get(score, :source_confidence),
              save_candidate?: Map.get(score, :save_candidate?, false)
            }
          },
          procurement_source_id: source.id
        }

        case SaveBid.run(params, context) do
          {:ok, result} ->
            result

          {:error, reason} ->
            Logger.warning(
              "SaveBid failed for SAM.gov '#{bid_value(bid, :title) || "unknown"}': #{inspect(reason)}"
            )

            nil
        end
      end)
      |> Enum.reject(&is_nil/1)

    {:ok, saved}
  end

  defp complete_scan(source, bids, excluded, scored, saved, query_result) do
    source = current_source(source)
    diagnostics = scan_diagnostics(scored, saved, excluded)

    Procurement.mark_procurement_source_scanned!(
      source,
      %{
        metadata:
          source
          |> scan_metadata(bids, excluded, scored, saved, query_result, diagnostics)
          |> Map.put("last_scan_status", "success")
      },
      authorize?: false
    )

    {:ok,
     %{
       source_id: source.id,
       source_name: source.name,
       extracted: length(bids),
       excluded: length(excluded),
       scored: length(scored),
       saved: length(saved),
       enriched: 0,
       diagnostics: diagnostics
     }}
  end

  defp scan_metadata(source, bids, excluded, scored, saved, query_result, diagnostics) do
    summary = %{
      "extracted" => length(bids),
      "excluded" => length(excluded),
      "scored" => length(scored),
      "saved" => length(saved),
      "enriched" => 0,
      "diagnosis" => diagnostics["diagnosis"],
      "query" => Map.get(query_result, :query),
      "top_unsaved" => diagnostics["top_unsaved"],
      "saved_examples" => diagnostics["saved_examples"],
      "excluded_examples" => Enum.take(excluded, 5),
      "recorded_at" => DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()
    }

    source.metadata
    |> Map.new()
    |> Map.put("last_scan_summary", summary)
  end

  defp scan_diagnostics(scored, saved, excluded) do
    top_unsaved =
      scored
      |> Enum.reject(fn bid ->
        Enum.any?(saved, fn result ->
          bid_value(result, :url) == bid_value(bid, :url) ||
            bid_value(result, :title) == bid_value(bid, :title)
        end)
      end)
      |> Enum.sort_by(&score_total/1, :desc)
      |> Enum.take(5)
      |> Enum.map(fn bid ->
        score = bid_value(bid, :score) || %{}

        %{
          "title" => bid_value(bid, :title),
          "url" => bid_value(bid, :url),
          "score_total" => Map.get(score, :score_total),
          "score_tier" => Map.get(score, :score_tier),
          "recommendation" => Map.get(score, :recommendation),
          "risk_flags" => Map.get(score, :risk_flags, [])
        }
      end)

    %{
      "diagnosis" => scan_diagnosis(scored, saved, excluded, top_unsaved),
      "top_unsaved" => top_unsaved,
      "saved_examples" =>
        saved
        |> Enum.take(5)
        |> Enum.map(fn result ->
          %{
            "title" => bid_value(result, :title),
            "url" => bid_value(result, :url),
            "score_total" => bid_value(result, :score_total),
            "score_tier" => bid_value(result, :score_tier)
          }
        end)
    }
  end

  defp scan_diagnosis(_scored, [_ | _], _excluded, _top_unsaved), do: "saved_qualified_leads"

  defp scan_diagnosis([], _saved, [_ | _], _top_unsaved),
    do: "all_candidates_filtered_before_scoring"

  defp scan_diagnosis([], _saved, _excluded, _top_unsaved), do: "no_candidates_extracted"

  defp scan_diagnosis(_scored, _saved, _excluded, top_unsaved) do
    if Enum.any?(top_unsaved, &(&1["score_tier"] == :rejected or &1["score_tier"] == "rejected")) do
      "candidates_rejected_by_scoring"
    else
      "scored_but_below_save_threshold"
    end
  end

  defp profile_context_for_source(source) do
    CompanyProfileContext.resolve(
      profile_key: source.metadata && source.metadata["company_profile_key"],
      mode: source.metadata && source.metadata["company_profile_mode"]
    )
  end

  defp current_source(source) do
    case Procurement.get_procurement_source(source.id) do
      {:ok, current_source} -> current_source
      _ -> source
    end
  end

  defp score_total(bid) do
    case bid_value(bid, :score) do
      %{score_total: total} when is_number(total) -> total
      %{"score_total" => total} when is_number(total) -> total
      _ -> 0
    end
  end

  defp estimated_value_for_scoring(%Decimal{} = value), do: Decimal.to_float(value)
  defp estimated_value_for_scoring(value), do: value

  defp state_filter(:national), do: nil
  defp state_filter(:ca), do: "CA"
  defp state_filter(:oc), do: "CA"
  defp state_filter(:la), do: "CA"
  defp state_filter(:ie), do: "CA"
  defp state_filter(:sd), do: "CA"
  defp state_filter(:socal), do: "CA"
  defp state_filter(:norcal), do: "CA"
  defp state_filter(_region), do: nil

  defp region_to_location(:national), do: "United States"
  defp region_to_location(:oc), do: "Orange County, CA"
  defp region_to_location(:la), do: "Los Angeles County, CA"
  defp region_to_location(:ie), do: "Inland Empire, CA"
  defp region_to_location(:sd), do: "San Diego County, CA"
  defp region_to_location(:socal), do: "Southern California"
  defp region_to_location(:norcal), do: "Northern California"
  defp region_to_location(:ca), do: "California"
  defp region_to_location(_), do: nil

  defp bid_value(bid, key) when is_atom(key) do
    Map.get(bid, key) || Map.get(bid, Atom.to_string(key))
  end

  defp config_value(config, key) when is_map(config) do
    Map.get(config, key) || Map.get(config, String.to_existing_atom(key))
  rescue
    ArgumentError -> nil
  end

  defp blank?(nil), do: true
  defp blank?(""), do: true
  defp blank?([]), do: true
  defp blank?(_value), do: false

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

  defp nested_value(_map, _path), do: nil
end
