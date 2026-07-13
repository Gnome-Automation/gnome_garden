defmodule GnomeGarden.Automation.Actions.SweepTimeTriggers do
  @moduledoc """
  Emits time-based automation events into the same evaluator as record
  events.

  Deadline events are episodic: a bid emits once per threshold bucket
  (14/7/3/1 days) per due date, so a rule keyed on `deadline_bucket` fires
  exactly once at each escalation and a rescheduled deadline starts fresh
  episodes. Overdue-task events are keyed by task and due date, so a
  rescheduled task can go overdue again. Event depth is inherited from
  automation-created tasks so recursion cannot reset through time triggers.
  """

  use Ash.Resource.Actions.Implementation

  alias GnomeGarden.Automation
  alias GnomeGarden.Operations
  alias GnomeGarden.Procurement

  @deadline_buckets [14, 7, 3, 1]
  @bid_due_window_days List.first(@deadline_buckets)

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
      record_once("task_overdue:#{task.id}:#{DateTime.to_iso8601(task.due_at)}", %{
        resource: "task",
        action: "overdue",
        record_id: task.id,
        depth: automation_depth(task),
        data: %{
          "title" => task.title,
          "priority" => Atom.to_string(task.priority),
          "task_type" => Atom.to_string(task.task_type),
          "owner_team_member_id" => task.owner_team_member_id,
          "due_at" => DateTime.to_iso8601(task.due_at),
          "days_overdue" => days_between(task.due_at, DateTime.utc_now())
        }
      })
    end)
  end

  defp sweep_bids_due_soon do
    {:ok, bids} = Procurement.list_bids_due_within(@bid_due_window_days, authorize?: false)

    Enum.count(bids, fn bid ->
      days_until_due = days_between(DateTime.utc_now(), bid.due_at)
      bucket = deadline_bucket(days_until_due)

      record_once(
        "bid_due_soon:#{bid.id}:#{DateTime.to_iso8601(bid.due_at)}:#{bucket}",
        %{
          resource: "bid",
          action: "due_soon",
          record_id: bid.id,
          data: %{
            "title" => bid.title,
            "agency" => bid.agency,
            "status" => Atom.to_string(bid.status),
            "score_tier" => bid.score_tier && Atom.to_string(bid.score_tier),
            "due_at" => DateTime.to_iso8601(bid.due_at),
            "days_until_due" => days_until_due,
            "deadline_bucket" => bucket
          }
        }
      )
    end)
  end

  # Smallest configured bucket the deadline currently falls inside; the
  # dedupe key includes it, so each escalation emits exactly one new event.
  defp deadline_bucket(days_until_due) do
    @deadline_buckets
    |> Enum.reverse()
    |> Enum.find(List.first(@deadline_buckets), &(days_until_due <= &1))
  end

  defp record_once(dedupe_key, attrs) do
    case Automation.record_automation_event(
           Map.put(attrs, :dedupe_key, dedupe_key),
           authorize?: false
         ) do
      {:ok, _event} ->
        true

      {:error, error} ->
        if duplicate_key?(error) do
          false
        else
          raise "time sweep failed to record #{dedupe_key}: #{Exception.message(error)}"
        end
    end
  end

  defp duplicate_key?(%Ash.Error.Invalid{} = error),
    do: Exception.message(error) =~ "has already been taken"

  defp duplicate_key?(_error), do: false

  defp automation_depth(%{metadata: %{"automation_depth" => depth}}) when is_integer(depth),
    do: depth

  defp automation_depth(_task), do: 0

  # Both sweeps filter on non-nil due dates, so inputs are always present.
  defp days_between(earlier, later),
    do: DateTime.diff(later, earlier, :second) |> div(86_400)
end
