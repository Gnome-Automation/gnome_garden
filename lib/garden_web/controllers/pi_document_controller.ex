defmodule GnomeGardenWeb.PiDocumentController do
  @moduledoc """
  Ash-owned document access for the Pi sidecar.

  Pi asks the app for document metadata and downloads. Garage remains an
  implementation detail behind AshStorage, so Pi never needs object keys or
  Garage credentials.
  """
  use GnomeGardenWeb, :controller

  alias GnomeGarden.Acquisition
  alias GnomeGarden.Acquisition.Document

  def index(conn, %{"finding_id" => finding_id}) do
    case Acquisition.list_finding_documents_for_finding(finding_id) do
      {:ok, finding_documents} ->
        documents =
          Enum.map(finding_documents, fn finding_document ->
            %{
              finding_document_id: finding_document.id,
              document_role: encode_atom(finding_document.document_role),
              notes: finding_document.notes,
              linked_at: encode_datetime(finding_document.linked_at),
              metadata: finding_document.metadata,
              document: document_payload(conn, finding_document.document)
            }
          end)

        json(conn, %{success: true, data: %{documents: documents}})

      {:error, error} ->
        render_error(
          conn,
          :unprocessable_entity,
          "document_query_failed",
          Exception.message(error)
        )
    end
  end

  def show(conn, %{"id" => id}) do
    case fetch_document(id) do
      {:ok, document} ->
        json(conn, %{success: true, data: %{document: document_payload(conn, document)}})

      {:error, :not_found} ->
        render_error(conn, :not_found, "not_found", "document not found")

      {:error, error} ->
        render_error(
          conn,
          :unprocessable_entity,
          "document_query_failed",
          Exception.message(error)
        )
    end
  end

  def download(conn, %{"id" => id}) do
    with {:ok, document} <- fetch_document(id),
         {:ok, blob} <- document_blob(document),
         {:ok, data} <- download_blob(blob) do
      conn
      |> put_resp_content_type(blob.content_type || "application/octet-stream")
      |> put_resp_header("content-disposition", content_disposition(blob.filename))
      |> send_resp(:ok, data)
    else
      {:error, :not_found} ->
        render_error(conn, :not_found, "not_found", "document not found")

      {:error, error} ->
        render_error(conn, :bad_gateway, "download_failed", inspect(error))
    end
  end

  defp fetch_document(id) do
    case Acquisition.get_document(id, load: [:file_url, file: :blob]) do
      {:ok, document} -> {:ok, document}
      {:error, %Ash.Error.Query.NotFound{}} -> {:error, :not_found}
      {:error, error} -> {:error, error}
    end
  end

  defp document_payload(_conn, document) do
    %{
      id: document.id,
      title: document.title,
      summary: document.summary,
      document_type: encode_atom(document.document_type),
      source_url: document.source_url,
      uploaded_at: encode_datetime(document.uploaded_at),
      metadata: document.metadata,
      file: file_payload(document),
      download_url: url(~p"/api/pi/documents/#{document.id}/download")
    }
  end

  defp file_payload(document) do
    case document_blob(document) do
      {:ok, blob} ->
        %{
          filename: blob.filename,
          content_type: blob.content_type,
          byte_size: blob.byte_size
        }

      {:error, :not_found} ->
        nil
    end
  end

  defp document_blob(%{file: %{blob: blob}}) when is_map(blob), do: {:ok, blob}
  defp document_blob(_document), do: {:error, :not_found}

  defp download_blob(%{service_name: service, key: key} = blob) when is_atom(service) do
    service.download(key, AshStorage.Service.Context.new(service_opts(blob)))
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
    |> Application.get_env(Document, [])
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

  defp render_error(conn, status, type, message) do
    conn
    |> put_status(status)
    |> json(%{success: false, errors: [%{type: type, field: nil, message: message}]})
  end

  defp content_disposition(filename) do
    filename = filename |> to_string() |> Path.basename() |> String.replace(~r/["\r\n]/, "_")
    ~s[attachment; filename="#{filename}"]
  end

  defp encode_atom(nil), do: nil
  defp encode_atom(value) when is_atom(value), do: Atom.to_string(value)
  defp encode_atom(value), do: value

  defp encode_datetime(nil), do: nil
  defp encode_datetime(%DateTime{} = datetime), do: DateTime.to_iso8601(datetime)
end
