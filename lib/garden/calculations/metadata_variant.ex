defmodule GnomeGarden.Calculations.MetadataVariant do
  @moduledoc """
  Maps a metadata field to a presentation variant.
  """

  use Ash.Resource.Calculation

  @impl true
  def init(opts) do
    field = opts[:field]
    mapping = opts[:mapping]

    cond do
      not (is_binary(field) or is_atom(field)) ->
        {:error, "`field` must be a string or atom"}

      not (is_map(mapping) or Keyword.keyword?(mapping)) ->
        {:error, "`mapping` must be a map or keyword list"}

      true ->
        {:ok, Keyword.put(opts, :mapping, Map.new(mapping))}
    end
  end

  @impl true
  def load(_query, _opts, _context), do: [:metadata]

  @impl true
  def calculate(records, opts, _context) do
    default = Keyword.get(opts, :default, :default)
    mapping = opts[:mapping]

    Enum.map(records, fn record ->
      record
      |> metadata_value(opts[:field])
      |> normalize_key()
      |> then(&Map.get(mapping, &1, default))
    end)
  end

  defp metadata_value(%{metadata: metadata}, field) when is_map(metadata) do
    Map.get(metadata, field) || Map.get(metadata, to_string(field))
  end

  defp metadata_value(_record, _field), do: nil

  defp normalize_key(value) when is_atom(value), do: value

  defp normalize_key(value) when is_binary(value) do
    try do
      String.to_existing_atom(value)
    rescue
      ArgumentError -> value
    end
  end

  defp normalize_key(value), do: value
end
