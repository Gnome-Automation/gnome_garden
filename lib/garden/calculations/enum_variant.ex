defmodule GnomeGarden.Calculations.EnumVariant do
  @moduledoc """
  Generic calculation for mapping enum-like fields to presentation variants.
  """

  use Ash.Resource.Calculation

  @impl true
  def init(opts) do
    field = opts[:field]
    mapping = opts[:mapping]

    cond do
      not is_atom(field) ->
        {:error, "`field` must be an atom"}

      not (is_map(mapping) or Keyword.keyword?(mapping)) ->
        {:error, "`mapping` must be a map or keyword list"}

      true ->
        {:ok, Keyword.put(opts, :mapping, Map.new(mapping))}
    end
  end

  @impl true
  def load(_query, opts, _context) do
    [opts[:field]]
  end

  @impl true
  def calculate(records, opts, _context) do
    field = opts[:field]
    mapping = opts[:mapping]
    default = Keyword.get(opts, :default, :default)

    Enum.map(records, fn record ->
      record
      |> Map.get(field)
      |> then(&Map.get(mapping, &1, default))
    end)
  end
end
