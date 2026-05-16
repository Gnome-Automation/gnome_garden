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
  alias GnomeGarden.Procurement

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"bid_id" => bid_id}}) when is_binary(bid_id) do
    with {:ok, bid} <- Procurement.get_bid(bid_id),
         documents when is_list(documents) and documents != [] <- list_documents(bid),
         {:ok, finding} <- Acquisition.get_finding_by_source_bid(bid_id) do
      results = Enum.map(documents, &ingest_document(&1, finding))
      persist_packet_status(bid, documents, results)
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

      case downloader().download(descriptor) do
        {:ok, temp_path, content_type} ->
          try do
            upload = %Plug.Upload{
              path: temp_path,
              filename: filename,
              content_type: content_type
            }

            case create_document(upload, url, document_type, finding, filename) do
              {:ok, _document} ->
                {:ok, %{url: url, filename: filename, document_type: document_type}}

              {:error, reason} ->
                ingest_error(url, filename, finding, reason)
            end
          after
            cleanup(temp_path)
          end

        {:error, reason} ->
          ingest_error(url, filename, finding, reason)
      end
    else
      {:skip, %{reason: "missing_url"}}
    end
  end

  defp ingest_document(_, _), do: {:skip, %{reason: "invalid_descriptor"}}

  defp ingest_error(url, filename, finding, reason) do
    Logger.warning(
      "Document ingest failed for #{url} (finding #{finding.id}): #{inspect(reason)}"
    )

    {:error, %{url: url, filename: filename, reason: inspect(reason)}}
  end

  defp stringify_keys(map) do
    Map.new(map, fn {key, value} -> {to_string(key), value} end)
  end

  defp downloader do
    Application.get_env(
      :gnome_garden,
      :acquisition_document_downloader,
      GnomeGarden.Acquisition.DocumentDownloader
    )
  end

  defp create_document(upload, source_url, document_type, finding, filename) do
    Acquisition.upload_document_for_finding(%{
      title: filename,
      document_type: document_type,
      source_url: source_url,
      file: upload,
      finding_id: finding.id,
      document_role: role_for_type(document_type),
      summary: "Captured from source packet ingest.",
      metadata: %{
        "ingest" => %{
          "source" => "bid_document_ingest",
          "captured_at" =>
            DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()
        }
      },
      finding_document_metadata: %{
        "source_url" => source_url,
        "ingested_by" => __MODULE__ |> to_string()
      }
    })
  end

  defp persist_packet_status(bid, documents, results) do
    ok = Enum.filter(results, &match?({:ok, _}, &1))
    errors = Enum.filter(results, &match?({:error, _}, &1))

    status =
      cond do
        ok != [] ->
          "present"

        Enum.any?(errors, fn {:error, result} -> result.reason =~ "login_required" end) ->
          "login_required"

        errors != [] ->
          "download_failed"

        documents == [] ->
          "missing"

        true ->
          "missing"
      end

    metadata =
      (bid.metadata || %{})
      |> Map.put("packet", %{
        "status" => status,
        "document_count" => length(ok),
        "failed_count" => length(errors),
        "ingested_at" =>
          DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601(),
        "errors" => Enum.map(errors, fn {:error, result} -> result end)
      })

    case Procurement.record_bid_document_ingest(bid, %{metadata: metadata}) do
      {:ok, _bid} ->
        :ok

      {:error, error} ->
        Logger.warning(
          "Failed to record packet ingest state for bid #{bid.id}: #{inspect(error)}"
        )

        :ok
    end
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
