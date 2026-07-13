defmodule GnomeGarden.Automation.Actions.SweepTimeTriggers do
  @moduledoc """
  Emits time-based automation events into the same evaluator as record
  events.

  Each sweep is idempotent: events carry a dedupe key per subject, so a bid
  approaching its deadline or a task going overdue fires exactly once no
  matter how many sweeps observe it. Thresholds live in rule criteria — the
  sweep only reports facts like `days_until_due`.
  """

  use Ash.Resource.Actions.Implementation

  alias GnomeGarden.Automation
  alias GnomeGarden.Operations
  alias GnomeGarden.Procurement

  @bid_due_window_days 14

  @impl true
  def run(_input, _opts, _context) do
    {:ok,
     %{
       "task_overdue" => sweep_overdue_tasks(),
       "bid_due_soon" => sweep_bids_due_soon()
     }}
  end

  defp sweep_overdue_tasks do
    {:ok, tasks} = Operations.list_overdue_tasks(authorize?: false)

    Enum.count(tasks, fn task ->
      record_once("task_overdue:#{task.id}", %{
        resource: "task",
        action: "overdue",
        record_id: task.id,
        data: %{
          "title" => task.title,
          "priority" => Atom.to_string(task.priority),
          "task_type" => Atom.to_string(task.task_type),
          "owner_team_member_id" => task.owner_team_member_id,
          "due_at" => task.due_at && DateTime.to_iso8601(task.due_at),
          "days_overdue" => days_between(task.due_at, DateTime.utc_now())
        }
      })
    end)
  end

  defp sweep_bids_due_soon do
    {:ok, bids} = Procurement.list_bids_due_within(@bid_due_window_days, authorize?: false)

    Enum.count(bids, fn bid ->
      record_once("bid_due_soon:#{bid.id}", %{
        resource: "bid",
        action: "due_soon",
        record_id: bid.id,
        data: %{
          "title" => bid.title,
          "agency" => bid.agency,
          "status" => Atom.to_string(bid.status),
          "score_tier" => bid.score_tier && Atom.to_string(bid.score_tier),
          "due_at" => bid.due_at && DateTime.to_iso8601(bid.due_at),
          "days_until_due" => days_between(DateTime.utc_now(), bid.due_at)
        }
      })
    end)
  end

  defp record_once(dedupe_key, attrs) do
    case Automation.record_automation_event(
           Map.put(attrs, :dedupe_key, dedupe_key),
           authorize?: false
         ) do
      {:ok, _event} -> true
      {:error, _already_recorded} -> false
    end
  end

  defp days_between(nil, _later), do: nil
  defp days_between(_earlier, nil), do: nil

  defp days_between(earlier, later),
    do: DateTime.diff(later, earlier, :second) |> div(86_400)
end
