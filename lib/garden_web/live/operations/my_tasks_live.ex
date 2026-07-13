defmodule GnomeGardenWeb.Operations.MyTasksLive do
  use GnomeGardenWeb, :live_view

  import GnomeGardenWeb.Components.OperationsUI, only: [related_tasks_panel: 1]

  alias GnomeGarden.Operations
  alias GnomeGardenWeb.Operations.TaskPubSub

  @lanes [
    {:overdue, "Overdue", "Past their due date and still open."},
    {:today, "Due Today", "Commitments that land today."},
    {:upcoming, "Upcoming", "Scheduled for a later date."},
    {:blocked, "Blocked", "Waiting on something before work can continue."},
    {:unscheduled, "Unscheduled", "Open work without a due date yet."},
    {:recently_completed, "Recently Completed", "Closed in the last seven days."}
  ]

  @impl true
  def mount(_params, _session, socket) do
    actor = socket.assigns.current_user
    viewer = load_viewer(actor)

    {:ok,
     socket
     |> assign(:page_title, "My Tasks")
     |> assign(:viewer, viewer)
     |> assign(:viewing, viewer)
     |> assign(:team_members, if(admin?(viewer), do: load_team_members(actor), else: []))
     |> assign(:workspace, empty_workspace())}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    viewer = socket.assigns.viewer
    viewing = resolve_viewing(viewer, params, socket.assigns.team_members)

    socket =
      if connected?(socket) do
        resubscribe(socket.assigns[:subscribed_owner_id], viewing)
        assign(socket, :subscribed_owner_id, viewing && viewing.id)
      else
        socket
      end

    {:noreply,
     socket
     |> assign(:viewing, viewing)
     |> assign(:workspace, load_workspace(viewing, socket.assigns.current_user))}
  end

  @impl true
  def handle_event("switch", %{"team_member_id" => team_member_id}, socket) do
    {:noreply, push_patch(socket, to: ~p"/operations/my-tasks?team_member_id=#{team_member_id}")}
  end

  @impl true
  def handle_info(%{topic: "task:owner:" <> _owner_id}, socket) do
    GnomeGardenWeb.NavBadges.invalidate()

    previous = socket.assigns.workspace
    workspace = load_workspace(socket.assigns.viewing, socket.assigns.current_user)

    {:noreply,
     socket
     |> flash_new_assignments(previous, workspace)
     |> assign(:workspace, workspace)}
  end

  @impl true
  def render(assigns) do
    assigns = assign(assigns, :lanes, @lanes)

    ~H"""
    <.page class="pb-8">
      <.page_header eyebrow="Operations">
        My Tasks
        <:subtitle>
          <span :if={@viewing}>
            What {@viewing.display_name} needs to do next, by when, and for which record.
          </span>
          <span :if={is_nil(@viewing)}>
            No team member profile is connected to your account yet.
          </span>
        </:subtitle>
        <:actions>
          <form :if={@team_members != []} id="my-tasks-switcher" phx-change="switch">
            <select
              name="team_member_id"
              class="rounded-md bg-white px-3 py-1.5 text-sm text-gray-900 outline-1 -outline-offset-1 outline-gray-300 focus:outline-2 focus:-outline-offset-2 focus:outline-emerald-600 dark:bg-white/5 dark:text-white dark:outline-white/10"
            >
              {Phoenix.HTML.Form.options_for_select(
                Enum.map(@team_members, &{&1.display_name, &1.id}),
                @viewing && @viewing.id
              )}
            </select>
          </form>
          <.button :if={@viewing} href={new_task_path(@viewing)} variant="primary">
            New Task
          </.button>
        </:actions>
      </.page_header>

      <div :if={is_nil(@viewing)} class="mt-6">
        <.empty_state
          icon="hero-user-circle"
          title="No operator profile"
          description="Ask an admin to run the ensure-operator provisioning action for your account."
        />
      </div>

      <div :if={@viewing} class="space-y-6">
        <.related_tasks_panel
          :for={{key, title, description} <- @lanes}
          tasks={Map.get(@workspace, key, [])}
          title={title}
          description={description}
          empty_title={"No #{String.downcase(title)} tasks"}
          empty_description={lane_empty_description(key)}
          new_task_path={nil}
        />
      </div>
    </.page>
    """
  end

  defp flash_new_assignments(socket, previous, workspace) do
    known_ids = open_task_ids(previous)
    new_tasks = workspace |> open_tasks() |> Enum.reject(&MapSet.member?(known_ids, &1.id))

    case new_tasks do
      [] -> socket
      [task] -> put_flash(socket, :info, "New task assigned: #{task.title}")
      tasks -> put_flash(socket, :info, "#{length(tasks)} new tasks assigned")
    end
  end

  defp open_tasks(workspace) do
    Enum.flat_map([:overdue, :today, :upcoming, :blocked, :unscheduled], fn lane ->
      Map.get(workspace, lane, [])
    end)
  end

  defp open_task_ids(workspace) do
    workspace |> open_tasks() |> MapSet.new(& &1.id)
  end

  defp lane_empty_description(:overdue), do: "Nothing is past due. Keep it that way."
  defp lane_empty_description(:today), do: "Nothing lands today."
  defp lane_empty_description(:upcoming), do: "Nothing scheduled ahead."
  defp lane_empty_description(:blocked), do: "Nothing is waiting on someone else."
  defp lane_empty_description(:unscheduled), do: "Every open task has a date."
  defp lane_empty_description(:recently_completed), do: "Nothing completed in the last week."

  defp load_viewer(actor) do
    case Operations.get_team_member_by_user(actor.id, actor: actor, authorize?: false) do
      {:ok, member} -> member
      {:error, _error} -> nil
    end
  end

  defp admin?(%{role: :admin}), do: true
  defp admin?(_viewer), do: false

  defp resolve_viewing(viewer, %{"team_member_id" => team_member_id}, team_members)
       when is_binary(team_member_id) and team_member_id != "" do
    if admin?(viewer) do
      Enum.find(team_members, viewer, &(&1.id == team_member_id))
    else
      viewer
    end
  end

  defp resolve_viewing(viewer, _params, _team_members), do: viewer

  defp resubscribe(previous_owner_id, viewing) do
    if previous_owner_id && (!viewing || viewing.id != previous_owner_id) do
      GnomeGardenWeb.Endpoint.unsubscribe("task:owner:#{previous_owner_id}")
    end

    if viewing && viewing.id != previous_owner_id do
      TaskPubSub.subscribe_related(:owner, viewing.id)
    end

    :ok
  end

  defp load_workspace(nil, _actor), do: empty_workspace()

  defp load_workspace(viewing, actor) do
    case Operations.get_my_tasks_workspace(viewing.id, actor: actor, authorize?: false) do
      {:ok, workspace} -> workspace
      {:error, error} -> raise "failed to load my tasks workspace: #{inspect(error)}"
    end
  end

  defp empty_workspace do
    %{
      overdue: [],
      today: [],
      upcoming: [],
      blocked: [],
      unscheduled: [],
      recently_completed: []
    }
  end

  defp load_team_members(actor) do
    case Operations.list_active_team_members(actor: actor, authorize?: false) do
      {:ok, members} -> members
      {:error, _error} -> []
    end
  end

  defp new_task_path(viewing) do
    query =
      URI.encode_query(%{
        owner_team_member_id: viewing.id,
        return_to: "/operations/my-tasks"
      })

    "/operations/tasks/new?#{query}"
  end
end
