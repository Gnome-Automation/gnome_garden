defmodule GnomeGardenWeb.NavBadges do
  @moduledoc """
  Per-process nav badge counts for the app shell.

  The app layout is a function component that re-runs on every LiveView
  render, so the open-task count is cached in the process dictionary with a
  short TTL instead of querying per render. LiveViews that receive
  task-owner PubSub events call `invalidate/0` so their next render shows a
  fresh count immediately.
  """

  alias GnomeGarden.Operations

  @cache_key :gnome_garden_nav_task_badges
  @ttl_ms 10_000

  def task_badges(nil), do: %{}

  def task_badges(current_user) do
    now = System.monotonic_time(:millisecond)

    case Process.get(@cache_key) do
      {timestamp, badges} when now - timestamp < @ttl_ms ->
        badges

      _stale ->
        badges = compute(current_user)
        Process.put(@cache_key, {now, badges})
        badges
    end
  end

  def invalidate, do: Process.delete(@cache_key)

  defp compute(current_user) do
    with member_id when is_binary(member_id) <-
           Operations.current_team_member_id(current_user),
         {:ok, [_task | _rest] = tasks} <-
           Operations.list_open_tasks_by_owner_team_member(member_id, authorize?: false) do
      now = DateTime.utc_now()

      overdue? =
        Enum.any?(tasks, fn task ->
          task.due_at && DateTime.compare(task.due_at, now) == :lt
        end)

      %{"ops-my-tasks" => %{count: length(tasks), hot: overdue?}}
    else
      _none -> %{}
    end
  end
end
