defmodule GnomeGardenWeb.CRM.TasksLive do
  use GnomeGardenWeb, :live_view

  alias GnomeGarden.Sales.Task

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, :page_title, "Tasks")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-4">
      <div class="flex justify-between items-center">
        <h1 class="text-2xl font-bold">Tasks</h1>
        <div class="flex gap-2">
          <a href="/admin/sales/task?action=create" class="btn btn-sm btn-primary">
            <.icon name="hero-plus" class="size-4" /> Add Task
          </a>
        </div>
      </div>

      <Cinder.collection
        resource={Task}
        actor={@current_user}
        search={[placeholder: "Search tasks..."]}
      >
        <:col :let={task} field="title" label="Title" filter sort search>
          <span class="font-medium">{task.title}</span>
        </:col>
        <:col :let={task} field="task_type" label="Type" filter>
          {format_type(task.task_type)}
        </:col>
        <:col :let={task} field="priority" label="Priority" filter sort>
          <span class={priority_badge(task.priority)}>{format_priority(task.priority)}</span>
        </:col>
        <:col :let={task} field="status" label="Status" filter sort>
          <span class={status_badge(task.status)}>{format_status(task.status)}</span>
        </:col>
        <:col :let={task} field="due_at" label="Due" sort>
          <span class={due_class(task.due_at)}>{format_date(task.due_at)}</span>
        </:col>
        <:col :let={task} label="">
          <a href={"/admin/sales/task/#{task.id}"} class="btn btn-xs btn-ghost">
            <.icon name="hero-pencil" class="size-4" />
          </a>
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

  defp due_class(nil), do: ""
  defp due_class(due_at) do
    if DateTime.compare(due_at, DateTime.utc_now()) == :lt do
      "text-error font-semibold"
    else
      ""
    end
  end
end
