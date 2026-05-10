defmodule GnomeGarden.Procurement.Changes.EnqueueDocumentIngest do
  @moduledoc """
  After a Bid is created or updated, if `metadata["documents"]` is a non-empty
  list, enqueue an `IngestFindingDocuments` job so the URLs get downloaded and
  attached to the bid's projected `Acquisition.Finding`.
  """

  use Ash.Resource.Change

  alias GnomeGarden.Acquisition.Workers.IngestFindingDocuments

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.after_transaction(changeset, fn _changeset, result ->
      case result do
        {:ok, bid} ->
          if has_documents?(bid) do
            %{"bid_id" => bid.id}
            |> IngestFindingDocuments.new()
            |> Oban.insert()
          end

          {:ok, bid}

        other ->
          other
      end
    end)
  end

  defp has_documents?(%{metadata: metadata}) when is_map(metadata) do
    case Map.get(metadata, "documents") || Map.get(metadata, :documents) do
      [_ | _] -> true
      _ -> false
    end
  end

  defp has_documents?(_bid), do: false
end
