defmodule GnomeGardenWeb.CRM.TaskLive.Index do
  use GnomeGardenWeb, :live_view

  import GnomeGardenWeb.CRM.Helpers

  alias GnomeGarden.Sales.Task

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, page_title: "Tasks")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.page class="pb-8">
      <.page_header eyebrow="CRM">
        Tasks
        <:subtitle>
          Manage calls, follow-ups, and sales execution work in one queue.
        </:subtitle>
        <:actions>
          <.button navigate={~p"/crm/tasks/new"} variant="primary">
            <.icon name="hero-plus" class="size-4" /> Add Task
          </.button>
        </:actions>
      </.page_header>

      <.section
        title="Task Queue"
        description="Review pending work by priority, status, and due date."
        compact
        body_class="p-0"
      >
        <Cinder.collection
          id="tasks"
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
            {format_atom(task.task_type)}
          </:col>
          <:col :let={task} field="priority" label="Priority" sort>
            <.status_badge status={task_priority(task.priority)}>
              {format_atom(task.priority)}
            </.status_badge>
          </:col>
          <:col :let={task} field="status" label="Status" sort>
            <.status_badge status={task_status(task.status)}>
              {format_atom(task.status)}
            </.status_badge>
          </:col>
          <:col :let={task} field="due_at" label="Due" sort>
            <span class={
              if overdue?(task.due_at, task.status),
                do: "text-rose-600 font-semibold dark:text-rose-400"
            }>
              {format_date(task.due_at)}
            </span>
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
      </.section>
    </.page>
    """
  end
end
