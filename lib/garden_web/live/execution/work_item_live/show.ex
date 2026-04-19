defmodule GnomeGardenWeb.Execution.WorkItemLive.Show do
  use GnomeGardenWeb, :live_view

  import GnomeGardenWeb.Execution.Helpers

  alias GnomeGarden.Execution

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    actor = socket.assigns.current_user
    work_item = load_work_item!(id, actor)

    {:ok,
     socket
     |> assign(:page_title, work_item.title)
     |> assign(:work_item, work_item)
     |> assign(:work_item_assignments, load_work_item_assignments!(work_item.id, actor))}
  end

  @impl true
  def handle_event("transition", %{"action" => action}, socket) do
    work_item = socket.assigns.work_item

    case transition_work_item(
           work_item,
           String.to_existing_atom(action),
           socket.assigns.current_user
         ) do
      {:ok, updated_work_item} ->
        work_item = load_work_item!(updated_work_item.id, socket.assigns.current_user)

        {:noreply,
         socket
         |> assign(:work_item, work_item)
         |> assign(
           :work_item_assignments,
           load_work_item_assignments!(work_item.id, socket.assigns.current_user)
         )
         |> put_flash(:info, "Work item updated")}

      {:error, error} ->
        {:noreply, put_flash(socket, :error, "Could not update work item: #{inspect(error)}")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.page class="pb-8">
      <.page_header eyebrow="Execution">
        {@work_item.title}
        <:subtitle>
          <span class="inline-flex items-center gap-2">
            <.status_badge status={@work_item.status_variant}>
              {format_atom(@work_item.status)}
            </.status_badge>
            <span class="text-zinc-400 dark:text-zinc-500">/</span>
            <span>{@work_item.code || "No work item code"}</span>
          </span>
        </:subtitle>
        <:actions>
          <.button navigate={~p"/execution/work-items"}>
            <.icon name="hero-arrow-left" class="size-4" /> Back
          </.button>
          <.button
            :if={@work_item.project}
            navigate={
              ~p"/execution/work-items/new?project_id=#{@work_item.project.id}&parent_work_item_id=#{@work_item.id}"
            }
          >
            <.icon name="hero-plus-circle" class="size-4" /> New Child
          </.button>
          <.button
            :if={@work_item.project}
            navigate={~p"/execution/assignments/new?#{assignment_params(@work_item)}"}
          >
            <.icon name="hero-calendar-days" class="size-4" /> New Assignment
          </.button>
          <.button
            :if={@work_item.project}
            navigate={~p"/execution/projects/#{@work_item.project}"}
          >
            <.icon name="hero-wrench-screwdriver" class="size-4" /> Project
          </.button>
          <.button navigate={~p"/execution/work-items/#{@work_item}/edit"}>
            <.icon name="hero-pencil-square" class="size-4" /> Edit
          </.button>
        </:actions>
      </.page_header>

      <.section
        title="Work Item Actions"
        description="Move planning units through explicit readiness and completion states instead of editing status by hand."
      >
        <div class="flex flex-wrap gap-3">
          <.button
            :for={action <- work_item_actions(@work_item)}
            phx-click="transition"
            phx-value-action={action.action}
            variant={action.variant}
          >
            <.icon name={action.icon} class="size-4" /> {action.label}
          </.button>
        </div>
      </.section>

      <div class="grid gap-6 lg:grid-cols-2">
        <.section title="Planning Snapshot">
          <div class="grid gap-5 sm:grid-cols-2">
            <.property_item label="Kind" value={format_atom(@work_item.kind)} />
            <.property_item label="Discipline" value={format_atom(@work_item.discipline)} />
            <.property_item label="Priority" value={format_atom(@work_item.priority)} />
            <.property_item label="Owner" value={display_email(@work_item.owner_user)} />
            <.property_item label="Estimate" value={format_minutes(@work_item.estimate_minutes)} />
            <.property_item label="Due On" value={format_date(@work_item.due_on)} />
            <.property_item label="Completed At" value={format_datetime(@work_item.completed_at)} />
            <.property_item label="Sort Order" value={Integer.to_string(@work_item.sort_order)} />
          </div>
        </.section>

        <.section title="Execution Context">
          <div class="grid gap-5 sm:grid-cols-2">
            <.property_item
              label="Project"
              value={(@work_item.project && @work_item.project.name) || "-"}
            />
            <.property_item
              label="Parent"
              value={(@work_item.parent_work_item && @work_item.parent_work_item.title) || "-"}
            />
            <.property_item
              label="Child Work Items"
              value={Integer.to_string(@work_item.child_work_item_count || 0)}
            />
            <.property_item
              label="Assignments"
              value={Integer.to_string(@work_item.assignment_count || 0)}
            />
            <.property_item
              label="Material Usage"
              value={Integer.to_string(@work_item.material_usage_count || 0)}
            />
          </div>
        </.section>
      </div>

      <.section :if={@work_item.description} title="Description">
        <p class="whitespace-pre-wrap text-sm leading-6 text-zinc-600 dark:text-zinc-300">
          {@work_item.description}
        </p>
      </.section>

      <.section
        title="Assignments"
        description="Scheduling should happen from the planning context where the work item actually lives."
      >
        <div :if={Enum.empty?(@work_item_assignments)} class="space-y-4">
          <.empty_state
            icon="hero-calendar-days"
            title="No assignments yet"
            description="Create an assignment when this work item is ready to claim real delivery capacity."
          >
            <:action>
              <.button
                :if={@work_item.project}
                navigate={~p"/execution/assignments/new?#{assignment_params(@work_item)}"}
              >
                Create Assignment
              </.button>
            </:action>
          </.empty_state>
        </div>

        <div :if={!Enum.empty?(@work_item_assignments)} class="space-y-3">
          <.link
            :for={assignment <- @work_item_assignments}
            navigate={~p"/execution/assignments/#{assignment}"}
            class="flex items-center justify-between rounded-2xl border border-zinc-200 bg-zinc-50/70 px-4 py-4 transition hover:border-emerald-300 hover:bg-white dark:border-white/10 dark:bg-white/[0.03] dark:hover:border-emerald-400/40"
          >
            <div class="space-y-1">
              <p class="font-medium text-zinc-900 dark:text-white">{assignment.title}</p>
              <p class="text-sm text-zinc-500 dark:text-zinc-400">
                {display_email(assignment.assigned_user, "Unassigned")} · {format_datetime(
                  assignment.scheduled_start_at
                )}
              </p>
            </div>
            <.status_badge status={assignment.status_variant}>
              {format_atom(assignment.status)}
            </.status_badge>
          </.link>
        </div>
      </.section>

      <.section
        title="Child Work Items"
        description="Break large execution work into nested items without losing the parent planning context."
      >
        <div :if={Enum.empty?(@work_item.child_work_items || [])}>
          <.empty_state
            icon="hero-queue-list"
            title="No child work items yet"
            description="Add child work items when this item needs explicit sub-planning or handoffs."
          >
            <:action>
              <.button
                :if={@work_item.project}
                navigate={
                  ~p"/execution/work-items/new?project_id=#{@work_item.project.id}&parent_work_item_id=#{@work_item.id}"
                }
              >
                Create Child Work Item
              </.button>
            </:action>
          </.empty_state>
        </div>

        <div :if={!Enum.empty?(@work_item.child_work_items || [])} class="space-y-3">
          <.link
            :for={child_work_item <- @work_item.child_work_items}
            navigate={~p"/execution/work-items/#{child_work_item}"}
            class="flex items-center justify-between rounded-2xl border border-zinc-200 bg-zinc-50/70 px-4 py-4 transition hover:border-emerald-300 hover:bg-white dark:border-white/10 dark:bg-white/[0.03] dark:hover:border-emerald-400/40"
          >
            <div class="space-y-1">
              <p class="font-medium text-zinc-900 dark:text-white">{child_work_item.title}</p>
              <p class="text-sm text-zinc-500 dark:text-zinc-400">
                {format_atom(child_work_item.kind)} · {format_minutes(
                  child_work_item.estimate_minutes
                )}
              </p>
            </div>
            <div class="space-y-2 text-right">
              <.status_badge status={child_work_item.status_variant}>
                {format_atom(child_work_item.status)}
              </.status_badge>
              <.status_badge status={child_work_item.priority_variant}>
                {format_atom(child_work_item.priority)}
              </.status_badge>
            </div>
          </.link>
        </div>
      </.section>
    </.page>
    """
  end

  attr :label, :string, required: true
  attr :value, :string, required: true

  defp property_item(assigns) do
    ~H"""
    <div class="space-y-1">
      <p class="text-xs font-semibold uppercase tracking-[0.2em] text-zinc-400 dark:text-zinc-500">
        {@label}
      </p>
      <p class="text-sm font-medium text-zinc-900 dark:text-white">{@value}</p>
    </div>
    """
  end

  defp load_work_item!(id, actor) do
    user_loads =
      if actor do
        [owner_user: []]
      else
        []
      end

    case Execution.get_work_item(
           id,
           actor: actor,
           load:
             [
               :status_variant,
               :priority_variant,
               :child_work_item_count,
               :assignment_count,
               :material_usage_count,
               project: [],
               parent_work_item: [],
               child_work_items: [:status_variant, :priority_variant]
             ] ++ user_loads
         ) do
      {:ok, work_item} -> work_item
      {:error, error} -> raise "failed to load work item #{id}: #{inspect(error)}"
    end
  end

  defp load_work_item_assignments!(work_item_id, actor) do
    user_loads = if actor, do: [assigned_user: []], else: []

    case Execution.list_assignments_for_work_item(
           work_item_id,
           actor: actor,
           load: [:status_variant] ++ user_loads
         ) do
      {:ok, assignments} ->
        assignments

      {:error, error} ->
        raise "failed to load assignments for work item #{work_item_id}: #{inspect(error)}"
    end
  end

  defp assignment_params(work_item) do
    %{}
    |> maybe_put(:organization_id, work_item.project && work_item.project.organization_id)
    |> maybe_put(:project_id, work_item.project && work_item.project.id)
    |> Map.put(:work_item_id, work_item.id)
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp work_item_actions(%{status: :backlog}) do
    [
      %{action: "ready", label: "Ready", icon: "hero-check-badge", variant: nil},
      %{action: "start", label: "Start", icon: "hero-play", variant: "primary"},
      %{action: "cancel", label: "Cancel", icon: "hero-x-circle", variant: nil}
    ]
  end

  defp work_item_actions(%{status: :ready}) do
    [
      %{action: "start", label: "Start", icon: "hero-play", variant: "primary"},
      %{action: "block", label: "Block", icon: "hero-no-symbol", variant: nil},
      %{action: "complete", label: "Complete", icon: "hero-check", variant: nil},
      %{action: "cancel", label: "Cancel", icon: "hero-x-circle", variant: nil}
    ]
  end

  defp work_item_actions(%{status: :in_progress}) do
    [
      %{action: "review", label: "Review", icon: "hero-eye", variant: nil},
      %{action: "block", label: "Block", icon: "hero-no-symbol", variant: nil},
      %{action: "complete", label: "Complete", icon: "hero-check", variant: "primary"}
    ]
  end

  defp work_item_actions(%{status: :blocked}) do
    [
      %{action: "start", label: "Resume", icon: "hero-play", variant: "primary"},
      %{action: "cancel", label: "Cancel", icon: "hero-x-circle", variant: nil}
    ]
  end

  defp work_item_actions(%{status: :review}) do
    [
      %{action: "complete", label: "Complete", icon: "hero-check", variant: "primary"},
      %{action: "block", label: "Block", icon: "hero-no-symbol", variant: nil}
    ]
  end

  defp work_item_actions(%{status: :done}) do
    [
      %{action: "reopen", label: "Reopen", icon: "hero-arrow-path", variant: "primary"}
    ]
  end

  defp work_item_actions(%{status: :cancelled}) do
    [
      %{action: "reopen", label: "Reopen", icon: "hero-arrow-path", variant: "primary"}
    ]
  end

  defp work_item_actions(_work_item), do: []

  defp transition_work_item(work_item, :ready, actor),
    do: Execution.ready_work_item(work_item, actor: actor)

  defp transition_work_item(work_item, :start, actor),
    do: Execution.start_work_item(work_item, actor: actor)

  defp transition_work_item(work_item, :block, actor),
    do: Execution.block_work_item(work_item, actor: actor)

  defp transition_work_item(work_item, :review, actor),
    do: Execution.review_work_item(work_item, actor: actor)

  defp transition_work_item(work_item, :complete, actor),
    do: Execution.complete_work_item(work_item, actor: actor)

  defp transition_work_item(work_item, :cancel, actor),
    do: Execution.cancel_work_item(work_item, actor: actor)

  defp transition_work_item(work_item, :reopen, actor),
    do: Execution.reopen_work_item(work_item, actor: actor)
end
