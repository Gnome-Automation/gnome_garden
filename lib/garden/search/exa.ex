defmodule GnomeGarden.Search.Exa do
  @moduledoc """
  Thin client for the [Exa](https://exa.ai) neural-search API.

  Exa is a semantic web-search service: given a natural-language query it returns
  ranked pages (with optional clean contents), which is a much higher
  signal-per-dollar way to find lead candidates than crawling whole sites.

  This module wraps only the cheap `/search` endpoint for now (no `/contents`,
  no LLM) — the building block for candidate generation feeding the AshLua
  discovery pipeline. Cost scales sharply once contents + extraction are added,
  so each response surfaces the real `cost` Exa reports so callers can budget.

  The API key is read from `config :gnome_garden, :exa, api_key: ...`
  (wired from the `EXA_API_KEY` environment variable in `config/runtime.exs`).
  """

  require Logger

  @endpoint "https://api.exa.ai/search"
  @default_num_results 10
  @receive_timeout 40_000

  @type result :: %{
          title: String.t() | nil,
          url: String.t(),
          published_date: String.t() | nil,
          author: String.t() | nil,
          score: float() | nil
        }

  @type search_response :: %{cost: float() | nil, resolved_type: String.t() | nil, results: [result()]}

  @doc """
  Runs an Exa search. Returns `{:ok, %{cost:, resolved_type:, results:}}` or
  `{:error, reason}`.

  Options:
    * `:num_results` — max results (default #{@default_num_results})
    * `:type` — `"auto"` (default), `"neural"`, or `"keyword"`
    * `:category` — narrow the result kind, e.g. `"company"`
    * `:include_domains` / `:exclude_domains` — list of domains to scope to
    * `:start_published_date` — ISO8601 string, e.g. recency filtering
  """
  @spec search(String.t(), keyword()) :: {:ok, search_response()} | {:error, term()}
  def search(query, opts \\ []) when is_binary(query) do
    with {:ok, api_key} <- api_key() do
      body = build_body(query, opts)

      request_options =
        [json: body, headers: [{"x-api-key", api_key}], receive_timeout: @receive_timeout]
        |> Keyword.merge(req_options())

      case Req.post(@endpoint, request_options) do
        {:ok, %Req.Response{status: 200, body: payload}} ->
          {:ok, normalize(payload)}

        {:ok, %Req.Response{status: status, body: payload}} ->
          Logger.warning("Exa search failed (#{status}): #{inspect(payload)}")
          {:error, {:http_error, status, payload}}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  defp build_body(query, opts) do
    %{
      "query" => query,
      "numResults" => Keyword.get(opts, :num_results, @default_num_results),
      "type" => Keyword.get(opts, :type, "auto")
    }
    |> maybe_put("category", Keyword.get(opts, :category))
    |> maybe_put("includeDomains", Keyword.get(opts, :include_domains))
    |> maybe_put("excludeDomains", Keyword.get(opts, :exclude_domains))
    |> maybe_put("startPublishedDate", Keyword.get(opts, :start_published_date))
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, _key, []), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp normalize(payload) when is_map(payload) do
    %{
      cost: get_in(payload, ["costDollars", "total"]),
      resolved_type: payload["resolvedSearchType"],
      results: payload |> Map.get("results", []) |> Enum.map(&normalize_result/1)
    }
  end

  defp normalize_result(result) do
    %{
      title: result["title"],
      url: result["url"],
      published_date: result["publishedDate"],
      author: result["author"],
      score: result["score"]
    }
  end

  defp api_key do
    case exa_config()[:api_key] || System.get_env("EXA_API_KEY") do
      key when is_binary(key) and key != "" -> {:ok, key}
      _ -> {:error, :missing_exa_api_key}
    end
  end

  # Extra Req options (e.g. a test stub via `plug: {Req.Test, __MODULE__}`).
  defp req_options, do: exa_config()[:req_options] || []

  defp exa_config, do: Application.get_env(:gnome_garden, :exa, [])
end
