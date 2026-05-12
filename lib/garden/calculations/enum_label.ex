defmodule GnomeGarden.Calculations.EnumLabel do
  @moduledoc """
  Generic calculation for turning enum-like fields into human labels.
  """

  use Ash.Resource.Calculation

  @impl true
  def init(opts) do
    field = opts[:field]

    if is_atom(field) do
      {:ok, opts}
    else
      {:error, "`field` must be an atom"}
    end
  end

  @impl true
  def load(_query, opts, _context) do
    [opts[:field]]
  end

  @impl true
  def calculate(records, opts, _context) do
    field = opts[:field]
    suffix = Keyword.get(opts, :suffix, "")

    Enum.map(records, fn record ->
      record
      |> Map.get(field)
      |> label_for(suffix)
    end)
  end

  defp label_for(nil, _suffix), do: nil

  defp label_for(value, suffix) do
    label =
      value
      |> to_string()
      |> String.replace("_", " ")
      |> String.capitalize()

    "#{label}#{suffix}"
  end
end
