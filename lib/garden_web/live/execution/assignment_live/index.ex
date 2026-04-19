defmodule GnomeGardenWeb.Execution.AssignmentLive.Index do
  use GnomeGardenWeb, :live_view

  import GnomeGardenWeb.Execution.Helpers

  alias GnomeGarden.Execution

  @impl true
  def mount(_params, _session, socket) do
    assignments = load_assignments(socket.assigns.current_user)

    {:ok,
     socket
     |> assign(:page_title, "Assignments")
     |> assign(:assignment_count, length(assignments))
     |> assign(:confirmed_count, Enum.count(assignments, &(&1.status == :confirmed)))
     |> assign(:in_progress_count, Enum.count(assignments, &(&1.status == :in_progress)))
     |> assign(:onsite_count, Enum.count(assignments, &(&1.location_mode == :onsite)))
     |> stream(:assignments, assignments)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.page class="pb-8">
      <.page_header eyebrow="Execution">
        Assignments
        <:subtitle>
          Coordinate scheduled execution across project work, service dispatch, and hybrid delivery without losing ownership.
        </:subtitle>
        <:actions>
          <.button navigate={~p"/execution/work-items"}>
            <.icon name="hero-queue-list" class="size-4" /> Work Items
          </.button>
          <.button navigate={~p"/execution/assignments/new"} variant="primary">
            <.icon name="hero-plus" class="size-4" /> New Assignment
          </.button>
        </:actions>
      </.page_header>

      <div class="grid gap-4 md:grid-cols-4">
        <.stat_card
          title="Assignments"
          value={Integer.to_string(@assignment_count)}
          description="Scheduled work allocations across delivery, service, and coordination."
          icon="hero-calendar-days"
        />
        <.stat_card
          title="Confirmed"
          value={Integer.to_string(@confirmed_count)}
          description="Assignments that are staffed and ready to happen when scheduled."
          icon="hero-check-badge"
          accent="sky"
        />
        <.stat_card
          title="In Progress"
          value={Integer.to_string(@in_progress_count)}
          description="Assignments actively consuming execution capacity right now."
          icon="hero-play"
          accent="amber"
        />
        <.stat_card
          title="Onsite"
          value={Integer.to_string(@onsite_count)}
          description="Assignments that require field presence instead of fully remote execution."
          icon="hero-map-pin"
          accent="rose"
        />
      </div>

      <.section
        title="Dispatch Board"
        description="Make schedule commitments visible so work items, work orders, and billing can trust the execution calendar."
        compact
        body_class="p-0"
      >
        <div :if={@assignment_count == 0} class="p-6 sm:p-7">
          <.empty_state
            icon="hero-calendar-days"
            title="No assignments yet"
            description="Create assignments from work items or work orders when work needs a real owner and calendar slot."
          >
            <:action>
              <.button navigate={~p"/execution/assignments/new"} variant="primary">
                Create Assignment
              </.button>
            </:action>
          </.empty_state>
        </div>

        <div :if={@assignment_count > 0} class="overflow-x-auto">
          <table class="min-w-full divide-y divide-zinc-200 text-sm dark:divide-white/10">
            <thead class="bg-zinc-50 dark:bg-white/[0.03]">
              <tr>
                <th class="px-5 py-3 text-left font-medium text-zinc-500 dark:text-zinc-400">
                  Assignment
                </th>
                <th class="px-5 py-3 text-left font-medium text-zinc-500 dark:text-zinc-400">
                  Context
                </th>
                <th class="px-5 py-3 text-left font-medium text-zinc-500 dark:text-zinc-400">
                  Assignee
                </th>
                <th class="px-5 py-3 text-left font-medium text-zinc-500 dark:text-zinc-400">
                  Schedule
                </th>
                <th class="px-5 py-3 text-left font-medium text-zinc-500 dark:text-zinc-400">
                  Status
                </th>
              </tr>
            </thead>
            <tbody
              id="assignments"
              phx-update="stream"
              class="divide-y divide-zinc-200 dark:divide-white/10"
            >
              <tr :for={{dom_id, assignment} <- @streams.assignments} id={dom_id}>
                <td class="px-5 py-4 align-top">
                  <div class="space-y-1">
                    <.link
                      navigate={~p"/execution/assignments/#{assignment}"}
                      class="font-medium text-zinc-900 hover:text-emerald-600 dark:text-white"
                    >
                      {assignment.title}
                    </.link>
                    <p class="text-sm text-zinc-500 dark:text-zinc-400">
                      {format_atom(assignment.assignment_type)} · {format_atom(
                        assignment.location_mode
                      )}
                    </p>
                  </div>
                </td>
                <td class="px-5 py-4 align-top text-zinc-600 dark:text-zinc-300">
                  <div class="space-y-1">
                    <p>{(assignment.project && assignment.project.name) || "-"}</p>
                    <p class="text-xs text-zinc-400 dark:text-zinc-500">
                      {(assignment.work_item && assignment.work_item.title) ||
                        (assignment.work_order && assignment.work_order.title) ||
                        "No work item/work order"}
                    </p>
                  </div>
                </td>
                <td class="px-5 py-4 align-top text-zinc-600 dark:text-zinc-300">
                  {display_email(assignment.assigned_user)}
                </td>
                <td class="px-5 py-4 align-top text-zinc-600 dark:text-zinc-300">
                  <div class="space-y-1">
                    <p>{format_datetime(assignment.scheduled_start_at)}</p>
                    <p class="text-xs text-zinc-400 dark:text-zinc-500">
                      {format_minutes(assignment.planned_minutes)}
                    </p>
                  </div>
                </td>
                <td class="px-5 py-4 align-top">
                  <.status_badge status={assignment.status_variant}>
                    {format_atom(assignment.status)}
                  </.status_badge>
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </.section>
    </.page>
    """
  end

  defp load_assignments(actor) do
    user_loads = if actor, do: [assigned_user: []], else: []

    case Execution.list_assignments(
           actor: actor,
           query: [sort: [scheduled_start_at: :asc, inserted_at: :asc]],
           load: [:status_variant, project: [], work_item: [], work_order: []] ++ user_loads
         ) do
      {:ok, assignments} -> assignments
      {:error, error} -> raise "failed to load assignments: #{inspect(error)}"
    end
  end
end
