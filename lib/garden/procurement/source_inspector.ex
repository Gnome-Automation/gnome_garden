defmodule GnomeGarden.Procurement.SourceInspector do
  @moduledoc """
  Captures a bounded source-page snapshot into crawl traversal storage.
  """

  require Logger

  alias GnomeGarden.Procurement
  alias GnomeGarden.Procurement.ProcurementSource

  @max_artifact_chars 40_000

  def inspect_source(source_or_id, opts \\ [])

  def inspect_source(%ProcurementSource{} = source, opts) do
    actor = Keyword.get(opts, :actor)
    browser = Keyword.get(opts, :browser, GnomeGarden.Browser)
    max_links = Keyword.get(opts, :max_links, 100)

    with {:ok, run} <- start_run(source, max_links, actor),
         {:ok, snapshot} <- browser.inspect_page(source.url, max_links: max_links),
         {:ok, page} <- record_page(run, source, snapshot, actor),
         {:ok, _artifact} <- record_snapshot_artifact(page, snapshot, actor),
         :ok <- record_edges(run, page, snapshot.links, actor),
         {:ok, run} <- complete_run(run, snapshot, actor) do
      {:ok, %{run: run, page: page, snapshot: snapshot}}
    else
      {:error, error} = failed ->
        Logger.warning("Source inspection failed for #{source.name}: #{inspect(error)}")
        failed
    end
  end

  def inspect_source(id, opts) when is_binary(id) do
    actor = Keyword.get(opts, :actor)

    with {:ok, source} <- Procurement.get_procurement_source(id, actor: actor) do
      inspect_source(source, opts)
    end
  end

  defp start_run(source, max_links, actor) do
    Procurement.start_crawl_run(
      %{
        procurement_source_id: source.id,
        seed_url: source.url,
        run_kind: :inspect,
        max_depth: 0,
        max_pages: 1,
        metadata: %{
          "inspector" => "source_inspector",
          "max_links" => max_links
        }
      },
      actor: actor
    )
  end

  defp record_page(run, source, snapshot, actor) do
    Procurement.record_crawl_page(
      %{
        crawl_run_id: run.id,
        url: source.url,
        normalized_url: normalize_url(source.url),
        final_url: snapshot.final_url,
        title: snapshot.title || source.name,
        depth: 0,
        content_hash: hash(snapshot.text || ""),
        fetch_status: :fetched,
        diagnostics: %{},
        metadata: %{
          "source_name" => source.name,
          "headings" => snapshot.headings,
          "forms_count" => length(snapshot.forms || [])
        }
      },
      actor: actor
    )
  end

  defp record_snapshot_artifact(page, snapshot, actor) do
    body =
      snapshot
      |> Jason.encode!(pretty: true)
      |> String.slice(0, @max_artifact_chars)

    Procurement.record_page_artifact(
      %{
        crawl_page_id: page.id,
        kind: :snapshot,
        body: body,
        byte_size: byte_size(body),
        content_hash: hash(body),
        metadata: %{"truncated" => String.length(body) >= @max_artifact_chars}
      },
      actor: actor
    )
  end

  defp record_edges(run, page, links, actor) when is_list(links) do
    links
    |> Enum.with_index()
    |> Enum.each(fn {link, index} ->
      href = value(link, "href")

      if is_binary(href) and href != "" do
        _ =
          Procurement.record_crawl_edge(
            %{
              crawl_run_id: run.id,
              from_page_id: page.id,
              to_url: href,
              link_text: value(link, "text"),
              selector: value(link, "selector"),
              edge_type: edge_type(href),
              ordinal: value(link, "ordinal") || index,
              metadata: %{}
            },
            actor: actor
          )
      end
    end)

    :ok
  end

  defp record_edges(_run, _page, _links, _actor), do: :ok

  defp complete_run(run, snapshot, actor) do
    Procurement.complete_crawl_run(
      run,
      %{
        summary: %{
          "pages" => 1,
          "links" => length(snapshot.links || []),
          "forms" => length(snapshot.forms || []),
          "headings" => length(snapshot.headings || []),
          "recorded_at" =>
            DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()
        },
        diagnostics: %{"diagnosis" => "page_inspected"}
      },
      actor: actor
    )
  end

  defp edge_type(href) do
    if Regex.match?(~r/\.(pdf|docx?|xlsx?)(\?|#|$)/i, href), do: :document, else: :link
  end

  defp normalize_url(url) when is_binary(url) do
    url
    |> String.replace(~r/#.*$/, "")
    |> String.trim_trailing("/")
  end

  defp hash(value) do
    value
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end

  defp value(map, key) when is_map(map), do: Map.get(map, key) || Map.get(map, key_atom(key))
  defp value(_map, _key), do: nil

  defp key_atom("href"), do: :href
  defp key_atom("text"), do: :text
  defp key_atom("selector"), do: :selector
  defp key_atom("ordinal"), do: :ordinal
  defp key_atom(_key), do: nil
end
