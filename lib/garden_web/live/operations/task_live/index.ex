defmodule GnomeGardenWeb.Operations.TaskLive.Index do
  use GnomeGardenWeb, :live_view

  import GnomeGardenWeb.Operations.Helpers

  alias GnomeGarden.Operations
  alias GnomeGardenWeb.Operations.TaskPubSub

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: TaskPubSub.subscribe_inbox()

    {:ok,
     socket
     |> assign(:page_title, "Tasks")
     |> assign_tasks()}
  end

  @impl true
  def handle_info(%{topic: "task:" <> _event}, socket) do
    {:noreply, assign_tasks(socket)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.page class="pb-8">
      <.page_header eyebrow="Operations">
        Tasks
        <:subtitle>
          Operator work across acquisition, commercial, agents, finance, execution, and manual intake.
        </:subtitle>
        <:actions>
          <.button navigate={~p"/operations/tasks/new"} variant="primary">
            New Task
          </.button>
        </:actions>
      </.page_header>

      <div class="grid gap-2 sm:grid-cols-4">
        <.stat_card
          title="Open"
          value={Integer.to_string(@counts.open)}
          description="Pending, active, and blocked tasks."
          icon="hero-inbox-stack"
        />
        <.stat_card
          title="Overdue"
          value={Integer.to_string(@counts.overdue)}
          description="Open tasks past their due time."
          icon="hero-exclamation-triangle"
          accent="rose"
        />
        <.stat_card
          title="Today"
          value={Integer.to_string(@counts.today)}
          description="Open tasks due today."
          icon="hero-calendar-days"
          accent="amber"
        />
        <.stat_card
          title="Blocked"
          value={Integer.to_string(@counts.blocked)}
          description="Tasks waiting on an explicit unblock step."
          icon="hero-no-symbol"
          accent="sky"
        />
      </div>

      <.section
        title="Task Inbox"
        description="Work from overdue and blocked items first, then today and upcoming."
        compact
      >
        <div :if={@tasks == []} class="p-4">
          <.empty_state
            icon="hero-check-circle"
            title="No open tasks"
            description="New operator work from review decisions, agent runs, and manual intake will appear here."
          >
            <:action>
              <.button navigate={~p"/operations/tasks/new"} variant="primary">
                Create Task
              </.button>
            </:action>
          </.empty_state>
        </div>

        <div :if={@tasks != []} class="divide-y divide-zinc-200 dark:divide-white/10">
          <.link
            :for={task <- @tasks}
            navigate={~p"/operations/tasks/#{task}"}
            class="block px-3 py-3 transition hover:bg-zinc-50 dark:hover:bg-white/[0.03] sm:px-4 lg:px-5"
          >
            <div class="flex flex-col gap-3 md:flex-row md:items-start md:justify-between">
              <div class="min-w-0 space-y-2">
                <div class="flex flex-wrap items-center gap-2">
                  <.status_badge status={task.status_variant}>
                    {format_atom(task.status)}
                  </.status_badge>
                  <.status_badge status={task.priority_variant}>
                    {format_atom(task.priority)}
                  </.status_badge>
                  <.tag color={origin_color(task.origin_domain)}>
                    {format_atom(task.origin_domain)}
                  </.tag>
                  <span class="text-xs text-base-content/40">
                    {format_atom(task.task_type)}
                  </span>
                </div>
                <div class="space-y-1">
                  <p class="font-medium text-base-content">{task.title}</p>
                  <p
                    :if={task.description}
                    class="line-clamp-2 text-sm leading-5 text-base-content/60"
                  >
                    {task.description}
                  </p>
                </div>
              </div>

              <div class="shrink-0 text-left text-xs text-base-content/50 md:text-right">
                <p>Due {format_datetime(task.due_at)}</p>
                <p>{task.origin_label || task.origin_resource || "Manual task"}</p>
              </div>
            </div>
          </.link>
        </div>
      </.section>
    </.page>
    """
  end

  defp assign_tasks(%{assigns: %{current_user: actor}} = socket) do
    tasks = list_task_inbox(actor)

    assign(socket,
      tasks: tasks,
      counts: %{
        open: length(tasks),
        overdue: task_count(&Operations.list_overdue_tasks/1, actor),
        today: task_count(&Operations.list_due_today_tasks/1, actor),
        blocked: task_count(&Operations.list_blocked_tasks/1, actor)
      }
    )
  end

  defp list_task_inbox(actor) do
    case Operations.list_task_inbox(actor: actor) do
      {:ok, tasks} -> tasks
      {:error, _error} -> []
    end
  end

  defp task_count(fun, actor) do
    case fun.(actor: actor, query: [select: [:id]]) do
      {:ok, tasks} -> length(tasks)
      {:error, _error} -> 0
    end
  end

  defp origin_color(:acquisition), do: :emerald
  defp origin_color(:commercial), do: :sky
  defp origin_color(:agents), do: :amber
  defp origin_color(:finance), do: :rose
  defp origin_color(_origin), do: :zinc
end
