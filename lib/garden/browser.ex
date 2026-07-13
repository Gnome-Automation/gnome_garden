defmodule GnomeGarden.Browser do
  @moduledoc """
  Bounded browser and HTTP retrieval facade for application workflows.

  Browser state is owned by `GnomeGarden.Browser.SessionManager`; callers see
  procurement-shaped values rather than Jido session structs or adapter
  details. Ordinary HTTP retrieval uses `Jido.Browser.web_fetch/2` without
  opening a browser session.
  """

  alias GnomeGarden.Browser.{Error, SessionManager}

  @default_timeout_ms 30_000
  @default_max_content_chars 50_000
  @default_max_download_bytes 25_000_000
  @download_poll_ms 50

  @doc "Navigate the managed browser session to a URL."
  def navigate(url, opts \\ []) when is_binary(url) do
    timeout = timeout(opts)

    with_session(:navigate, opts, fn client, session ->
      client.navigate(session, url,
        timeout: timeout,
        wait_until: wait_until(opts)
      )
    end)
    |> case do
      {:ok, result} ->
        {:ok,
         %{
           url: value(result, :url) || url,
           title: value(result, :title) || "Unknown",
           status: :ok
         }}

      error ->
        error
    end
  end

  @doc "Navigate and return a bounded page snapshot with links and forms."
  def inspect_page(url, opts \\ []) when is_binary(url) do
    max_links = positive_integer(opts[:max_links], 100)
    max_text_chars = positive_integer(opts[:max_text_chars], 20_000)
    timeout = timeout(opts)

    with_session(:inspect_page, opts, fn client, session ->
      with {:ok, session, navigation} <-
             client.navigate(session, url,
               timeout: timeout,
               wait_until: wait_until(opts)
             ),
           {:ok, session, evaluation} <-
             client.evaluate(session, page_snapshot_js(max_links, max_text_chars),
               timeout: timeout
             ),
           {:ok, snapshot} <- evaluation_result(evaluation) do
        {:ok, session,
         %{
           url: url,
           final_url: value(snapshot, :url) || value(navigation, :url) || url,
           title: value(snapshot, :title) || value(navigation, :title) || "Unknown",
           text: bounded_string(value(snapshot, :text), max_text_chars),
           links: bounded_list(value(snapshot, :links), max_links),
           headings: bounded_list(value(snapshot, :headings), 25),
           forms: bounded_list(value(snapshot, :forms), 10)
         }}
      end
    end)
  end

  @doc "Evaluate JavaScript in the managed browser session."
  def evaluate(script, opts \\ []) when is_binary(script) do
    with_session(:evaluate, opts, fn client, session ->
      with {:ok, session, evaluation} <-
             client.evaluate(session, script, timeout: timeout(opts)),
           {:ok, result} <- evaluation_result(evaluation) do
        {:ok, session, result}
      end
    end)
  end

  @doc "Type a transient value into an element without embedding it in JavaScript source."
  def type(selector, value, opts \\ []) when is_binary(selector) and is_binary(value) do
    with_session(:type, opts, fn client, session ->
      case client.type(session, selector, value, timeout: timeout(opts)) do
        {:ok, session, _result} -> {:ok, session, %{}}
        {:error, _reason} -> {:error, {:element_input_failed, selector}}
      end
    end)
  end

  @doc "Click an element in the managed browser session."
  def click(selector, opts \\ []) when is_binary(selector) do
    with_session(:click, opts, fn client, session ->
      client.click(session, selector, timeout: timeout(opts))
    end)
  end

  @doc "Fetch an HTTP resource without starting a browser session."
  def web_fetch(url, opts \\ []) when is_binary(url) do
    client = browser_client(opts)
    max_content_chars = positive_integer(opts[:max_content_chars], @default_max_content_chars)

    fetch_opts =
      opts
      |> Keyword.drop([:client, :max_content_chars])
      |> Keyword.put_new(:timeout, timeout(opts))
      |> Keyword.put_new(:max_content_tokens, max(div(max_content_chars, 4), 1))

    case client.web_fetch(url, fetch_opts) do
      {:ok, result} when is_map(result) -> {:ok, bound_fetch_result(result, max_content_chars)}
      {:error, reason} -> {:error, Error.new(:web_fetch, reason)}
    end
  rescue
    exception -> {:error, Error.new(:web_fetch, exception)}
  end

  @doc "Download the selected link through the authenticated browser session."
  def download(selector, target_path, opts \\ [])
      when is_binary(selector) and is_binary(target_path) do
    max_bytes = positive_integer(opts[:max_bytes], @default_max_download_bytes)

    result =
      with_session(:download, opts, fn client, session, context ->
        before = download_entries(context.download_dir)

        with {:ok, session, _click} <-
               client.click(session, selector, timeout: timeout(opts)),
             {:ok, download_path} <-
               await_download(
                 context.download_dir,
                 before,
                 max_bytes,
                 System.monotonic_time(:millisecond) + timeout(opts)
               ) do
          {:ok, session, download_path}
        end
      end)

    with {:ok, download_path} <- result,
         {:ok, stat} <- File.stat(download_path),
         true <- stat.size <= max_bytes,
         :ok <- move_download(download_path, target_path) do
      :ok
    else
      {:error, reason} ->
        {:error, {:browser_download_failed, reason}}

      false ->
        {:error, {:browser_download_failed, :download_too_large}}

      other ->
        {:error, {:browser_download_failed, other}}
    end
  rescue
    exception -> {:error, {:browser_download_failed, Error.new(:download, exception)}}
  end

  @doc "End and forget the managed browser session."
  def close do
    SessionManager.close()
  end

  defp with_session(operation, opts, function) do
    client = browser_client(opts)
    session_opts = session_options(opts)

    case SessionManager.execute(client, session_opts, function, timeout(opts) + 5_000) do
      {:ok, result} -> {:ok, result}
      {:error, reason} -> {:error, Error.new(operation, reason)}
    end
  rescue
    exception -> {:error, Error.new(operation, exception)}
  end

  defp browser_client(opts),
    do: opts[:client] || Application.get_env(:gnome_garden, :browser_client, Jido.Browser)

  defp session_options(opts) do
    configured = Application.get_env(:gnome_garden, :browser_session_options, [])
    adapter = opts[:adapter] || Application.get_env(:gnome_garden, :browser_adapter)

    configured
    |> Keyword.merge(Keyword.take(opts, [:headed, :headless, :executable_path, :allowed_domains]))
    |> Keyword.put(:timeout, timeout(opts))
    |> maybe_put(:adapter, adapter)
  end

  defp timeout(opts),
    do: positive_integer(opts[:timeout_ms] || opts[:timeout], @default_timeout_ms)

  defp wait_until(opts),
    do: if(Keyword.get(opts, :wait_for_network, true), do: "networkidle", else: "load")

  defp evaluation_result(%{result: result}), do: {:ok, result}
  defp evaluation_result(%{"result" => result}), do: {:ok, result}
  defp evaluation_result(result), do: {:ok, result}

  defp bound_fetch_result(result, max_content_chars) do
    content = value(result, :content)
    bounded = bounded_string(content, max_content_chars)

    result
    |> Map.put(:content, bounded)
    |> Map.put(:truncated, value(result, :truncated) == true or bounded != content)
  end

  defp bounded_string(value, limit) when is_binary(value), do: String.slice(value, 0, limit)
  defp bounded_string(_value, _limit), do: ""
  defp bounded_list(value, limit) when is_list(value), do: Enum.take(value, limit)
  defp bounded_list(_value, _limit), do: []
  defp positive_integer(value, _default) when is_integer(value) and value > 0, do: value
  defp positive_integer(_value, default), do: default

  defp value(map, key) when is_map(map),
    do: Map.get(map, key) || Map.get(map, Atom.to_string(key))

  defp value(_map, _key), do: nil
  defp maybe_put(opts, _key, nil), do: opts
  defp maybe_put(opts, key, value), do: Keyword.put(opts, key, value)

  defp download_entries(download_dir) do
    download_dir
    |> Path.join("*")
    |> Path.wildcard()
    |> Map.new(fn path -> {path, file_signature(path)} end)
  end

  defp await_download(download_dir, before, max_bytes, deadline, previous \\ nil) do
    candidates =
      download_dir
      |> download_entries()
      |> Enum.reject(fn {path, signature} ->
        Map.get(before, path) == signature or partial_download?(path)
      end)
      |> Enum.sort_by(fn {_path, {_size, modified}} -> modified end, :desc)

    case candidates do
      [{_path, {size, _modified}} | _rest] when size > max_bytes ->
        {:error, :download_too_large}

      [{path, signature} | _rest] when previous == {path, signature} ->
        {:ok, path}

      [{path, signature} | _rest] ->
        wait_for_download(download_dir, before, max_bytes, deadline, {path, signature})

      [] ->
        wait_for_download(download_dir, before, max_bytes, deadline, nil)
    end
  end

  defp wait_for_download(download_dir, before, max_bytes, deadline, previous) do
    if System.monotonic_time(:millisecond) >= deadline do
      {:error, :download_timeout}
    else
      Process.sleep(@download_poll_ms)
      await_download(download_dir, before, max_bytes, deadline, previous)
    end
  end

  defp file_signature(path) do
    case File.stat(path, time: :posix) do
      {:ok, stat} -> {stat.size, stat.mtime}
      {:error, _reason} -> {0, 0}
    end
  end

  defp partial_download?(path) do
    String.ends_with?(path, [".crdownload", ".part", ".tmp"])
  end

  defp move_download(source, target) do
    case File.rename(source, target) do
      :ok ->
        :ok

      {:error, :exdev} ->
        with {:ok, _bytes} <- File.copy(source, target),
             :ok <- File.rm(source) do
          :ok
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp page_snapshot_js(max_links, max_text_chars) do
    """
    (() => {
      const clean = value => (value || '').replace(/\\s+/g, ' ').trim();
      const links = Array.from(document.querySelectorAll('a[href]'))
        .slice(0, #{max_links})
        .map((link, index) => ({
          href: link.href,
          text: clean(link.innerText || link.getAttribute('aria-label') || link.title),
          selector: link.id ? `#${link.id}` : null,
          ordinal: index
        }))
        .filter(link => link.href);

      const headings = Array.from(document.querySelectorAll('h1,h2,h3'))
        .slice(0, 25)
        .map(heading => clean(heading.innerText))
        .filter(Boolean);

      const forms = Array.from(document.querySelectorAll('form'))
        .slice(0, 10)
        .map((form, index) => ({
          ordinal: index,
          action: form.action || '',
          method: form.method || 'get',
          text: clean(form.innerText).slice(0, 500),
          inputs: Array.from(form.querySelectorAll('input, textarea, select'))
            .slice(0, 25)
            .map(input => ({
              tag: input.tagName.toLowerCase(),
              type: input.getAttribute('type') || input.tagName.toLowerCase(),
              name: input.getAttribute('name') || '',
              id: input.id || '',
              placeholder: input.getAttribute('placeholder') || '',
              autocomplete: input.getAttribute('autocomplete') || '',
              aria_label: input.getAttribute('aria-label') || ''
            })),
          buttons: Array.from(form.querySelectorAll('button, input[type="submit"], input[type="button"]'))
            .slice(0, 10)
            .map(button => clean(button.innerText || button.value || button.getAttribute('aria-label')))
            .filter(Boolean)
        }));

      return {
        url: window.location.href,
        title: document.title || '',
        text: clean(document.body?.innerText || '').slice(0, #{max_text_chars}),
        links,
        headings,
        forms
      };
    })()
    """
  end
end
