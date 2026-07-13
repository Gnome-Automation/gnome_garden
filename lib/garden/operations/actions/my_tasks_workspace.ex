defmodule GnomeGarden.Operations.Actions.MyTasksWorkspace do
  @moduledoc """
  Builds the per-operator My Tasks workspace in one read.

  Lanes: blocked, overdue, today, upcoming, unscheduled, and recently
  completed (last seven days). Blocked wins over date lanes because a blocked
  task cannot be acted on regardless of its due date.
  """

  use Ash.Resource.Actions.Implementation

  require Ash.Query

  @recently_completed_days 7

  @impl true
  def run(input, _opts, context) do
    owner_team_member_id = Ash.ActionInput.get_argument(input, :owner_team_member_id)
    completed_after = DateTime.add(DateTime.utc_now(), -@recently_completed_days, :day)

    tasks =
      GnomeGarden.Operations.Task
      |> Ash.Query.filter(
        owner_team_member_id == ^owner_team_member_id and
          (status in [:pending, :in_progress, :blocked] or
             (status == :completed and completed_at > ^completed_after))
      )
      |> Ash.Query.load([:status_variant, :priority_variant])
      |> Ash.Query.sort(due_at: :asc, inserted_at: :desc)
      |> Ash.read!(actor: context.actor, authorize?: context.authorize?)

    {open, completed} = Enum.split_with(tasks, &(&1.status != :completed))
    {blocked, actionable} = Enum.split_with(open, &(&1.status == :blocked))

    lanes =
      Enum.group_by(actionable, fn task ->
        case due_lane(task.due_at) do
          :overdue -> :overdue
          :today -> :today
          :upcoming -> :upcoming
          :unscheduled -> :unscheduled
        end
      end)

    {:ok,
     %{
       overdue: Map.get(lanes, :overdue, []),
       today: Map.get(lanes, :today, []),
       upcoming: Map.get(lanes, :upcoming, []),
       blocked: blocked,
       unscheduled: Map.get(lanes, :unscheduled, []),
       recently_completed: Enum.sort_by(completed, & &1.completed_at, {:desc, DateTime})
     }}
  end

  defp due_lane(nil), do: :unscheduled

  defp due_lane(due_at) do
    today = Date.utc_today()

    case Date.compare(DateTime.to_date(due_at), today) do
      :lt -> :overdue
      :eq -> :today
      :gt -> :upcoming
    end
  end
end
