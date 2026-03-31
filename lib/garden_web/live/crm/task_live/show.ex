defmodule GnomeGardenWeb.CRM.TaskLive.Show do
  use GnomeGardenWeb, :live_view

  alias GnomeGarden.Sales

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    task = Sales.get_task!(id, actor: socket.assigns.current_user, load: [:company, :contact])

    {:ok,
     socket
     |> assign(:page_title, task.title)
     |> assign(:task, task)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.header>
      {@task.title}
      <:actions>
        <.button navigate={~p"/crm/tasks"}>
          <.icon name="hero-arrow-left" class="size-4" /> Back
        </.button>
        <.button variant="primary" navigate={~p"/crm/tasks/#{@task}/edit"}>
          <.icon name="hero-pencil-square" class="size-4" /> Edit
        </.button>
      </:actions>
    </.header>

    <div class="mt-6 grid grid-cols-1 gap-8 lg:grid-cols-2">
      <div>
        <h2 class="text-base font-semibold mb-4">Task Details</h2>
        <.list>
          <:item title="Type">{format_atom(@task.task_type)}</:item>
          <:item title="Priority">
            <span class={priority_badge(@task.priority)}>{format_atom(@task.priority)}</span>
          </:item>
          <:item title="Status">
            <span class={status_badge(@task.status)}>{format_atom(@task.status)}</span>
          </:item>
          <:item title="Due">
            <span class={due_class(@task.due_at, @task.status)}>
              {format_datetime(@task.due_at)}
            </span>
          </:item>
          <:item :if={@task.completed_at} title="Completed">
            {format_datetime(@task.completed_at)}
          </:item>
        </.list>
      </div>

      <div>
        <h2 class="text-base font-semibold mb-4">Related Records</h2>
        <.list>
          <:item title="Company">
            <.link
              :if={@task.company}
              navigate={~p"/crm/companies/#{@task.company}"}
              class="text-emerald-600 hover:text-emerald-500 dark:text-emerald-400"
            >
              {@task.company.name}
            </.link>
            <span :if={!@task.company} class="text-zinc-400">-</span>
          </:item>
          <:item title="Contact">
            <.link
              :if={@task.contact}
              navigate={~p"/crm/contacts/#{@task.contact}"}
              class="text-emerald-600 hover:text-emerald-500 dark:text-emerald-400"
            >
              {@task.contact.first_name} {@task.contact.last_name}
            </.link>
            <span :if={!@task.contact} class="text-zinc-400">-</span>
          </:item>
        </.list>
      </div>
    </div>

    <div :if={@task.description} class="mt-8">
      <h2 class="text-base font-semibold mb-2">Description</h2>
      <p class="text-sm text-zinc-600 dark:text-zinc-400 whitespace-pre-wrap">
        {@task.description}
      </p>
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

  defp format_atom(nil), do: "-"
  defp format_atom(atom), do: atom |> to_string() |> String.replace("_", " ") |> String.capitalize()

  defp format_datetime(nil), do: "-"
  defp format_datetime(datetime), do: Calendar.strftime(datetime, "%b %d, %Y %H:%M")

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
