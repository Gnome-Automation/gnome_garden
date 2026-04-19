defmodule GnomeGardenWeb.Execution.WorkItemLive.Index do
  use GnomeGardenWeb, :live_view

  import GnomeGardenWeb.Execution.Helpers

  alias GnomeGarden.Execution

  @impl true
  def mount(_params, _session, socket) do
    work_items = load_work_items(socket.assigns.current_user)

    {:ok,
     socket
     |> assign(:page_title, "Work Items")
     |> assign(:work_item_count, length(work_items))
     |> assign(
       :open_count,
       Enum.count(work_items, &(&1.status in [:backlog, :ready, :in_progress, :blocked, :review]))
     )
     |> assign(:blocked_count, Enum.count(work_items, &(&1.status == :blocked)))
     |> assign(:due_soon_count, Enum.count(work_items, &due_soon?/1))
     |> stream(:work_items, work_items)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.page class="pb-8">
      <.page_header eyebrow="Execution">
        Work Items
        <:subtitle>
          Plan delivery through durable execution units instead of hiding actual work under project headers.
        </:subtitle>
        <:actions>
          <.button navigate={~p"/execution/projects"}>
            <.icon name="hero-wrench-screwdriver" class="size-4" /> Projects
          </.button>
          <.button navigate={~p"/execution/work-items/new"} variant="primary">
            <.icon name="hero-plus" class="size-4" /> New Work Item
          </.button>
        </:actions>
      </.page_header>

      <div class="grid gap-4 md:grid-cols-4">
        <.stat_card
          title="Work Items"
          value={Integer.to_string(@work_item_count)}
          description="Phases, tasks, issues, milestones, and deliverables attached to project execution."
          icon="hero-queue-list"
        />
        <.stat_card
          title="Open"
          value={Integer.to_string(@open_count)}
          description="Items still flowing through backlog, ready, active, blocked, or review states."
          icon="hero-play"
          accent="sky"
        />
        <.stat_card
          title="Blocked"
          value={Integer.to_string(@blocked_count)}
          description="Execution work that needs attention before the project can move cleanly."
          icon="hero-no-symbol"
          accent="amber"
        />
        <.stat_card
          title="Due Soon"
          value={Integer.to_string(@due_soon_count)}
          description="Open items due within the next seven days and worth triaging now."
          icon="hero-calendar-days"
          accent="rose"
        />
      </div>

      <.section
        title="Execution Board"
        description="Track actual planning units with project, ownership, and priority visible in one place."
        compact
        body_class="p-0"
      >
        <div :if={@work_item_count == 0} class="p-6 sm:p-7">
          <.empty_state
            icon="hero-queue-list"
            title="No work items yet"
            description="Add work items directly or create them from a project to make delivery planning explicit."
          >
            <:action>
              <.button navigate={~p"/execution/work-items/new"} variant="primary">
                Create Work Item
              </.button>
            </:action>
          </.empty_state>
        </div>

        <div :if={@work_item_count > 0} class="overflow-x-auto">
          <table class="min-w-full divide-y divide-zinc-200 text-sm dark:divide-white/10">
            <thead class="bg-zinc-50 dark:bg-white/[0.03]">
              <tr>
                <th class="px-5 py-3 text-left font-medium text-zinc-500 dark:text-zinc-400">
                  Work Item
                </th>
                <th class="px-5 py-3 text-left font-medium text-zinc-500 dark:text-zinc-400">
                  Project
                </th>
                <th class="px-5 py-3 text-left font-medium text-zinc-500 dark:text-zinc-400">
                  Shape
                </th>
                <th class="px-5 py-3 text-left font-medium text-zinc-500 dark:text-zinc-400">
                  Scheduling
                </th>
                <th class="px-5 py-3 text-left font-medium text-zinc-500 dark:text-zinc-400">
                  Status
                </th>
              </tr>
            </thead>
            <tbody
              id="work-items"
              phx-update="stream"
              class="divide-y divide-zinc-200 dark:divide-white/10"
            >
              <tr :for={{dom_id, work_item} <- @streams.work_items} id={dom_id}>
                <td class="px-5 py-4 align-top">
                  <div class="space-y-1">
                    <.link
                      navigate={~p"/execution/work-items/#{work_item}"}
                      class="font-medium text-zinc-900 hover:text-emerald-600 dark:text-white"
                    >
                      {work_item.title}
                    </.link>
                    <p class="text-sm text-zinc-500 dark:text-zinc-400">
                      {work_item.code || "No code"} · {display_email(
                        work_item.owner_user,
                        "Unassigned"
                      )}
                    </p>
                  </div>
                </td>
                <td class="px-5 py-4 align-top text-zinc-600 dark:text-zinc-300">
                  {(work_item.project && work_item.project.name) || "-"}
                </td>
                <td class="px-5 py-4 align-top text-zinc-600 dark:text-zinc-300">
                  <div class="space-y-2">
                    <.tag color={:zinc}>{format_atom(work_item.kind)}</.tag>
                    <.tag color={:emerald}>{format_atom(work_item.discipline)}</.tag>
                    <p class="text-xs text-zinc-400 dark:text-zinc-500">
                      {work_item.child_work_item_count || 0} children · {work_item.assignment_count ||
                        0} assignments
                    </p>
                  </div>
                </td>
                <td class="px-5 py-4 align-top text-zinc-600 dark:text-zinc-300">
                  <div class="space-y-1">
                    <p>Due {format_date(work_item.due_on)}</p>
                    <p class="text-xs text-zinc-400 dark:text-zinc-500">
                      {format_minutes(work_item.estimate_minutes)}
                    </p>
                  </div>
                </td>
                <td class="px-5 py-4 align-top">
                  <div class="space-y-2">
                    <.status_badge status={work_item.status_variant}>
                      {format_atom(work_item.status)}
                    </.status_badge>
                    <.status_badge status={work_item.priority_variant}>
                      {format_atom(work_item.priority)}
                    </.status_badge>
                  </div>
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </.section>
    </.page>
    """
  end

  defp load_work_items(actor) do
    user_loads = if actor, do: [owner_user: []], else: []

    case Execution.list_work_items(
           actor: actor,
           query: [sort: [due_on: :asc, sort_order: :asc, inserted_at: :asc]],
           load:
             [
               :status_variant,
               :priority_variant,
               :child_work_item_count,
               :assignment_count,
               project: []
             ] ++ user_loads
         ) do
      {:ok, work_items} -> work_items
      {:error, error} -> raise "failed to load work items: #{inspect(error)}"
    end
  end

  defp due_soon?(%{status: status, due_on: %Date{} = due_on})
       when status in [:backlog, :ready, :in_progress, :blocked, :review] do
    diff = Date.diff(due_on, Date.utc_today())
    diff >= 0 and diff <= 7
  end

  defp due_soon?(_work_item), do: false
end
