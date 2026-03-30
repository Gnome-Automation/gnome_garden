defmodule GnomeGarden.Agents.Tools.WebSearch do
  @moduledoc """
  Search the web using Brave Search API.

  Returns relevant search results with titles, URLs, and descriptions.
  Requires BRAVE_API_KEY environment variable.
  """

  use Jido.Action,
    name: "web_search",
    description:
      "Search the web using Brave Search. Returns relevant results with titles, URLs, and descriptions.",
    schema: [
      query: [
        type: :string,
        required: true,
        doc: "Search query"
      ],
      count: [
        type: :integer,
        default: 10,
        doc: "Number of results to return (max 20)"
      ],
      freshness: [
        type: :string,
        doc: "Filter by freshness: pd (past day), pw (past week), pm (past month), py (past year)"
      ]
    ]

  @brave_api_url "https://api.search.brave.com/res/v1/web/search"

  @impl true
  def run(params, _context) do
    query = Map.get(params, :query) || Map.get(params, "query")
    count = min(Map.get(params, :count) || Map.get(params, "count", 10), 20)
    freshness = Map.get(params, :freshness) || Map.get(params, "freshness")

    case get_api_key() do
      {:ok, api_key} ->
        do_search(query, count, freshness, api_key)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp get_api_key do
    case Application.get_env(:jido_browser, :brave_api_key) || System.get_env("BRAVE_API_KEY") do
      nil -> {:error, "BRAVE_API_KEY not configured. Set the environment variable."}
      key -> {:ok, key}
    end
  end

  defp do_search(query, count, freshness, api_key) do
    params = %{q: query, count: count}
    params = if freshness, do: Map.put(params, :freshness, freshness), else: params

    headers = [
      {"Accept", "application/json"},
      {"X-Subscription-Token", api_key}
    ]

    url = "#{@brave_api_url}?#{URI.encode_query(params)}"

    case Req.get(url, headers: headers) do
      {:ok, %{status: 200, body: body}} ->
        parse_results(body, query)

      {:ok, %{status: status, body: body}} ->
        {:error, "Brave Search API error (#{status}): #{inspect(body)}"}

      {:error, reason} ->
        {:error, "HTTP request failed: #{inspect(reason)}"}
    end
  end

  defp parse_results(body, query) do
    results =
      body
      |> Map.get("web", %{})
      |> Map.get("results", [])
      |> Enum.map(fn r ->
        %{
          title: Map.get(r, "title", ""),
          url: Map.get(r, "url", ""),
          description: Map.get(r, "description", "")
        }
      end)

    formatted =
      results
      |> Enum.with_index(1)
      |> Enum.map(fn {r, i} ->
        "#{i}. #{r.title}\n   #{r.url}\n   #{r.description}"
      end)
      |> Enum.join("\n\n")

    {:ok,
     %{
       query: query,
       count: length(results),
       results: formatted
     }}
  end
end
