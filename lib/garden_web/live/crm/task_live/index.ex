defmodule GnomeGardenWeb.CRM.TaskLive.Index do
  use GnomeGardenWeb, :live_view

  alias GnomeGarden.Sales.Task

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, :page_title, "Tasks")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <div class="flex justify-end">
        <.button navigate={~p"/crm/tasks/new"} variant="primary">
          <.icon name="hero-plus" class="size-4" /> Add Task
        </.button>
      </div>

      <Cinder.collection
        resource={Task}
        actor={@current_user}
        search={[placeholder: "Search tasks..."]}
      >
        <:col :let={task} field="title" label="Title" sort search>
          <.link navigate={~p"/crm/tasks/#{task}"} class="font-medium hover:text-emerald-600">
            {task.title}
          </.link>
        </:col>
        <:col :let={task} field="task_type" label="Type">
          {format_type(task.task_type)}
        </:col>
        <:col :let={task} field="priority" label="Priority" sort>
          <span class={priority_badge(task.priority)}>{format_priority(task.priority)}</span>
        </:col>
        <:col :let={task} field="status" label="Status" sort>
          <span class={status_badge(task.status)}>{format_status(task.status)}</span>
        </:col>
        <:col :let={task} field="due_at" label="Due" sort>
          <span class={due_class(task.due_at, task.status)}>{format_date(task.due_at)}</span>
        </:col>
        <:col :let={task} label="">
          <.link
            navigate={~p"/crm/tasks/#{task}/edit"}
            class="inline-flex items-center justify-center rounded-md p-1.5 text-zinc-400 transition hover:bg-zinc-900/5 hover:text-zinc-600 dark:hover:bg-white/5 dark:hover:text-zinc-300"
          >
            <.icon name="hero-pencil" class="size-4" />
          </.link>
        </:col>
      </Cinder.collection>
    </div>
    """
  end

  defp priority_badge(:urgent), do: "badge badge-error badge-sm"
  defp priority_badge(:high), do: "badge badge-warning badge-sm"
  defp priority_badge(:normal), do: "badge badge-info badge-sm"
  defp priority_badge(:low), do: "badge badge-ghost badge-sm"
  defp priority_badge(_), do: "badge badge-ghost badge-sm"

  defp status_badge(:completed), do: "badge badge-success badge-sm"
  defp status_badge(:in_progress), do: "badge badge-info badge-sm"
  defp status_badge(:pending), do: "badge badge-warning badge-sm"
  defp status_badge(:cancelled), do: "badge badge-ghost badge-sm"
  defp status_badge(_), do: "badge badge-ghost badge-sm"

  defp format_type(nil), do: "-"
  defp format_type(type), do: type |> to_string() |> String.replace("_", " ")

  defp format_priority(nil), do: "normal"
  defp format_priority(p), do: to_string(p)

  defp format_status(nil), do: "pending"
  defp format_status(status), do: status |> to_string() |> String.replace("_", " ")

  defp format_date(nil), do: "-"
  defp format_date(datetime), do: Calendar.strftime(datetime, "%b %d, %Y")

  defp due_class(nil, _status), do: ""
  defp due_class(_due_at, :completed), do: ""
  defp due_class(_due_at, :cancelled), do: ""
  defp due_class(due_at, _status) do
    if DateTime.compare(due_at, DateTime.utc_now()) == :lt do
      "text-error font-semibold"
    else
      ""
    end
  end
end
