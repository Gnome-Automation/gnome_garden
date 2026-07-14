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
  alias GnomeGarden.Company.ProfileContext, as: CompanyProfileContext
  alias GnomeGarden.Procurement
  alias GnomeGarden.Procurement.ProcurementSource
  alias GnomeGarden.Procurement.SourceSearchFilter
  alias GnomeGarden.Procurement.TargetingFilter

  @default_limit 5

  def scan(%ProcurementSource{} = source, context \\ %{}) do
    profile_context = profile_context_for_source(source)

    result =
      with {:ok, query_result} <- query_sam_gov(source, profile_context, context),
           bids = Map.get(query_result, :bids, []),
           filtered = TargetingFilter.filter_bids(bids, profile_context),
           {:ok, scored} <- score_bids(filtered.kept, source, profile_context),
           {:ok, saved} <- save_qualifying_bids(scored, source, context) do
        complete_scan(source, bids, filtered.excluded, scored, saved, query_result)
      end

    case result do
      {:ok, _payload} = ok ->
        ok

      {:error, {:rate_limited, retry_at} = reason} ->
        defer_scan(source, reason, retry_at)

      {:error, {:budget_exhausted, reset_at, _remaining} = reason} ->
        defer_scan(source, reason, reset_at)

      {:error, reason} ->
        fail_scan(source, reason)
    end
  end

  defp query_sam_gov(source, profile_context, context) do
    source
    |> query_param_sets(profile_context)
    |> Enum.reduce_while({:ok, []}, fn params, {:ok, results} ->
      case QuerySamGov.run(params, context) do
        {:ok, result} ->
          {:cont,
           {:ok,
            [annotate_query_result(result, Map.get(params, :source_search_filter)) | results]}}

        {:error, error} ->
          {:halt, {:error, error}}
      end
    end)
    |> case do
      {:ok, results} ->
        bids =
          results
          |> Enum.flat_map(&Map.get(&1, :bids, []))
          |> Enum.uniq_by(&bid_identity/1)

        {:ok,
         %{
           source_type: :sam_gov,
           query: query_summary(results),
           bids_found: length(bids),
           bids: bids,
           query_count: length(results),
           search_filter_counts: search_filter_counts(results)
         }}

      {:error, error} ->
        {:error, error}
    end
  end

  defp query_param_sets(source, profile_context) do
    base = query_params(source, profile_context)

    source_search_filters(source)
    |> case do
      [] -> fallback_query_param_sets(base)
      filters -> Enum.map(filters, &filter_query_params(base, &1))
    end
    |> Enum.map(&normalize_query_params/1)
    |> Enum.uniq_by(&query_identity/1)
    |> Enum.map(&with_query_identity(&1, source))
  end

  defp fallback_query_param_sets(base) do
    codes = List.wrap(Map.get(base, :naics_codes))

    case codes do
      [] -> [base]
      codes -> Enum.map(codes, &Map.put(base, :naics_codes, [&1]))
    end
  end

  defp filter_query_params(base, %SourceSearchFilter{filter_type: :naics} = filter) do
    base
    |> Map.delete(:keywords)
    |> Map.put(:naics_codes, [filter.value])
    |> Map.put(:limit, filter.per_run_limit || @default_limit)
    |> Map.put(:source_search_filter, filter)
  end

  defp filter_query_params(base, %SourceSearchFilter{filter_type: :keyword} = filter) do
    base
    |> Map.put(:keywords, filter.value)
    |> Map.put(:limit, filter.per_run_limit || @default_limit)
    |> Map.put(:source_search_filter, filter)
  end

  defp filter_query_params(base, %SourceSearchFilter{filter_type: :state} = filter) do
    base
    |> Map.put(:state, filter.value)
    |> Map.put(:limit, filter.per_run_limit || @default_limit)
    |> Map.put(:source_search_filter, filter)
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
          notice_type: bid_value(bid, :notice_type),
          set_aside: bid_value(bid, :set_aside),
          keywords: score_keywords(bid),
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
              search_filter_id: bid_value(bid, :search_filter_id),
              search_filter_type: bid_value(bid, :search_filter_type),
              search_filter_value: bid_value(bid, :search_filter_value),
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
            |> Map.put(:search_filter_id, bid_value(bid, :search_filter_id))
            |> Map.put(:search_filter_value, bid_value(bid, :search_filter_value))

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

  defp score_keywords(bid) do
    [
      bid_value(bid, :notice_type),
      bid_value(bid, :set_aside)
    ]
    |> Enum.reject(&blank?/1)
    |> Enum.join(" ")
  end

  defp complete_scan(source, bids, excluded, scored, saved, query_result) do
    source = current_source(source)
    diagnostics = scan_diagnostics(scored, saved, excluded)
    record_search_filter_counts(query_result, saved)

    source =
      if source.deferred_until do
        case Procurement.clear_procurement_source_scan_deferral(source, authorize?: false) do
          {:ok, source} -> source
          {:error, _error} -> source
        end
      else
        source
      end

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

  defp fail_scan(source, reason) do
    source = current_source(source)

    _ =
      Procurement.scan_fail_procurement_source(
        source,
        %{
          metadata:
            source.metadata
            |> Map.new()
            |> Map.put("last_scan_status", "failed")
            |> Map.put("last_scan_summary", scan_failure_summary(reason))
        },
        authorize?: false
      )

    {:error, reason}
  end

  defp defer_scan(source, reason, deferred_until) do
    source = current_source(source)

    case Procurement.defer_procurement_source_scan(
           source,
           %{
             deferred_until: deferred_until,
             defer_reason: format_reason(reason)
           },
           authorize?: false
         ) do
      {:ok, _source} -> {:error, {:deferred, reason, deferred_until}}
      {:error, error} -> {:error, {:deferral_failed, reason, error}}
    end
  end

  defp scan_failure_summary(reason) do
    %{
      "extracted" => 0,
      "excluded" => 0,
      "scored" => 0,
      "saved" => 0,
      "enriched" => 0,
      "diagnosis" => "scan_failed",
      "reason" => format_reason(reason),
      "recorded_at" => DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()
    }
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
      "query_count" => Map.get(query_result, :query_count),
      "search_filter_counts" => Map.get(query_result, :search_filter_counts, []),
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

  defp bid_identity(bid) do
    bid_value(bid, :external_id) || bid_value(bid, :url) || bid_value(bid, :title)
  end

  defp normalize_query_params(params) do
    params
    |> normalize_keywords()
    |> normalize_naics_codes()
    |> normalize_state()
    |> normalize_limit()
  end

  defp normalize_keywords(params) do
    case Map.get(params, :keywords) do
      value when is_binary(value) ->
        Map.put(params, :keywords, String.trim(value))

      _value ->
        Map.delete(params, :keywords)
    end
  end

  defp normalize_naics_codes(params) do
    codes =
      params
      |> Map.get(:naics_codes, [])
      |> List.wrap()
      |> Enum.map(&(&1 |> to_string() |> String.trim()))
      |> Enum.reject(&(&1 == ""))
      |> Enum.uniq()
      |> Enum.sort()

    if codes == [],
      do: Map.delete(params, :naics_codes),
      else: Map.put(params, :naics_codes, codes)
  end

  defp normalize_state(params) do
    case Map.get(params, :state) do
      value when is_binary(value) ->
        Map.put(params, :state, value |> String.trim() |> String.upcase())

      _value ->
        Map.delete(params, :state)
    end
  end

  defp normalize_limit(params) do
    limit = params |> Map.get(:limit, @default_limit) |> normalize_integer(@default_limit)
    Map.put(params, :limit, min(max(limit, 1), 1_000))
  end

  defp normalize_integer(value, _default) when is_integer(value), do: value

  defp normalize_integer(value, default) when is_binary(value) do
    case Integer.parse(value) do
      {integer, ""} -> integer
      _error -> default
    end
  end

  defp normalize_integer(_value, default), do: default

  defp query_identity(params) do
    params
    |> Map.drop([:source_search_filter, :idempotency_key, :source_id])
    |> Map.update(:keywords, nil, fn
      value when is_binary(value) -> String.downcase(value)
      value -> value
    end)
    |> Enum.sort()
  end

  defp with_query_identity(params, source) do
    fingerprint =
      params
      |> query_identity()
      |> :erlang.term_to_binary()
      |> then(&:crypto.hash(:sha256, &1))
      |> Base.encode16(case: :lower)

    params
    |> Map.put(:source_id, source.id)
    |> maybe_put_provider_request_limit(source.rate_limit_per_day)
    |> Map.put(
      :idempotency_key,
      "sam_gov:#{source.id}:#{Date.to_iso8601(Date.utc_today())}:#{fingerprint}"
    )
  end

  defp maybe_put_provider_request_limit(params, limit) when is_integer(limit) and limit > 0,
    do: Map.put(params, :provider_request_limit, limit)

  defp maybe_put_provider_request_limit(params, _limit), do: params

  defp query_summary(results) do
    results
    |> Enum.map(&Map.get(&1, :query))
    |> Enum.reject(&blank?/1)
    |> Enum.uniq()
    |> Enum.join(", ")
  end

  defp annotate_query_result(result, nil), do: result

  defp annotate_query_result(result, %SourceSearchFilter{} = filter) do
    bids =
      result
      |> Map.get(:bids, [])
      |> Enum.map(fn bid ->
        bid
        |> Map.put(:search_filter_id, filter.id)
        |> Map.put(:search_filter_type, filter.filter_type)
        |> Map.put(:search_filter_value, filter.value)
      end)

    result
    |> Map.put(:bids, bids)
    |> Map.put(:source_search_filter, filter)
  end

  defp search_filter_counts(results) do
    results
    |> Enum.map(fn result ->
      case Map.get(result, :source_search_filter) do
        %SourceSearchFilter{} = filter ->
          %{
            "id" => filter.id,
            "type" => to_string(filter.filter_type),
            "value" => filter.value,
            "label" => filter.label,
            "returned" => length(Map.get(result, :bids, []))
          }

        _ ->
          nil
      end
    end)
    |> Enum.reject(&is_nil/1)
  end

  defp record_search_filter_counts(query_result, saved) do
    saved_counts = Enum.frequencies_by(saved, &Map.get(&1, :search_filter_id))

    query_result
    |> Map.get(:search_filter_counts, [])
    |> Enum.each(fn %{"id" => id, "returned" => returned} ->
      with {:ok, filter} <- Ash.get(SourceSearchFilter, id, authorize?: false) do
        Procurement.record_source_search_filter_run!(
          filter,
          %{
            last_returned_count: returned,
            last_saved_count: Map.get(saved_counts, id, 0)
          },
          authorize?: false
        )
      end
    end)
  end

  defp source_search_filters(source) do
    case Procurement.list_enabled_source_search_filters(source.id, authorize?: false) do
      {:ok, filters} -> filters
      _ -> []
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

  defp format_reason(reason) when is_binary(reason), do: reason
  defp format_reason(reason), do: inspect(reason)

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
