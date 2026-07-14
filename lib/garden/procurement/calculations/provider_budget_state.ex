defmodule GnomeGarden.Procurement.Calculations.ProviderBudgetState do
  @moduledoc false

  use Ash.Resource.Calculation

  alias GnomeGarden.Acquisition.ProviderBudgetPolicy

  @impl true
  def calculate(records, _opts, context) do
    Enum.map(records, fn
      %{source_type: :sam_gov} = source -> sam_gov_budget(source, context)
      _source -> nil
    end)
  end

  defp sam_gov_budget(source, context) do
    case ProviderBudgetPolicy.current_window(
           "sam_gov",
           "search",
           budget_options(source, context)
         ) do
      {:ok, budget} ->
        %{
          "remaining_requests" => budget.remaining_requests,
          "request_limit" => budget.request_limit,
          "resets_at" => budget.resets_at && DateTime.to_iso8601(budget.resets_at)
        }

      {:error, error} ->
        %{"error" => inspect(error)}
    end
  end

  defp budget_options(source, context) do
    [actor: Map.get(context, :actor)]
    |> then(fn options ->
      if is_integer(source.rate_limit_per_day),
        do: Keyword.put(options, :request_limit, source.rate_limit_per_day),
        else: options
    end)
  end
end
