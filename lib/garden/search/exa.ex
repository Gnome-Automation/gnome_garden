defmodule GnomeGarden.Search.Exa do
  @moduledoc """
  Thin client for the [Exa](https://exa.ai) neural-search API.

  Exa is a semantic web-search service: given a natural-language query it returns
  ranked pages (with optional clean contents), which is a much higher
  signal-per-dollar way to find lead candidates than crawling whole sites.

  This module wraps two endpoints: the cheap `/search` (candidate generation for
  the AshLua discovery pipeline) and the paid `/contents` (selective page
  enrichment — clean text + subpages for chosen candidates, e.g. pulling a
  company's contact/about/team pages). Cost scales sharply with `/contents`, so
  each response surfaces the real `cost` Exa reports so callers can budget.

  The API key is read from `config :gnome_garden, :exa, api_key: ...`
  (wired from the `EXA_API_KEY` environment variable in `config/runtime.exs`).
  """

  require Logger

  @search_endpoint "https://api.exa.ai/search"
  @contents_endpoint "https://api.exa.ai/contents"
  @default_num_results 10
  @receive_timeout 40_000

  @type result :: %{
          title: String.t() | nil,
          url: String.t(),
          published_date: String.t() | nil,
          author: String.t() | nil,
          score: float() | nil,
          entities: list() | nil,
          image: String.t() | nil
        }

  @type search_response :: %{cost: float() | nil, resolved_type: String.t() | nil, results: [result()]}

  @type content :: %{
          url: String.t(),
          title: String.t() | nil,
          text: String.t() | nil,
          summary: map() | String.t() | nil,
          subpages: [content()]
        }

  @type contents_response :: %{cost: float() | nil, results: [content()]}

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

      case Req.post(@search_endpoint, request_options) do
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

  @doc """
  Fetches clean page contents for one or more URLs via Exa's paid `/contents`
  endpoint. Returns `{:ok, %{cost:, results:}}` where each result carries the
  page `text` and any matched `subpages` (e.g. contact/about/team pages).

  This is the selective enrichment step — meaningfully more expensive than
  `/search` — so callers should scope it to chosen candidates and budget against
  the returned `cost`.

  Options:
    * `:max_characters` — cap text per page (default 5000); `false` to omit text
    * `:subpages` — number of linked subpages to also fetch (default 0)
    * `:subpage_target` — list of link keywords, e.g. `["contact", "about"]`
    * `:livecrawl` — `"fallback"` (default), `"always"`, or `"never"`
    * `:summary_schema` — a JSON-schema map; when given, Exa runs its own LLM to
      return structured data per page (parsed into `:summary`)
    * `:summary_query` — guidance string paired with `:summary_schema`
  """
  @spec contents([String.t()] | String.t(), keyword()) :: {:ok, contents_response()} | {:error, term()}
  def contents(urls, opts \\ [])

  def contents(url, opts) when is_binary(url), do: contents([url], opts)

  def contents(urls, opts) when is_list(urls) do
    with {:ok, api_key} <- api_key() do
      body = build_contents_body(urls, opts)

      request_options =
        [json: body, headers: [{"x-api-key", api_key}], receive_timeout: @receive_timeout]
        |> Keyword.merge(req_options())

      case Req.post(@contents_endpoint, request_options) do
        {:ok, %Req.Response{status: 200, body: payload}} ->
          {:ok, normalize_contents(payload)}

        {:ok, %Req.Response{status: status, body: payload}} ->
          Logger.warning("Exa contents failed (#{status}): #{inspect(payload)}")
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

  defp build_contents_body(urls, opts) do
    %{
      "urls" => urls,
      "livecrawl" => Keyword.get(opts, :livecrawl, "fallback")
    }
    |> maybe_put("text", text_param(Keyword.get(opts, :max_characters, 5000)))
    |> maybe_put("subpages", positive(Keyword.get(opts, :subpages)))
    |> maybe_put("subpageTarget", Keyword.get(opts, :subpage_target))
    |> maybe_put("summary", summary_param(opts))
  end

  defp text_param(false), do: nil
  defp text_param(max) when is_integer(max), do: %{"maxCharacters" => max}
  defp text_param(_), do: %{"maxCharacters" => 5000}

  defp summary_param(opts) do
    case Keyword.get(opts, :summary_schema) do
      %{} = schema ->
        %{"schema" => schema}
        |> maybe_put("query", Keyword.get(opts, :summary_query))

      _ ->
        nil
    end
  end

  defp positive(n) when is_integer(n) and n > 0, do: n
  defp positive(_), do: nil

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
      score: result["score"],
      entities: result["entities"],
      image: result["image"]
    }
  end

  defp normalize_contents(payload) when is_map(payload) do
    %{
      cost: get_in(payload, ["costDollars", "total"]),
      results: payload |> Map.get("results", []) |> Enum.map(&normalize_content/1)
    }
  end

  defp normalize_content(result) do
    %{
      url: result["url"],
      title: result["title"],
      text: result["text"],
      summary: parse_summary(result["summary"]),
      subpages: result |> Map.get("subpages", []) |> Enum.map(&normalize_content/1)
    }
  end

  # With a schema, Exa returns the summary as a JSON string; without one it may be
  # plain text. Parse JSON objects into maps, leave plain strings as-is.
  defp parse_summary(summary) when is_binary(summary) do
    case Jason.decode(summary) do
      {:ok, %{} = map} -> map
      _ -> summary
    end
  end

  defp parse_summary(summary), do: summary

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
