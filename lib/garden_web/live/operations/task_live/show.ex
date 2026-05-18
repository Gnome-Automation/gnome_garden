defmodule GnomeGardenWeb.Operations.TaskLive.Show do
  use GnomeGardenWeb, :live_view

  import GnomeGardenWeb.Operations.Helpers

  alias GnomeGarden.Operations
  alias GnomeGardenWeb.Operations.TaskPubSub

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    task = load_task!(id, socket.assigns.current_user)

    if connected?(socket), do: TaskPubSub.subscribe_task(task.id)

    {:ok,
     socket
     |> assign(:page_title, task.title)
     |> assign(:task, task)}
  end

  @impl true
  def handle_info(%{topic: "task:destroyed:" <> _task_id}, socket) do
    {:noreply, push_navigate(socket, to: ~p"/operations/tasks")}
  end

  def handle_info(%{topic: "task:updated:" <> _task_id}, socket) do
    {:noreply,
     assign(socket, :task, load_task!(socket.assigns.task.id, socket.assigns.current_user))}
  end

  @impl true
  def handle_event("start", _params, socket),
    do: transition_task(socket, &Operations.start_task/2)

  def handle_event("complete", _params, socket),
    do: transition_task(socket, &Operations.complete_task/2)

  def handle_event("cancel", _params, socket),
    do: transition_task(socket, &Operations.cancel_task/2)

  def handle_event("reopen", _params, socket),
    do: transition_task(socket, &Operations.reopen_task/2)

  def handle_event("block", %{"task" => %{"blocked_reason" => blocked_reason}}, socket) do
    case Operations.block_task(socket.assigns.task, %{blocked_reason: blocked_reason},
           actor: socket.assigns.current_user
         ) do
      {:ok, task} ->
        {:noreply,
         socket
         |> assign(:task, load_task!(task.id, socket.assigns.current_user))
         |> put_flash(:info, "Task blocked")}

      {:error, error} ->
        {:noreply, put_flash(socket, :error, "Could not block task: #{inspect(error)}")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.page class="pb-8">
      <.page_header eyebrow="Operations">
        {@task.title}
        <:subtitle>
          <span class="inline-flex flex-wrap items-center gap-2">
            <.status_badge status={@task.status_variant}>
              {format_atom(@task.status)}
            </.status_badge>
            <.status_badge status={@task.priority_variant}>
              {format_atom(@task.priority)}
            </.status_badge>
            <span>{format_atom(@task.origin_domain)}</span>
          </span>
        </:subtitle>
        <:actions>
          <.button navigate={~p"/operations/tasks"}>
            Back
          </.button>
          <.button navigate={~p"/operations/tasks/#{@task}/edit"}>
            Edit
          </.button>
          <.button
            :if={@task.status in [:pending, :blocked]}
            phx-click="start"
            variant="primary"
          >
            Start
          </.button>
          <.button :if={@task.status == :in_progress} phx-click="complete" variant="primary">
            Complete
          </.button>
          <.button :if={@task.status in [:completed, :cancelled]} phx-click="reopen">
            Reopen
          </.button>
        </:actions>
      </.page_header>

      <div class="grid gap-6 lg:grid-cols-[minmax(0,1fr)_24rem]">
        <div class="space-y-6">
          <.section title="Task">
            <p class="whitespace-pre-wrap text-sm leading-6 text-base-content/70">
              {@task.description || "No description captured."}
            </p>
          </.section>

          <.section :if={@task.blocked_reason} title="Blocked Reason">
            <p class="whitespace-pre-wrap text-sm leading-6 text-base-content/70">
              {@task.blocked_reason}
            </p>
          </.section>
        </div>

        <div class="space-y-6">
          <.section title="Schedule">
            <.properties>
              <.property name="Due">{format_datetime(@task.due_at)}</.property>
              <.property name="Started">{format_datetime(@task.started_at)}</.property>
              <.property name="Blocked">{format_datetime(@task.blocked_at)}</.property>
              <.property name="Completed">{format_datetime(@task.completed_at)}</.property>
            </.properties>
          </.section>

          <.section title="Origin">
            <.properties>
              <.property name="Domain">{format_atom(@task.origin_domain)}</.property>
              <.property name="Resource">{@task.origin_resource || "-"}</.property>
              <.property name="Label">{@task.origin_label || "-"}</.property>
              <.property name="Link">
                <.link
                  :if={@task.origin_url}
                  navigate={@task.origin_url}
                  class="text-emerald-600 hover:text-primary"
                >
                  Open source record
                </.link>
                <span :if={!@task.origin_url}>-</span>
              </.property>
            </.properties>
          </.section>

          <.section title="Actions">
            <div class="space-y-4">
              <.form
                :if={@task.status in [:pending, :in_progress]}
                for={%{}}
                as={:task}
                id="task-block-form"
                phx-submit="block"
                class="space-y-3"
              >
                <.input
                  name="task[blocked_reason]"
                  value=""
                  type="textarea"
                  label="Blocked Reason"
                  required
                />
                <.button type="submit">
                  Mark Blocked
                </.button>
              </.form>

              <.button
                :if={@task.status in [:pending, :in_progress, :blocked]}
                phx-click="cancel"
              >
                Cancel
              </.button>
            </div>
          </.section>
        </div>
      </div>
    </.page>
    """
  end

  defp transition_task(socket, fun) do
    case fun.(socket.assigns.task, actor: socket.assigns.current_user) do
      {:ok, task} ->
        {:noreply,
         socket
         |> assign(:task, load_task!(task.id, socket.assigns.current_user))
         |> put_flash(:info, "Task updated")}

      {:error, error} ->
        {:noreply, put_flash(socket, :error, "Could not update task: #{inspect(error)}")}
    end
  end

  defp load_task!(id, actor) do
    case Operations.get_task(id,
           actor: actor,
           load: [:status_variant, :priority_variant, :organization, :person, :pursuit, :finding]
         ) do
      {:ok, task} -> task
      {:error, error} -> raise "failed to load task #{id}: #{inspect(error)}"
    end
  end
end
