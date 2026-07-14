defmodule GnomeGarden.Agents.Procurement.OpenGovAdapter do
  @moduledoc """
  Provider-specific OpenGov opportunity retrieval and normalization.

  Structured API retrieval is used only when a source stores an explicit
  projects endpoint. Public portal HTML and the Jido browser are bounded
  fallbacks; no undocumented endpoint is guessed from an agency slug.
  """

  alias GnomeGarden.Browser
  alias GnomeGarden.Procurement.ProcurementSource

  @browser_extract_script """
  (() => {
    const links = Array.from(document.querySelectorAll("a[href*='/project/'], a[href*='/projects/']"));
    const seen = new Set();

    return links.flatMap(link => {
      const href = link.href;
      const container = link.closest('article, tr, li, [class*="project"], [data-testid*="project"]') || link;
      const title = (link.innerText || container.querySelector('h1,h2,h3,h4,[class*="title"]')?.innerText || '').trim();

      if (!href || !title || seen.has(href)) return [];
      seen.add(href);

      const text = (container.innerText || '').trim();
      const time = container.querySelector('time');

      return [{
        id: href.split('/').filter(Boolean).pop(),
        title,
        url: href,
        description: text,
        dueDate: time?.dateTime || time?.innerText || null,
        status: 'open'
      }];
    });
  })()
  """

  def fetch(%ProcurementSource{} = source, :provider_api, context) do
    with {:ok, url} <- projects_api_url(source),
         {:ok, body} <- http_get(url, context),
         {:ok, projects, schema} <- parse_payload(body) do
      {:ok, result(source, projects, :provider_api, url, schema)}
    end
  end

  def fetch(%ProcurementSource{} = source, :http, context) do
    url = listing_url(source)

    with {:ok, body} <- http_get(url, context),
         {:ok, projects, schema} <- parse_payload(body) do
      {:ok, result(source, projects, :http, url, schema)}
    end
  end

  def fetch(%ProcurementSource{} = source, :browser, context) do
    url = listing_url(source)
    navigate = context_value(context, :browser_navigate) || (&Browser.navigate/1)
    evaluate = context_value(context, :browser_evaluate) || (&Browser.evaluate/1)
    sleep = context_value(context, :sleep) || (&Process.sleep/1)

    with {:ok, _navigation} <- navigate.(url),
         :ok <- sleep.(context_value(context, :browser_wait_ms) || 1_200),
         {:ok, body} <- evaluate.(@browser_extract_script),
         {:ok, projects, schema} <- parse_payload(body) do
      {:ok, result(source, projects, :browser, url, schema)}
    end
  end

  defp projects_api_url(source) do
    config = source.scrape_config || %{}

    case value(config, "projects_api_url") || value(config, "api_url") do
      url when is_binary(url) and url != "" -> {:ok, url}
      _value -> {:error, :opengov_api_not_configured}
    end
  end

  defp listing_url(source) do
    config = source.scrape_config || %{}
    value(config, "listing_url") || source.url
  end

  defp http_get(url, context) do
    getter = context_value(context, :http_get)

    result =
      if is_function(getter, 2) do
        getter.(url,
          headers: [
            {"accept", "application/json,text/html;q=0.9"},
            {"user-agent", "GnomeGarden OpenGov Adapter/1.0"}
          ],
          redirect: true,
          retry: false,
          receive_timeout: 30_000
        )
      else
        Browser.web_fetch(url, format: :html, timeout_ms: 30_000)
      end

    case result do
      {:ok, %{status: status, body: body}} when status in 200..299 -> {:ok, body}
      {:ok, %{status: 403, body: body}} -> {:error, classify_forbidden(body)}
      {:ok, %{status: 429}} -> {:error, :rate_limited}
      {:ok, %{status: status}} -> {:error, {:http_status, status}}
      {:ok, %{content: content}} -> {:ok, content}
      {:error, reason} -> {:error, reason}
    end
  end

  defp classify_forbidden(body) when is_binary(body) do
    if String.match?(body, ~r/cloudflare|challenge|cf-mitigated/i),
      do: :waf_challenge,
      else: :forbidden
  end

  defp classify_forbidden(_body), do: :forbidden

  defp parse_payload(%{"projects" => projects}) when is_list(projects),
    do: {:ok, projects, "projects"}

  defp parse_payload(%{"data" => projects}) when is_list(projects),
    do: {:ok, Enum.map(projects, &json_api_project/1), "json_api"}

  defp parse_payload(projects) when is_list(projects), do: {:ok, projects, "list"}

  defp parse_payload(body) when is_binary(body) do
    case Jason.decode(body) do
      {:ok, decoded} -> parse_payload(decoded)
      {:error, _error} -> parse_html(body)
    end
  end

  defp parse_payload(_body), do: {:error, :opengov_schema_drift}

  defp parse_html(body) do
    with {:ok, document} <- Floki.parse_document(body) do
      projects =
        document
        |> Floki.find("a[href*='/project/'], a[href*='/projects/']")
        |> Enum.map(fn link ->
          href = link |> Floki.attribute("href") |> List.first()

          %{
            "id" => href && href |> String.split("/", trim: true) |> List.last(),
            "title" => link |> Floki.text(sep: " ") |> String.trim(),
            "url" => href,
            "status" => "open"
          }
        end)
        |> Enum.reject(&(blank?(value(&1, "title")) or blank?(value(&1, "url"))))
        |> Enum.uniq_by(&value(&1, "url"))

      if projects == [] and String.match?(body, ~r/cloudflare|challenge|cf-mitigated/i) do
        {:error, :waf_challenge}
      else
        {:ok, projects, "html"}
      end
    else
      _error -> {:error, :opengov_malformed_html}
    end
  end

  defp result(source, projects, path, url, schema) do
    bids =
      projects
      |> Enum.map(&normalize_project(&1, source, url))
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq_by(&(&1.external_id || &1.url))

    %{
      bids: bids,
      diagnostics: %{
        "provider" => "opengov",
        "path" => Atom.to_string(path),
        "schema" => schema,
        "rows" => length(projects),
        "normalized" => length(bids),
        "endpoint" => url
      }
    }
  end

  defp normalize_project(project, source, endpoint) when is_map(project) do
    title = value(project, "title") || value(project, "name")
    url = absolutize(value(project, "url") || value(project, "link"), source.url)

    if blank?(title) or blank?(url) do
      nil
    else
      %{
        external_id: value(project, "id") || value(project, "projectId"),
        title: title,
        description: value(project, "description") || value(project, "summary") || "",
        agency: source.name,
        location: region_location(source.region),
        url: url,
        source_url: endpoint,
        source_type: :opengov,
        posted_at: parse_datetime(value(project, "publishedDate") || value(project, "createdAt")),
        due_at:
          parse_datetime(
            value(project, "dueDate") || value(project, "closeDate") ||
              value(project, "deadline")
          ),
        metadata: %{
          "opengov" => %{
            "status" => value(project, "status"),
            "project_id" => value(project, "id") || value(project, "projectId")
          }
        }
      }
    end
  end

  defp json_api_project(%{"attributes" => attributes, "id" => id} = project) do
    attributes
    |> Map.put_new("id", id)
    |> Map.put_new("url", get_in(project, ["links", "self"]))
  end

  defp json_api_project(project), do: project

  defp parse_datetime(nil), do: nil
  defp parse_datetime(%DateTime{} = value), do: value

  defp parse_datetime(%Date{} = value),
    do: DateTime.new!(value, ~T[23:59:59], "Etc/UTC")

  defp parse_datetime(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, date_time, _offset} ->
        date_time

      _error ->
        case Date.from_iso8601(value) do
          {:ok, date} -> DateTime.new!(date, ~T[23:59:59], "Etc/UTC")
          _error -> nil
        end
    end
  end

  defp parse_datetime(_value), do: nil

  defp absolutize(nil, _base), do: nil

  defp absolutize(url, base) do
    base |> URI.merge(url) |> URI.to_string()
  rescue
    _error -> url
  end

  defp region_location(:oc), do: "Orange County, CA"
  defp region_location(:la), do: "Los Angeles County, CA"
  defp region_location(:ie), do: "Inland Empire, CA"
  defp region_location(:sd), do: "San Diego County, CA"
  defp region_location(:socal), do: "Southern California"
  defp region_location(:norcal), do: "Northern California"
  defp region_location(:ca), do: "California"
  defp region_location(_region), do: nil

  defp context_value(context, key) when is_map(context),
    do: Map.get(context, key) || Map.get(context, Atom.to_string(key))

  defp context_value(_context, _key), do: nil

  defp value(map, key) when is_map(map), do: Map.get(map, key) || atom_value(map, key)
  defp value(_map, _key), do: nil

  defp atom_value(map, key) do
    Map.get(map, String.to_existing_atom(key))
  rescue
    ArgumentError -> nil
  end

  defp blank?(value), do: value in [nil, ""]
end
