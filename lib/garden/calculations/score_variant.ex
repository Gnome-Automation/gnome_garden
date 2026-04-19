defmodule GnomeGarden.Calculations.ScoreVariant do
  @moduledoc """
  Maps an integer score into a presentation variant.
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
  def load(_query, opts, _context), do: [opts[:field]]

  @impl true
  def calculate(records, opts, _context) do
    field = opts[:field]

    Enum.map(records, fn record ->
      record
      |> Map.get(field)
      |> variant_for_score()
    end)
  end

  defp variant_for_score(score) when is_integer(score) and score >= 80, do: :success
  defp variant_for_score(score) when is_integer(score) and score >= 60, do: :info
  defp variant_for_score(score) when is_integer(score) and score >= 40, do: :warning
  defp variant_for_score(score) when is_integer(score), do: :default
  defp variant_for_score(_score), do: :default
end
