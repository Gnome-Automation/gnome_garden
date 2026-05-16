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

  API limit: 1000 requests/day
  """

  alias GnomeGarden.Commercial.CompanyProfileContext

  use Jido.Action,
    name: "query_sam_gov",
    description: "Query SAM.gov for federal procurement opportunities",
    schema: [
      keywords: [type: :string, doc: "Search keywords (e.g., 'SCADA PLC controls')"],
      naics_codes: [
        type: {:array, :string},
        default: [],
        doc: "NAICS codes to filter by"
      ],
      posted_from: [type: :string, doc: "Start date (MM/DD/YYYY)"],
      posted_to: [type: :string, doc: "End date (MM/DD/YYYY)"],
      state: [type: :string, default: "CA", doc: "State code to filter by"],
      limit: [type: :integer, default: 100, doc: "Max results to return"]
    ]

  require Logger

  @sam_api_base "https://api.sam.gov/opportunities/v2/search"

  @impl true
  def run(params, context) do
    api_key = get_api_key(context)

    if is_nil(api_key) do
      {:error, "SAM.gov API key not configured. Set SAM_GOV_API_KEY environment variable."}
    else
      query_params = build_query_params(params, context, api_key)

      Logger.info(
        "[QuerySamGov] Searching with params: #{inspect(Map.delete(query_params, :api_key))}"
      )

      request = context_value(context, [:http_get]) || (&Req.get/2)

      case request.(@sam_api_base, sam_request_options(query_params)) do
        {:ok, %{status: 200, body: body}} ->
          opportunities = parse_response(body)
          Logger.info("[QuerySamGov] Found #{length(opportunities)} opportunities")

          {:ok,
           %{
             source_type: :sam_gov,
             query: Map.get(params, :keywords),
             bids_found: length(opportunities),
             bids: opportunities
           }}

        {:ok, %{status: 429}} ->
          {:error, "SAM.gov rate limit exceeded (1000/day)"}

        {:ok, %{status: 401}} ->
          {:error,
           "SAM.gov API key was rejected. Generate a public API key in SAM.gov and update SAM_GOV_API_KEY."}

        {:ok, %{status: status, body: body}} ->
          Logger.warning("[QuerySamGov] API returned status #{status}: #{inspect(body)}")
          {:error, "SAM.gov API error: status #{status}"}

        {:error, reason} ->
          {:error, "SAM.gov request failed: #{inspect(reason)}"}
      end
    end
  end

  defp get_api_key(context) do
    # Check context first (injected by agent), then environment
    context_value(context, [:sam_gov_api_key]) ||
      System.get_env("SAM_GOV_API_KEY")
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
      notice_type: opp["type"] || opp["noticeType"],
      metadata: %{
        solicitationNumber: opp["solicitationNumber"],
        classificationCode: opp["classificationCode"],
        organizationType: opp["organizationType"]
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

  defp place_value(%{} = value, key), do: value[key] || value[Atom.to_string(key)]
  defp place_value(value, _key), do: value

  defp build_sam_url(nil), do: "https://sam.gov"
  defp build_sam_url(notice_id), do: "https://sam.gov/opp/#{notice_id}/view"

  defp nested_value(map, [key]) when is_map(map) do
    Map.get(map, key) || Map.get(map, Atom.to_string(key))
  end

  defp nested_value(map, [key | rest]) when is_map(map) do
    map
    |> nested_value([key])
    |> case do
      %{} = nested -> nested_value(nested, rest)
      _ -> nil
    end
  end

  defp nested_value(_map, _path), do: nil

  defp context_value(context, path) do
    nested_value(context, path) || nested_value(context, [:tool_context | path])
  end

  defp sam_request_options(query_params) do
    [
      params: query_params,
      headers: [{"accept", "application/json"}, {"user-agent", "GnomeGarden SAM Scanner/1.0"}],
      connect_options: [transport_opts: [versions: [:"tlsv1.2"]]]
    ]
  end
end
