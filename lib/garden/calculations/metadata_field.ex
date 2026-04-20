defmodule GnomeGarden.Calculations.MetadataField do
  @moduledoc """
  Extracts a field from a record metadata map with optional atom casting.
  """

  use Ash.Resource.Calculation

  @impl true
  def init(opts) do
    field = opts[:field]
    cast = Keyword.get(opts, :cast, :string)
    allowed = Keyword.get(opts, :allowed)

    cond do
      not (is_binary(field) or is_atom(field)) ->
        {:error, "`field` must be a string or atom"}

      cast not in [:string, :atom, :raw] ->
        {:error, "`cast` must be :string, :atom, or :raw"}

      cast == :atom and not is_list(allowed) ->
        {:error, "`allowed` must be provided when cast: :atom"}

      true ->
        {:ok, opts}
    end
  end

  @impl true
  def load(_query, _opts, _context), do: [:metadata]

  @impl true
  def calculate(records, opts, _context) do
    Enum.map(records, fn record ->
      record
      |> metadata_value(opts[:field])
      |> cast_value(opts)
    end)
  end

  defp metadata_value(%{metadata: metadata}, field) when is_map(metadata) do
    Map.get(metadata, field) || Map.get(metadata, to_string(field))
  end

  defp metadata_value(_record, _field), do: nil

  defp cast_value(value, opts) do
    case Keyword.get(opts, :cast, :string) do
      :raw ->
        value

      :string when is_binary(value) ->
        value

      :string ->
        nil

      :atom when is_binary(value) ->
        allowed = Keyword.fetch!(opts, :allowed)

        try do
          atom_value = String.to_existing_atom(value)
          if atom_value in allowed, do: atom_value, else: nil
        rescue
          ArgumentError -> nil
        end

      :atom when is_atom(value) ->
        allowed = Keyword.fetch!(opts, :allowed)
        if value in allowed, do: value, else: nil
    end
  end
end
