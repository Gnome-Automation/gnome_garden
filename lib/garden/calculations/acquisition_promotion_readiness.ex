defmodule GnomeGarden.Calculations.AcquisitionPromotionReadiness do
  @moduledoc """
  Exposes promotion readiness and blockers for acquisition findings.
  """

  use Ash.Resource.Calculation

  alias GnomeGarden.Acquisition.PromotionRules

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
  def load(_query, _opts, _context), do: PromotionRules.required_load()

  @impl true
  def calculate(records, opts, _context) do
    Enum.map(records, fn record ->
      blockers = PromotionRules.blockers(record)

      case Keyword.fetch!(opts, :return) do
        :ready -> blockers == []
        :blockers -> blockers
      end
    end)
  end
end
