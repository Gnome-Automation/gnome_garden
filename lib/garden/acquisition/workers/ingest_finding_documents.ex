defmodule GnomeGarden.Acquisition.Workers.IngestFindingDocuments do
  @moduledoc """
  Downloads bid-attached documents from URLs and stores them via ash_storage.

  Pi extracts document URLs (RFP PDF, scope, addenda) when scanning a bid and
  passes them in `metadata["documents"]`. This worker:

    1. Resolves the bid's projected `Acquisition.Finding`.
    2. For each `%{"url", "filename", "document_type"}` descriptor:
       a. Streams the file to a temp path with a size cap.
       b. Creates an `Acquisition.Document` via the upload-for-finding action,
          attaching the file and linking it to the finding in one call.
       c. Removes the temp file.

  Failures on individual documents are logged and skipped — one missing PDF
  must not block the rest. The job itself is idempotent enough for `max_attempts: 3`
  because document_id uniqueness is on `(finding_id, source_url)` per descriptor.
  """

  use Oban.Worker, queue: :default, max_attempts: 3

  require Logger

  alias GnomeGarden.Acquisition

  @max_bytes 50 * 1024 * 1024
  @timeout_ms 30_000

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"bid_id" => bid_id}}) when is_binary(bid_id) do
    with {:ok, bid} <- GnomeGarden.Procurement.get_bid(bid_id),
         documents when is_list(documents) and documents != [] <- list_documents(bid),
         {:ok, finding} <- Acquisition.get_finding_by_source_bid(bid_id) do
      Enum.each(documents, &ingest_document(&1, finding))
      :ok
    else
      [] -> :ok
      nil -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  def perform(%Oban.Job{args: args}) do
    {:error, {:unexpected_args, args}}
  end

  defp list_documents(%{metadata: metadata}) when is_map(metadata) do
    case metadata |> stringify_keys() |> Map.get("documents") do
      list when is_list(list) -> list
      _ -> []
    end
  end

  defp list_documents(_bid), do: []

  defp ingest_document(descriptor, finding) when is_map(descriptor) do
    descriptor = stringify_keys(descriptor)
    url = Map.get(descriptor, "url")

    if is_binary(url) and url != "" do
      filename = Map.get(descriptor, "filename") || basename(url)

      document_type = parse_document_type(Map.get(descriptor, "document_type"))

      with {:ok, temp_path, content_type} <- download(url),
           upload <- %Plug.Upload{
             path: temp_path,
             filename: filename,
             content_type: content_type
           },
           {:ok, _document} <- create_document(upload, url, document_type, finding, filename) do
        cleanup(temp_path)
        :ok
      else
        {:error, reason} ->
          Logger.warning(
            "Document ingest failed for #{url} (finding #{finding.id}): #{inspect(reason)}"
          )

          :error
      end
    else
      :ok
    end
  end

  defp ingest_document(_, _), do: :ok

  defp stringify_keys(map) do
    Map.new(map, fn {key, value} -> {to_string(key), value} end)
  end

  defp download(url) do
    case Req.get(url,
           receive_timeout: @timeout_ms,
           connect_options: [timeout: @timeout_ms],
           max_redirects: 5,
           headers: [{"user-agent", "GnomeGarden DocumentIngest/1.0"}]
         ) do
      {:ok, %Req.Response{status: status} = response} when status in 200..299 ->
        write_response_to_temp(response)

      {:ok, %Req.Response{status: status}} ->
        {:error, {:http_status, status}}

      {:error, reason} ->
        {:error, reason}
    end
  rescue
    e -> {:error, Exception.message(e)}
  end

  defp write_response_to_temp(%Req.Response{} = response) do
    temp_path =
      Path.join(
        System.tmp_dir!(),
        "gnome-doc-#{Ecto.UUID.generate()}"
      )

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

  defp create_document(upload, source_url, document_type, finding, filename) do
    Acquisition.upload_document_for_finding(%{
      title: filename,
      document_type: document_type,
      source_url: source_url,
      file: upload,
      finding_id: finding.id,
      document_role: role_for_type(document_type)
    })
  end

  # FindingDocument.document_role enum overlaps but isn't identical to
  # Document.document_type — map types not present in role to :supporting.
  defp role_for_type(:solicitation), do: :solicitation
  defp role_for_type(:scope), do: :scope
  defp role_for_type(:pricing), do: :pricing
  defp role_for_type(:addendum), do: :addendum
  defp role_for_type(_), do: :supporting

  defp cleanup(path) do
    _ = File.rm(path)
    :ok
  end

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

  defp parse_document_type(nil), do: :other

  defp parse_document_type(value) when is_binary(value) do
    case value do
      "solicitation" -> :solicitation
      "scope" -> :scope
      "pricing" -> :pricing
      "addendum" -> :addendum
      "intake_note" -> :intake_note
      _ -> :other
    end
  end

  defp parse_document_type(value) when is_atom(value) do
    if value in [:solicitation, :scope, :pricing, :addendum, :intake_note],
      do: value,
      else: :other
  end

  defp parse_document_type(_), do: :other
end
