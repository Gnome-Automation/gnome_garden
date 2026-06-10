defmodule GnomeGarden.Browser do
  @moduledoc """
  Bounded browser automation facade for application workflows.

  Domain scanners should call this module instead of agent-facing browser tools
  or raw browser commands. The implementation can change without changing the
  procurement/commercial workflow code.
  """

  @default_timeout_ms 30_000

  @doc "Navigate the shared browser session to a URL."
  def navigate(url, opts \\ []) when is_binary(url) do
    wait_for_network = Keyword.get(opts, :wait_for_network, true)
    timeout_ms = Keyword.get(opts, :timeout_ms, @default_timeout_ms)

    case open_url(url, timeout_ms) do
      {output, 0} ->
        if wait_for_network, do: wait_for_load(timeout_ms)
        {:ok, %{url: url, title: parse_title(output), status: :ok}}

      {output, _} ->
        {:error, String.trim(output)}
    end
  end

  @doc "Navigate to a URL and return a bounded page snapshot with links."
  def inspect_page(url, opts \\ []) when is_binary(url) do
    max_links = Keyword.get(opts, :max_links, 100)
    max_text_chars = Keyword.get(opts, :max_text_chars, 20_000)

    with {:ok, navigation} <- navigate(url, opts),
         {:ok, snapshot} <- evaluate(page_snapshot_js(max_links, max_text_chars)) do
      {:ok,
       %{
         url: url,
         final_url: Map.get(snapshot, "url") || url,
         title: Map.get(snapshot, "title") || navigation.title,
         text: Map.get(snapshot, "text") || "",
         links: Map.get(snapshot, "links") || [],
         headings: Map.get(snapshot, "headings") || [],
         forms: Map.get(snapshot, "forms") || []
       }}
    end
  end

  @doc "Evaluate JavaScript in the current browser page and JSON-decode the result when possible."
  def evaluate(js) when is_binary(js) do
    case System.cmd(binary_path(), ["eval", js], stderr_to_stdout: true) do
      {output, 0} ->
        case Jason.decode(output) do
          {:ok, data} -> {:ok, data}
          {:error, _} -> {:ok, String.trim(output)}
        end

      {output, _} ->
        {:error, "Extract failed: #{String.trim(output)}"}
    end
  end

  @doc "Inject a browser download command for the selector into the target path."
  def download(selector, target_path) when is_binary(selector) and is_binary(target_path) do
    case System.cmd(binary_path(), ["download", selector, target_path], stderr_to_stdout: true) do
      {_output, 0} -> :ok
      {output, _code} -> {:error, {:browser_download_failed, String.trim(output)}}
    end
  end

  @doc "Path to the browser automation binary."
  def binary_path do
    Application.get_env(:gnome_garden, :browser_path, default_path())
  end

  @doc "Default browser launch args. Headless unless headed mode is explicitly configured."
  def default_args do
    browser_mode_args() ++
      ["--args", "--no-sandbox,--disable-blink-features=AutomationControlled"]
  end

  @doc "Close the browser daemon if it is running."
  def close do
    System.cmd(binary_path(), ["close"], stderr_to_stdout: true)
  end

  defp open_url(url, timeout_ms) do
    command = default_args() ++ ["open", url, "--timeout", Integer.to_string(timeout_ms)]

    case System.cmd(binary_path(), command, stderr_to_stdout: true) do
      {_output, 0} = result ->
        result

      {output, _code} ->
        if restart_required?(output) do
          _ = close()
          System.cmd(binary_path(), command, stderr_to_stdout: true)
        else
          {output, 1}
        end
    end
  end

  defp wait_for_load(timeout_ms) do
    System.cmd(
      binary_path(),
      ["wait", "--load", "networkidle", "--timeout", Integer.to_string(timeout_ms)],
      stderr_to_stdout: true
    )
  end

  defp restart_required?(output) when is_binary(output) do
    String.contains?(output, "--args ignored: daemon already running") or
      String.contains?(output, "Event stream closed")
  end

  defp parse_title(output) do
    case Regex.run(~r/\[1m(.+?)\[0m/, output) do
      [_, title] -> title
      _ -> "Unknown"
    end
  end

  defp browser_mode_args do
    case Application.get_env(:gnome_garden, :browser_mode, :auto) do
      :headed -> ["--headed"]
      :headless -> []
      :auto -> []
    end
  end

  defp default_path do
    build_root =
      Application.app_dir(:gnome_garden)
      |> Path.join("../../..")
      |> Path.expand()

    Path.join([build_root, "jido_browser-linux_amd64", "agent-browser-linux-x64"])
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
