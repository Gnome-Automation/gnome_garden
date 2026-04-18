defmodule GnomeGardenWeb.CRM.TaskLive.Show do
  use GnomeGardenWeb, :live_view

  import GnomeGardenWeb.CRM.Helpers

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
    <.page class="pb-8">
      <.page_header eyebrow="CRM">
        {@task.title}
        <:subtitle>
          <.status_badge status={task_status(@task.status)}>
            {format_atom(@task.status)}
          </.status_badge>
        </:subtitle>
        <:actions>
          <.button navigate={~p"/crm/tasks"}>
            <.icon name="hero-arrow-left" class="size-4" /> Back
          </.button>
          <.button variant="primary" navigate={~p"/crm/tasks/#{@task}/edit"}>
            <.icon name="hero-pencil-square" class="size-4" /> Edit
          </.button>
        </:actions>
      </.page_header>

      <div class="grid grid-cols-1 gap-6 lg:grid-cols-2">
        <.section title="Task Details">
          <.properties>
            <.property name="Type">{format_atom(@task.task_type)}</.property>
            <.property name="Priority">
              <.status_badge status={task_priority(@task.priority)}>
                {format_atom(@task.priority)}
              </.status_badge>
            </.property>
            <.property name="Status">
              <.status_badge status={task_status(@task.status)}>
                {format_atom(@task.status)}
              </.status_badge>
            </.property>
            <.property name="Due">
              <span class={
                if overdue?(@task.due_at, @task.status),
                  do: "font-semibold text-rose-600 dark:text-rose-400"
              }>
                {format_datetime(@task.due_at)}
              </span>
            </.property>
            <.property :if={@task.completed_at} name="Completed">
              {format_datetime(@task.completed_at)}
            </.property>
          </.properties>
        </.section>

        <.section title="Related Records">
          <.properties>
            <.property name="Company">
              <.link
                :if={@task.company}
                navigate={~p"/crm/companies/#{@task.company}"}
                class="text-emerald-600 hover:text-emerald-500 dark:text-emerald-400"
              >
                {@task.company.name}
              </.link>
              <span :if={!@task.company} class="text-zinc-400">-</span>
            </.property>
            <.property name="Contact">
              <.link
                :if={@task.contact}
                navigate={~p"/crm/contacts/#{@task.contact}"}
                class="text-emerald-600 hover:text-emerald-500 dark:text-emerald-400"
              >
                {@task.contact.first_name} {@task.contact.last_name}
              </.link>
              <span :if={!@task.contact} class="text-zinc-400">-</span>
            </.property>
          </.properties>
        </.section>
      </div>

      <.section :if={@task.description} title="Description">
        <p class="whitespace-pre-wrap text-sm text-zinc-600 dark:text-zinc-400">
          {@task.description}
        </p>
      </.section>
    </.page>
    """
  end
end
