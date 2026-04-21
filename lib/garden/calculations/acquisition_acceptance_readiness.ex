defmodule GnomeGarden.Calculations.AcquisitionAcceptanceReadiness do
  @moduledoc """
  Exposes acceptance readiness and blockers for acquisition findings.
  """

  use Ash.Resource.Calculation

  alias GnomeGarden.Acquisition.AcceptanceRules

  @impl true
  def init(opts) do
    return = Keyword.get(opts, :return, :ready)

    if return in [:ready, :blockers] do
      {:ok, opts}
    else
      {:error, "`return` must be :ready or :blockers"}
    end
  end

  @impl true
  def load(_query, _opts, _context), do: AcceptanceRules.required_load()

  @impl true
  def calculate(records, opts, _context) do
    Enum.map(records, fn record ->
      blockers = AcceptanceRules.blockers(record)

      case Keyword.fetch!(opts, :return) do
        :ready -> blockers == []
        :blockers -> blockers
      end
    end)
  end
end
