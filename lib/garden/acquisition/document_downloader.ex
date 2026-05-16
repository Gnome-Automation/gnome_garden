defmodule GnomeGarden.Acquisition.DocumentDownloader do
  @moduledoc """
  Downloads procurement packet descriptors for acquisition document ingest.

  Public document links are fetched with Req. Protected PlanetBids links fall
  back to the agent browser so the credentialed portal flow can retrieve files
  that unauthenticated HTTP cannot access.
  """

  alias GnomeGarden.Agents.Tools.Browser
  alias GnomeGarden.Agents.Tools.Browser.{Extract, Navigate}
  alias GnomeGarden.Procurement.SourceCredentials

  @max_bytes 50 * 1024 * 1024
  @timeout_ms 30_000

  def download(descriptor) when is_map(descriptor) do
    descriptor = stringify_keys(descriptor)
    url = Map.get(descriptor, "url")

    if is_binary(url) and url != "" do
      case http_download(url) do
        {:error, :login_required} = login_error ->
          if browser_fallback?(descriptor), do: browser_download(descriptor), else: login_error

        result ->
          result
      end
    else
      {:error, :missing_url}
    end
  end

  def download(_descriptor), do: {:error, :invalid_descriptor}

  defp http_download(url) do
    case Req.get(url,
           receive_timeout: @timeout_ms,
           connect_options: [timeout: @timeout_ms],
           max_redirects: 5,
           headers: [{"user-agent", "GnomeGarden DocumentIngest/1.0"}]
         ) do
      {:ok, %Req.Response{status: status} = response} when status in 200..299 ->
        if login_page?(response),
          do: {:error, :login_required},
          else: write_response_to_temp(response)

      {:ok, %Req.Response{status: status}} when status in [401, 403] ->
        {:error, :login_required}

      {:ok, %Req.Response{status: status}} ->
        {:error, {:http_status, status}}

      {:error, reason} ->
        {:error, reason}
    end
  rescue
    e -> {:error, Exception.message(e)}
  end

  defp browser_fallback?(descriptor) do
    (Map.get(descriptor, "requires_login") in [true, "true"] or
       planetbids_url?(Map.get(descriptor, "url"))) and browser_login_url(descriptor) != nil
  end

  defp browser_download(descriptor) do
    with {:ok, _credentials} <- SourceCredentials.planetbids_credentials(),
         :ok <- ensure_browser_login(descriptor),
         {:ok, path} <- click_download_link(descriptor) do
      {:ok, path, content_type_for_path(path)}
    end
  end

  defp ensure_browser_login(descriptor) do
    login_url = browser_login_url(descriptor)

    with {:ok, credentials} <- SourceCredentials.planetbids_credentials(),
         {:ok, _} <- Navigate.run(%{url: login_url}, %{}),
         {:ok, %{data: %{"submitted" => submitted?}}} <-
           Extract.run(%{js: planetbids_login_js(credentials)}, %{}) do
      if submitted?, do: Process.sleep(3_500)
      :ok
    else
      {:error, reason} -> {:error, reason}
      _ -> :ok
    end
  end

  defp click_download_link(descriptor) do
    url = Map.fetch!(descriptor, "url")
    filename = Map.get(descriptor, "filename") || basename(url)

    temp_path =
      Path.join(
        System.tmp_dir!(),
        "gnome-doc-#{Ecto.UUID.generate()}-#{Path.basename(filename)}"
      )

    id = "gnome-document-download-#{System.unique_integer([:positive])}"

    with {_output, 0} <-
           System.cmd(Browser.binary_path(), ["eval", inject_link_js(id, url)],
             stderr_to_stdout: true
           ),
         {_output, 0} <-
           System.cmd(Browser.binary_path(), ["download", "##{id}", temp_path],
             stderr_to_stdout: true
           ),
         :ok <- validate_download(temp_path) do
      {:ok, temp_path}
    else
      {:error, reason} ->
        cleanup(temp_path)
        {:error, reason}

      {output, _code} ->
        cleanup(temp_path)
        {:error, {:browser_download_failed, String.trim(output)}}
    end
  end

  defp validate_download(path) do
    cond do
      not File.exists?(path) -> {:error, :browser_download_missing}
      File.stat!(path).size > @max_bytes -> {:error, :too_large}
      true -> :ok
    end
  end

  defp write_response_to_temp(%Req.Response{} = response) do
    temp_path = Path.join(System.tmp_dir!(), "gnome-doc-#{Ecto.UUID.generate()}")
    body = response.body

    cond do
      is_binary(body) and byte_size(body) <= @max_bytes ->
        File.write!(temp_path, body)
        {:ok, temp_path, content_type_for(response)}

      is_binary(body) ->
        {:error, :too_large}

      true ->
        {:error, {:unsupported_body, response}}
    end
  end

  defp content_type_for(%Req.Response{} = response) do
    case Req.Response.get_header(response, "content-type") do
      [type | _] -> type
      _ -> "application/octet-stream"
    end
  end

  defp content_type_for_path(path), do: MIME.from_path(path) || "application/octet-stream"

  defp login_page?(%Req.Response{body: body} = response) when is_binary(body) do
    content_type = content_type_for(response)

    String.contains?(content_type, "text/html") and
      String.match?(body, ~r/login|sign in|password/i)
  end

  defp login_page?(_response), do: false

  defp browser_login_url(descriptor) do
    [
      Map.get(descriptor, "captured_from"),
      Map.get(descriptor, "source_url"),
      Map.get(descriptor, "listing_url"),
      Map.get(descriptor, "url")
    ]
    |> Enum.find(&planetbids_url?/1)
  end

  defp planetbids_url?(url) when is_binary(url), do: String.contains?(url, "planetbids")
  defp planetbids_url?(_url), do: false

  defp inject_link_js(id, url) do
    encoded_id = Jason.encode!(id)
    encoded_url = Jason.encode!(url)

    """
    (function() {
      var id = #{encoded_id};
      var url = #{encoded_url};
      var existing = document.getElementById(id);
      if (existing) existing.remove();
      var link = document.createElement('a');
      link.id = id;
      link.href = url;
      link.download = '';
      link.textContent = 'Download packet';
      document.body.appendChild(link);
      return {inserted: true, id: id};
    })()
    """
  end

  defp planetbids_login_js(%{username: username, password: password}) do
    encoded_username = Jason.encode!(username)
    encoded_password = Jason.encode!(password)

    """
    (function() {
      var username = #{encoded_username};
      var password = #{encoded_password};
      var userInput = document.querySelector('input[type="email"], input[name*="email" i], input[id*="email" i], input[name*="user" i], input[id*="user" i]');
      var passInput = document.querySelector('input[type="password"], input[name*="password" i], input[id*="password" i]');

      if (!userInput || !passInput) {
        return {submitted: false, reason: 'no_login_form'};
      }

      userInput.focus();
      userInput.value = username;
      userInput.dispatchEvent(new Event('input', {bubbles: true}));
      userInput.dispatchEvent(new Event('change', {bubbles: true}));

      passInput.focus();
      passInput.value = password;
      passInput.dispatchEvent(new Event('input', {bubbles: true}));
      passInput.dispatchEvent(new Event('change', {bubbles: true}));

      var form = passInput.closest('form') || userInput.closest('form');
      var button = document.querySelector('button[type="submit"], input[type="submit"], button[id*="login" i], button[class*="login" i]');

      if (form && form.requestSubmit) {
        form.requestSubmit();
      } else if (button) {
        button.click();
      } else if (form) {
        form.submit();
      } else {
        return {submitted: false, reason: 'no_submit_control'};
      }

      return {submitted: true};
    })()
    """
  end

  defp stringify_keys(map), do: Map.new(map, fn {key, value} -> {to_string(key), value} end)
  defp cleanup(path), do: File.rm(path)

  defp basename(url) do
    case URI.parse(url) do
      %URI{path: path} when is_binary(path) ->
        case Path.basename(path) do
          "" -> "document"
          name -> name
        end

      _ ->
        "document"
    end
  end
end
