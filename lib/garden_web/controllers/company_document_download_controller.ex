defmodule GnomeGardenWeb.CompanyDocumentDownloadController do
  use GnomeGardenWeb, :controller

  alias GnomeGarden.Documents

  plug :require_authenticated_user

  def show(conn, %{"id" => id}) do
    case Documents.get_document(id, load: [file: [blob: []]]) do
      {:ok, doc} ->
        case doc do
          %{file: %{blob: blob}} when is_map(blob) ->
            stream_from_storage(conn, doc, blob)

          _ when is_binary(doc.file_path) ->
            static_path = Path.join([:code.priv_dir(:gnome_garden), "static", doc.file_path])
            send_download(conn, {:file, static_path}, filename: Path.basename(doc.file_path))

          _ ->
            conn
            |> put_status(:not_found)
            |> text("File not found")
        end

      {:error, %Ash.Error.Query.NotFound{}} ->
        conn
        |> put_status(:not_found)
        |> text("Document not found")

      {:error, _reason} ->
        conn
        |> put_status(:internal_server_error)
        |> text("Failed to load document")
    end
  end

  defp stream_from_storage(conn, _doc, %{service_name: nil}) do
    conn |> put_status(:internal_server_error) |> text("Storage service unavailable")
  end

  defp stream_from_storage(conn, doc, blob) do
    service = blob.service_name

    case service.download(blob.key, AshStorage.Service.Context.new(service_opts(blob))) do
      {:ok, binary} ->
        content_type = blob.content_type || "application/octet-stream"
        filename = blob.filename || "#{doc.name}-#{doc.version}.pdf"
        safe_filename = filename |> to_string() |> Path.basename() |> String.replace(~r/["\r\n]/, "_")

        conn
        |> put_resp_content_type(content_type)
        |> put_resp_header("content-disposition", ~s(attachment; filename="#{safe_filename}"))
        |> send_resp(200, binary)

      {:error, _reason} ->
        conn
        |> put_status(:internal_server_error)
        |> text("Download failed")
    end
  end

  defp service_opts(blob) do
    persisted_opts = normalize_service_opts(blob.service_opts)

    case configured_document_service() do
      {service, runtime_opts} when service == blob.service_name ->
        Keyword.merge(persisted_opts, runtime_opts)

      _other ->
        persisted_opts
    end
  end

  defp configured_document_service do
    :gnome_garden
    |> Application.get_env(GnomeGarden.Documents.CompanyDocument, [])
    |> Keyword.get(:storage, [])
    |> Keyword.get(:service)
  end

  defp normalize_service_opts(opts) when is_list(opts), do: opts

  defp normalize_service_opts(opts) when is_map(opts) do
    opts
    |> Enum.flat_map(fn
      {key, value} when is_atom(key) ->
        [{key, value}]

      {key, value} when is_binary(key) ->
        case known_service_opt(key) do
          nil -> []
          atom_key -> [{atom_key, value}]
        end
    end)
  end

  defp normalize_service_opts(_opts), do: []

  defp known_service_opt("access_key_id"), do: :access_key_id
  defp known_service_opt("base_url"), do: :base_url
  defp known_service_opt("bucket"), do: :bucket
  defp known_service_opt("endpoint_url"), do: :endpoint_url
  defp known_service_opt("name"), do: :name
  defp known_service_opt("prefix"), do: :prefix
  defp known_service_opt("region"), do: :region
  defp known_service_opt("root"), do: :root
  defp known_service_opt("secret_access_key"), do: :secret_access_key
  defp known_service_opt(_key), do: nil

  defp require_authenticated_user(conn, _opts) do
    if conn.assigns[:current_user] do
      conn
    else
      conn
      |> redirect(to: ~p"/sign-in")
      |> halt()
    end
  end
end
