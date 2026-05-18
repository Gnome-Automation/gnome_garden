defmodule GnomeGarden.Calculations.SourceSearchFilterPerformance do
  @moduledoc """
  Operator-facing performance labels for persisted procurement source filters.
  """

  use Ash.Resource.Calculation

  @impl true
  def init(opts) do
    return = Keyword.get(opts, :return, :recommendation)

    if return in [:recommendation, :note, :variant] do
      {:ok, Keyword.put(opts, :return, return)}
    else
      {:error, "`return` must be :recommendation, :note, or :variant"}
    end
  end

  @impl true
  def load(_query, _opts, _context) do
    [
      :enabled,
      :last_returned_count,
      :last_saved_count,
      :last_run_at,
      :accepted_feedback_count,
      :parked_feedback_count,
      :rejected_feedback_count,
      :suppressed_feedback_count
    ]
  end

  @impl true
  def calculate(records, opts, _context) do
    Enum.map(records, fn record ->
      status = performance_status(record)

      case Keyword.fetch!(opts, :return) do
        :recommendation -> recommendation(status)
        :note -> note(record, status)
        :variant -> variant(status)
      end
    end)
  end

  defp performance_status(%{enabled: false}), do: :disabled

  defp performance_status(%{accepted_feedback_count: accepted})
       when is_integer(accepted) and accepted > 0,
       do: :keep

  defp performance_status(%{last_saved_count: saved}) when is_integer(saved) and saved > 0,
    do: :keep

  defp performance_status(%{
         last_saved_count: saved,
         rejected_feedback_count: rejected,
         suppressed_feedback_count: suppressed
       })
       when saved in [nil, 0] and
              ((is_integer(rejected) and rejected > 0) or
                 (is_integer(suppressed) and suppressed > 0)),
       do: :disable_noisy

  defp performance_status(%{last_run_at: nil}), do: :untested
  defp performance_status(%{last_returned_count: returned}) when returned in [nil, 0], do: :empty

  defp performance_status(%{last_returned_count: returned})
       when is_integer(returned) and returned >= 5,
       do: :disable_noisy

  defp performance_status(%{parked_feedback_count: parked})
       when is_integer(parked) and parked > 0,
       do: :watch

  defp performance_status(_record), do: :watch

  defp recommendation(:disabled), do: "Disabled"
  defp recommendation(:untested), do: "Keep searching"
  defp recommendation(:empty), do: "Keep searching"
  defp recommendation(:keep), do: "Keep"
  defp recommendation(:disable_noisy), do: "Disable noisy filter"
  defp recommendation(:watch), do: "Watch next run"

  defp note(_record, :disabled), do: "Filter is off and will not run."
  defp note(_record, :untested), do: "No run has recorded performance for this filter yet."

  defp note(record, :keep) do
    accepted = count_value(Map.get(record, :accepted_feedback_count))
    saved = count_value(Map.get(record, :last_saved_count))
    returned = count_value(Map.get(record, :last_returned_count))

    if accepted > 0 do
      "#{accepted} accepted from this filter. Last run saved #{saved} from #{returned} returned."
    else
      "#{saved} saved from #{returned} returned in the last run."
    end
  end

  defp note(record, :disable_noisy) do
    returned = count_value(Map.get(record, :last_returned_count))
    rejected = count_value(Map.get(record, :rejected_feedback_count))
    suppressed = count_value(Map.get(record, :suppressed_feedback_count))

    cond do
      rejected + suppressed > 0 ->
        "#{returned} returned in the last run. #{rejected} rejected and #{suppressed} suppressed from review."

      true ->
        "#{returned} returned and none saved in the last run."
    end
  end

  defp note(_record, :empty), do: "Last run returned no results for this filter."

  defp note(%{last_returned_count: returned, last_saved_count: saved}, :watch),
    do:
      "#{saved || 0} saved from #{returned || 0} returned. Watch one more run before changing it."

  defp count_value(value) when is_integer(value), do: value
  defp count_value(_value), do: 0

  defp variant(:keep), do: :success
  defp variant(:disable_noisy), do: :warning
  defp variant(:watch), do: :info
  defp variant(:empty), do: :default
  defp variant(:untested), do: :default
  defp variant(:disabled), do: :default
end
