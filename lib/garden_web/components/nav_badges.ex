defmodule GnomeGardenWeb.NavBadges do
  @moduledoc """
  Per-process nav badge counts for the app shell.

  The app layout is a function component that re-runs on every LiveView
  render, so the aggregate lookup is cached in the process dictionary with a
  short TTL, keyed by user. LiveViews that receive task-owner PubSub events
  call `invalidate/0` so their next render shows a fresh count immediately.
  """

  alias GnomeGarden.Operations

  @cache_key :gnome_garden_nav_task_badges
  @ttl_ms 10_000

  def task_badges(nil), do: %{}

  def task_badges(current_user) do
    now = System.monotonic_time(:millisecond)

    case Process.get(@cache_key) do
      {user_id, timestamp, badges}
      when user_id == current_user.id and now - timestamp < @ttl_ms ->
        badges

      _stale ->
        badges = compute(current_user)
        Process.put(@cache_key, {current_user.id, now, badges})
        badges
    end
  end

  def invalidate, do: Process.delete(@cache_key)

  defp compute(current_user) do
    case Operations.get_team_member_by_user(current_user.id,
           authorize?: false,
           load: [:open_task_count, :has_overdue_tasks]
         ) do
      {:ok, %{open_task_count: count} = member} when count > 0 ->
        %{"ops-my-tasks" => %{count: count, hot: member.has_overdue_tasks}}

      _none_or_zero ->
        %{}
    end
  end
end
