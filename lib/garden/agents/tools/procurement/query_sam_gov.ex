defmodule GnomeGarden.Agents.Tools.Procurement.QuerySamGov do
  @moduledoc """
  Query SAM.gov for federal procurement opportunities.

  Uses the SAM.gov Opportunities API:
  https://open.gsa.gov/api/get-opportunities-public-api/

  Relevant NAICS codes for controls/automation:
  - 541330: Engineering Services
  - 541512: Computer Systems Design Services
  - 541519: Other Computer Related Services
  - 238210: Electrical Contractors

  Every request reserves the configured SAM.gov daily request budget before
  network access. Retries reuse a deterministic query key and replay a cached
  successful response instead of consuming another provider request.
  """

  alias GnomeGarden.Acquisition.ProviderBudgetPolicy
  alias GnomeGarden.Company.ProfileContext, as: CompanyProfileContext
  alias GnomeGarden.Procurement.SourceCredentials

  require Logger

  @sam_api_base "https://api.sam.gov/opportunities/v2/search"

  def run(params, context) do
    with {:ok, api_key} <- get_api_key(context),
         query_params = build_query_params(params, context, api_key),
         idempotency_key <- idempotency_key(params, query_params, context),
         {:ok, request} <-
           ProviderBudgetPolicy.configured_request(
             "sam_gov",
             "search",
             idempotency_key,
             metadata: %{
               "query_fingerprint" => query_fingerprint(query_params),
               "source_id" => Map.get(params, :source_id)
             }
           ),
         {:ok, %{reservation: reservation, budget: budget}} <-
           ProviderBudgetPolicy.reserve(request, reserve_options(params, context)) do
      execute_or_replay(params, query_params, reservation, budget, context)
    else
      {:error, error} ->
        if ProviderBudgetPolicy.budget_exceeded?(error) do
          with {:ok, budget} <-
                 ProviderBudgetPolicy.current_window(
                   "sam_gov",
                   "search",
                   reserve_options(params, context)
                 ) do
            {:error, {:budget_exhausted, budget.resets_at, budget.remaining_requests}}
          end
        else
          {:error, error}
        end
    end
  end

  defp execute_or_replay(
         params,
         query_params,
         %{status: :reserved} = reservation,
         budget,
         context
       ) do
    Logger.info(
      "[QuerySamGov] Searching with params: #{inspect(Map.delete(query_params, :api_key))}"
    )

    request = context_value(context, [:http_get]) || (&Req.get/2)

    case request.(@sam_api_base, sam_request_options(query_params)) do
      {:ok, %{status: 200, body: body}} ->
        settle_success(params, body, reservation, budget, context)

      {:ok, %{status: 429} = response} ->
        retry_at = retry_at(response, context)

        _ =
          ProviderBudgetPolicy.account_failure(reservation, {:http_error, 429, nil},
            actor: context_value(context, [:actor])
          )

        {:error, {:rate_limited, retry_at}}

      {:ok, %{status: 401}} ->
        _ =
          ProviderBudgetPolicy.account_failure(reservation, {:http_error, 401, nil},
            actor: context_value(context, [:actor])
          )

        {:error,
         "SAM.gov API key was rejected. Generate a public API key in SAM.gov and update SAM_GOV_API_KEY."}

      {:ok, %{status: status, body: body}} ->
        Logger.warning("[QuerySamGov] API returned status #{status}: #{inspect(body)}")

        _ =
          ProviderBudgetPolicy.account_failure(reservation, {:http_error, status, body},
            actor: context_value(context, [:actor])
          )

        {:error, {:http_error, status}}

      {:error, reason} ->
        _ =
          ProviderBudgetPolicy.account_failure(reservation, reason,
            actor: context_value(context, [:actor])
          )

        {:error, {:transport_error, reason}}
    end
  end

  defp execute_or_replay(
         params,
         _query_params,
         %{status: :settled} = reservation,
         budget,
         _context
       ) do
    case reservation.metadata do
      %{"response" => body} -> response(params, body, budget, true)
      _metadata -> {:error, {:provider_reservation_finalized, :settled}}
    end
  end

  defp execute_or_replay(_params, _query_params, reservation, budget, _context) do
    {:error, {:provider_reservation_finalized, reservation.status, budget.resets_at}}
  end

  defp settle_success(params, body, reservation, budget, context) do
    with {:ok, %{budget: settled_budget}} <-
           ProviderBudgetPolicy.settle(
             %{
               idempotency_key: reservation.idempotency_key,
               actual_cost: 0,
               actual_requests: 1,
               status: :settled,
               metadata: %{"response" => cacheable_response(body)}
             },
             actor: context_value(context, [:actor])
           ) do
      response(params, body, settled_budget || budget, false)
    end
  end

  defp response(params, body, budget, replayed?) do
    opportunities = parse_response(body)
    Logger.info("[QuerySamGov] Found #{length(opportunities)} opportunities")

    {:ok,
     %{
       source_type: :sam_gov,
       query: Map.get(params, :keywords),
       bids_found: length(opportunities),
       bids: opportunities,
       replayed?: replayed?,
       budget: budget_summary(budget)
     }}
  end

  defp cacheable_response(%{"opportunitiesData" => opportunities})
       when is_list(opportunities),
       do: %{"opportunitiesData" => opportunities}

  defp cacheable_response(%{"_embedded" => %{"results" => results}}) when is_list(results),
    do: %{"_embedded" => %{"results" => results}}

  defp cacheable_response(body) when is_list(body), do: body
  defp cacheable_response(_body), do: %{"opportunitiesData" => []}

  defp budget_summary(budget) do
    %{
      remaining_requests:
        max(budget.request_limit - budget.reserved_requests - budget.used_requests, 0),
      resets_at: budget.resets_at,
      request_limit: budget.request_limit
    }
  end

  defp idempotency_key(params, query_params, context) do
    Map.get(params, :idempotency_key) ||
      context_value(context, [:idempotency_key]) ||
      "sam_gov:#{Date.to_iso8601(Date.utc_today())}:#{query_fingerprint(query_params)}"
  end

  defp reserve_options(params, context) do
    [actor: context_value(context, [:actor])]
    |> maybe_put_option(:request_limit, Map.get(params, :provider_request_limit))
  end

  defp maybe_put_option(options, _key, nil), do: options
  defp maybe_put_option(options, key, value), do: Keyword.put(options, key, value)

  defp query_fingerprint(query_params) do
    query_params
    |> Map.delete(:api_key)
    |> Enum.sort()
    |> :erlang.term_to_binary()
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end

  defp retry_at(response, context) do
    now = context_value(context, [:now]) || DateTime.utc_now()
    retry_after = retry_after_seconds(Map.get(response, :headers) || Map.get(response, "headers"))
    DateTime.add(now, min(max(retry_after || 900, 60), 3_600), :second)
  end

  defp retry_after_seconds(headers) when is_map(headers) do
    headers
    |> Enum.find_value(fn {key, value} ->
      if String.downcase(to_string(key)) == "retry-after", do: parse_retry_after(value)
    end)
  end

  defp retry_after_seconds(headers) when is_list(headers) do
    headers
    |> Enum.find_value(fn {key, value} ->
      if String.downcase(to_string(key)) == "retry-after", do: parse_retry_after(value)
    end)
  end

  defp retry_after_seconds(_headers), do: nil

  defp parse_retry_after([value | _values]), do: parse_retry_after(value)

  defp parse_retry_after(value) do
    case Integer.parse(to_string(value)) do
      {seconds, ""} -> seconds
      _error -> nil
    end
  end

  defp get_api_key(context) do
    # Explicit run context wins; otherwise use the same DB/Bitwarden/env
    # resolver that source health and credential checks rely on.
    case context_value(context, [:sam_gov_api_key]) do
      value when is_binary(value) and value != "" -> {:ok, value}
      _ -> SourceCredentials.sam_gov_api_key()
    end
  end

  defp build_query_params(params, context, api_key) do
    base = %{
      api_key: api_key,
      limit: Map.get(params, :limit, 100),
      postedFrom: Map.get(params, :posted_from) || default_posted_from(),
      postedTo: Map.get(params, :posted_to) || today_string()
    }

    # Add optional filters
    base
    |> maybe_add(:title, Map.get(params, :keywords))
    |> maybe_add(:ncode, format_naics(default_naics_codes(params, context)))
    |> maybe_add(:state, Map.get(params, :state))
  end

  defp maybe_add(params, _key, nil), do: params
  defp maybe_add(params, _key, ""), do: params
  defp maybe_add(params, key, value), do: Map.put(params, key, value)

  defp format_naics([]), do: nil
  defp format_naics(codes) when is_list(codes), do: Enum.join(codes, ",")
  defp format_naics(code) when is_binary(code), do: code

  defp default_naics_codes(params, context) do
    case Map.get(params, :naics_codes, []) do
      [] ->
        tool_context = Map.get(context, :tool_context, context)

        scope_mode =
          nested_value(tool_context, [:company_profile_mode]) ||
            nested_value(tool_context, [:source_scope, :company_profile_mode])

        profile_key =
          nested_value(tool_context, [:company_profile_key]) ||
            nested_value(tool_context, [:deployment_config, :company_profile_key])

        CompanyProfileContext.sam_gov_naics_codes(
          profile_key && CompanyProfileContext.profile(profile_key),
          scope_mode
        )

      codes ->
        codes
    end
  end

  defp default_posted_from do
    Date.utc_today()
    |> Date.add(-30)
    |> format_date()
  end

  defp today_string do
    Date.utc_today() |> format_date()
  end

  defp format_date(date) do
    "#{date.month}/#{date.day}/#{date.year}"
  end

  defp parse_response(%{"opportunitiesData" => opportunities}) when is_list(opportunities) do
    Enum.map(opportunities, &parse_opportunity/1)
  end

  defp parse_response(%{"_embedded" => %{"results" => results}}) when is_list(results) do
    Enum.map(results, &parse_opportunity/1)
  end

  defp parse_response(body) when is_list(body) do
    Enum.map(body, &parse_opportunity/1)
  end

  defp parse_response(_), do: []

  defp parse_opportunity(opp) do
    %{
      external_id: opp["noticeId"] || opp["solicitationNumber"] || opp["id"],
      title: opp["title"] || opp["solicitationTitle"] || "Federal Opportunity",
      description: opp["description"] || opp["synopsis"],
      agency:
        opp["department"] || opp["agency"] || opp["organizationName"] || opp["fullParentPathName"],
      location: extract_location(opp),
      url: opp["uiLink"] || build_sam_url(opp["noticeId"]),
      source_url: @sam_api_base,
      source_type: :sam_gov,
      posted_at: parse_sam_date(opp["postedDate"]),
      due_date: parse_sam_date(opp["responseDeadLine"] || opp["responseDate"]),
      estimated_value: extract_value(opp),
      naics_code: opp["naicsCode"] || List.first(opp["naicsCodes"] || []),
      set_aside: opp["typeOfSetAsideDescription"],
      notice_type:
        opp["type"] || opp["noticeType"] || opp["typeOfNotice"] || opp["solicitationType"],
      metadata: %{
        solicitationNumber: opp["solicitationNumber"],
        classificationCode: opp["classificationCode"],
        organizationType: opp["organizationType"],
        solicitationType: opp["solicitationType"],
        noticeType: opp["noticeType"] || opp["typeOfNotice"] || opp["type"]
      }
    }
  end

  defp extract_location(opp) do
    place = opp["placeOfPerformance"] || %{}
    city = place["city"] || opp["city"]
    city = place_value(city, "name")
    state = place_value(place["state"] || opp["state"], "code")

    cond do
      city && state -> "#{city}, #{state}"
      state -> state
      true -> nil
    end
  end

  defp extract_value(opp) do
    # SAM.gov sometimes has award info
    award = opp["award"] || %{}
    amount = award["amount"] || opp["estimatedValue"]

    case amount do
      nil ->
        nil

      n when is_number(n) ->
        Decimal.new(n)

      s when is_binary(s) ->
        case Decimal.parse(String.replace(s, ~r/[,$]/, "")) do
          {d, _} -> d
          :error -> nil
        end
    end
  end

  defp parse_sam_date(nil), do: nil

  defp parse_sam_date(date_str) when is_binary(date_str) do
    # SAM.gov uses various formats
    cond do
      String.contains?(date_str, "T") ->
        case DateTime.from_iso8601(date_str) do
          {:ok, dt, _} -> dt
          _ -> nil
        end

      Regex.match?(~r/^\d{4}-\d{2}-\d{2}$/, date_str) ->
        case Date.from_iso8601(date_str) do
          {:ok, d} -> DateTime.new!(d, ~T[23:59:59], "Etc/UTC")
          _ -> nil
        end

      true ->
        parse_sam_space_datetime(date_str) || parse_us_date(date_str)
    end
  end

  defp parse_sam_date(_), do: nil

  defp parse_sam_space_datetime(date_str) do
    case Regex.run(~r/^(\d{4}-\d{2}-\d{2})\s+(\d{2}:\d{2}:\d{2})([+-]\d{2})$/, date_str) do
      [_, date, time, offset] ->
        case DateTime.from_iso8601("#{date}T#{time}#{offset}:00") do
          {:ok, dt, _} -> dt
          _ -> nil
        end

      _ ->
        nil
    end
  end

  defp parse_us_date(date_str) do
    case Regex.run(~r/^(\d{1,2})\/(\d{1,2})\/(\d{4})$/, date_str) do
      [_, month, day, year] ->
        with {month, ""} <- Integer.parse(month),
             {day, ""} <- Integer.parse(day),
             {year, ""} <- Integer.parse(year),
             {:ok, date} <- Date.new(year, month, day) do
          DateTime.new!(date, ~T[23:59:59], "Etc/UTC")
        else
          _ -> nil
        end

      _ ->
        nil
    end
  end

  defp place_value(%{} = value, key), do: map_value(value, key)
  defp place_value(value, _key), do: value

  defp build_sam_url(nil), do: "https://sam.gov"
  defp build_sam_url(notice_id), do: "https://sam.gov/opp/#{notice_id}/view"

  defp nested_value(map, [key]) when is_map(map), do: map_value(map, key)

  defp nested_value(map, [key | rest]) when is_map(map) do
    map
    |> nested_value([key])
    |> case do
      %{} = nested -> nested_value(nested, rest)
      _ -> nil
    end
  end

  defp nested_value(_map, _path), do: nil

  defp map_value(map, key) when is_atom(key) do
    Map.get(map, key) || Map.get(map, Atom.to_string(key))
  end

  defp map_value(map, key) when is_binary(key) do
    Map.get(map, key) || existing_atom_value(map, key)
  end

  defp existing_atom_value(map, key) do
    Map.get(map, String.to_existing_atom(key))
  rescue
    ArgumentError -> nil
  end

  defp context_value(context, path) do
    nested_value(context, path) || nested_value(context, [:tool_context | path])
  end

  defp sam_request_options(query_params) do
    [
      params: query_params,
      retry: false,
      receive_timeout: 15_000,
      pool_timeout: 5_000,
      headers: [{"accept", "application/json"}, {"user-agent", "GnomeGarden SAM Scanner/1.0"}],
      connect_options: [timeout: 8_000, transport_opts: [versions: [:"tlsv1.2"]]]
    ]
  end
end
