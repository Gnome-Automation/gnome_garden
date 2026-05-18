defmodule GnomeGarden.Calculations.FindingDocumentState do
  @moduledoc """
  Presentation-facing evidence state for finding-document links.
  """

  use Ash.Resource.Calculation

  @impl true
  def init(opts) do
    return = Keyword.get(opts, :return, :state)

    if return in [:state, :label, :variant] do
      {:ok, Keyword.put(opts, :return, return)}
    else
      {:error, "`return` must be :state, :label, or :variant"}
    end
  end

  @impl true
  def load(_query, _opts, _context) do
    [:metadata, document: [file: :blob]]
  end

  @impl true
  def calculate(records, opts, _context) do
    Enum.map(records, fn record ->
      state = document_state(record)

      case Keyword.fetch!(opts, :return) do
        :state -> state
        :label -> label(state)
        :variant -> variant(state)
      end
    end)
  end

  defp document_state(%{document: document} = record) do
    explicit_state =
      case Map.get(record, :metadata) do
        metadata when is_map(metadata) -> explicit_state(metadata)
        _metadata -> nil
      end

    explicit_state || document_state_from_document(document)
  end

  defp document_state(_record), do: :needed

  defp explicit_state(metadata) do
    case metadata_value(metadata, "document_status") do
      status when status in ["needed", "linked", "fetched", "analyzed", "failed"] ->
        String.to_existing_atom(status)

      status when status in [:needed, :linked, :fetched, :analyzed, :failed] ->
        status

      _other ->
        nil
    end
  end

  defp document_state_from_document(%{file: %{blob: %{metadata: metadata}}})
       when is_map(metadata) do
    case metadata |> metadata_value("document_analysis") |> metadata_value("status") do
      "complete" -> :analyzed
      "failed" -> :failed
      "tool_unavailable" -> :failed
      "empty" -> :fetched
      "skipped" -> :fetched
      _other -> :fetched
    end
  end

  defp document_state_from_document(%{file: %{blob: %{}}}), do: :fetched

  defp document_state_from_document(%{source_url: source_url}) when is_binary(source_url),
    do: :linked

  defp document_state_from_document(%{}), do: :linked
  defp document_state_from_document(_document), do: :needed

  defp label(:needed), do: "Needed"
  defp label(:linked), do: "Linked"
  defp label(:fetched), do: "Fetched"
  defp label(:analyzed), do: "Analyzed"
  defp label(:failed), do: "Failed"
  defp label(_state), do: "Linked"

  defp variant(:needed), do: :warning
  defp variant(:linked), do: :info
  defp variant(:fetched), do: :info
  defp variant(:analyzed), do: :success
  defp variant(:failed), do: :error
  defp variant(_state), do: :default

  defp metadata_value(nil, _key), do: nil

  defp metadata_value(map, key) when is_map(map) do
    Map.get(map, key) || Map.get(map, to_string(key))
  end

  defp metadata_value(_value, _key), do: nil
end
