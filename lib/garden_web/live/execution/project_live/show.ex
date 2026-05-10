defmodule GnomeGardenWeb.Execution.ProjectLive.Show do
  use GnomeGardenWeb, :live_view

  import GnomeGardenWeb.Execution.Helpers

  alias GnomeGarden.Execution

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    actor = socket.assigns.current_user
    project = load_project!(id, actor)

    {:ok,
     socket
     |> assign(:page_title, project.name)
     |> assign(:project, project)
     |> assign(:project_work_items, load_project_work_items!(project.id, actor))}
  end

  @impl true
  def handle_event("transition", %{"action" => action}, socket) do
    project = socket.assigns.project

    case transition_project(project, String.to_existing_atom(action), socket.assigns.current_user) do
      {:ok, updated_project} ->
        project = load_project!(updated_project.id, socket.assigns.current_user)

        {:noreply,
         socket
         |> assign(:project, project)
         |> assign(
           :project_work_items,
           load_project_work_items!(project.id, socket.assigns.current_user)
         )
         |> put_flash(:info, "Project updated")}

      {:error, error} ->
        {:noreply, put_flash(socket, :error, "Could not update project: #{inspect(error)}")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.page class="pb-8">
      <.page_header eyebrow="Execution">
        {@project.name}
        <:subtitle>
          <span class="inline-flex items-center gap-2">
            <.status_badge status={@project.status_variant}>
              {format_atom(@project.status)}
            </.status_badge>
            <span class="text-base-content/40">/</span>
            <span>{@project.code || "No project code"}</span>
          </span>
        </:subtitle>
        <:actions>
          <.button navigate={~p"/execution/projects"}>
            Back
          </.button>
          <.button navigate={~p"/finance/time-entries/new?#{time_entry_params(@project)}"}>
            New Time Entry
          </.button>
          <.button navigate={~p"/finance/expenses/new?#{expense_params(@project)}"}>
            New Expense
          </.button>
          <.button navigate={~p"/execution/work-items/new?project_id=#{@project.id}"}>
            New Work Item
          </.button>
          <.button navigate={~p"/commercial/change-orders/new?project_id=#{@project.id}"}>
            New Change Order
          </.button>
          <.button navigate={~p"/execution/projects/#{@project}/edit"}>
            Edit
          </.button>
        </:actions>
      </.page_header>

      <.section
        title="Project Actions"
        description="Advance delivery through explicit state transitions so work planning, field service, and billing stay aligned."
      >
        <div class="flex flex-wrap gap-3">
          <.button
            :for={action <- project_actions(@project)}
            phx-click="transition"
            phx-value-action={action.action}
            variant={action.variant}
          >
            <.icon name={action.icon} class="size-4" /> {action.label}
          </.button>
        </div>
      </.section>

      <div class="grid gap-6 lg:grid-cols-2">
        <.section title="Delivery Snapshot">
          <div class="grid gap-5 sm:grid-cols-2">
            <.property_item label="Project Type" value={format_atom(@project.project_type)} />
            <.property_item label="Delivery Mode" value={format_atom(@project.delivery_mode)} />
            <.property_item label="Priority" value={format_atom(@project.priority)} />
            <.property_item label="Start On" value={format_date(@project.start_on)} />
            <.property_item label="Target End" value={format_date(@project.target_end_on)} />
            <.property_item label="Actual End" value={format_date(@project.actual_end_on)} />
          </div>
        </.section>

        <.section title="Commercial Context">
          <div class="grid gap-5 sm:grid-cols-2">
            <.property_item
              label="Organization"
              value={(@project.organization && @project.organization.name) || "-"}
            />
            <.property_item
              label="Agreement"
              value={(@project.agreement && @project.agreement.name) || "-"}
            />
            <.property_item label="Budget Hours" value={decimal_or_dash(@project.budget_hours)} />
            <.property_item label="Budget Amount" value={format_amount(@project.budget_amount)} />
            <.property_item
              label="Work Items"
              value={Integer.to_string(@project.work_item_count || 0)}
            />
            <.property_item
              label="Work Orders"
              value={Integer.to_string(@project.work_order_count || 0)}
            />
          </div>
        </.section>
      </div>

      <.section title="Execution Counts">
        <div class="grid gap-5 sm:grid-cols-4">
          <.property_item
            label="Assignments"
            value={Integer.to_string(@project.assignment_count || 0)}
          />
          <.property_item label="Work Items" value={Integer.to_string(@project.work_item_count || 0)} />
          <.property_item
            label="Work Orders"
            value={Integer.to_string(@project.work_order_count || 0)}
          />
          <.property_item
            label="Material Usage"
            value={Integer.to_string(@project.material_usage_count || 0)}
          />
        </div>
      </.section>

      <.section
        title="Work Items"
        description="Keep the actual project plan visible here instead of forcing operators to bounce between separate execution screens."
      >
        <div :if={Enum.empty?(@project_work_items)} class="space-y-4">
          <.empty_state
            icon="hero-queue-list"
            title="No work items yet"
            description="Create work items now so project execution has explicit phases, tasks, and deliverables to run through."
          >
            <:action>
              <.button navigate={~p"/execution/work-items/new?project_id=#{@project.id}"}>
                Create Work Item
              </.button>
            </:action>
          </.empty_state>
        </div>

        <div :if={!Enum.empty?(@project_work_items)} class="space-y-3">
          <.link
            :for={work_item <- @project_work_items}
            navigate={~p"/execution/work-items/#{work_item}"}
            class="flex items-center justify-between rounded-2xl border border-zinc-200 bg-zinc-50/70 px-4 py-4 transition hover:border-emerald-300 hover:bg-white dark:border-white/10 dark:bg-white/[0.03] dark:hover:border-emerald-400/40"
          >
            <div class="space-y-1">
              <p class="font-medium text-base-content">{work_item.title}</p>
              <p class="text-sm text-base-content/50">
                {format_atom(work_item.kind)} · {display_team_member(
                  work_item.owner_team_member,
                  "Unassigned"
                )}
              </p>
            </div>
            <div class="space-y-2 text-right">
              <.status_badge status={work_item.status_variant}>
                {format_atom(work_item.status)}
              </.status_badge>
              <p class="text-xs text-base-content/40">
                {work_item.assignment_count || 0} assignments · {format_minutes(
                  work_item.estimate_minutes
                )}
              </p>
            </div>
          </.link>
        </div>
      </.section>

      <.section :if={@project.description} title="Description">
        <p class="whitespace-pre-wrap text-sm leading-6 text-base-content/70">
          {@project.description}
        </p>
      </.section>

      <.section :if={@project.notes} title="Notes">
        <p class="whitespace-pre-wrap text-sm leading-6 text-base-content/70">
          {@project.notes}
        </p>
      </.section>

      <.section
        title="Change Orders"
        description="Project-facing commercial deltas should stay visible to delivery instead of disappearing into contract history."
      >
        <div :if={Enum.empty?(@project.change_orders || [])}>
          <.empty_state
            icon="hero-arrow-path"
            title="No change orders yet"
            description="Add change orders here when execution uncovers scope, pricing, or schedule changes that need explicit approval."
          >
            <:action>
              <.button navigate={~p"/commercial/change-orders/new?project_id=#{@project.id}"}>
                Create Change Order
              </.button>
            </:action>
          </.empty_state>
        </div>

        <div :if={!Enum.empty?(@project.change_orders || [])} class="space-y-3">
          <.link
            :for={change_order <- @project.change_orders}
            navigate={~p"/commercial/change-orders/#{change_order}"}
            class="flex items-center justify-between rounded-2xl border border-zinc-200 bg-zinc-50/70 px-4 py-4 transition hover:border-emerald-300 hover:bg-white dark:border-white/10 dark:bg-white/[0.03] dark:hover:border-emerald-400/40"
          >
            <div class="space-y-1">
              <p class="font-medium text-base-content">{change_order.title}</p>
              <p class="text-sm text-base-content/50">
                {change_order.change_order_number}
              </p>
            </div>
            <.status_badge status={change_order.status_variant}>
              {format_atom(change_order.status)}
            </.status_badge>
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
      <p class="text-xs font-semibold uppercase tracking-[0.2em] text-base-content/40">
        {@label}
      </p>
      <p class="text-sm font-medium text-base-content">{@value}</p>
    </div>
    """
  end

  defp time_entry_params(project) do
    %{
      organization_id: project.organization_id,
      project_id: project.id
    }
  end

  defp expense_params(project) do
    %{
      organization_id: project.organization_id,
      project_id: project.id
    }
  end

  defp load_project!(id, actor) do
    case Execution.get_project(
           id,
           actor: actor,
           load: [
             :status_variant,
             :priority_variant,
             :assignment_count,
             :work_item_count,
             :work_order_count,
             :material_usage_count,
             organization: [],
             agreement: [],
             change_orders: [:status_variant]
           ]
         ) do
      {:ok, project} -> project
      {:error, error} -> raise "failed to load project #{id}: #{inspect(error)}"
    end
  end

  defp load_project_work_items!(project_id, actor) do
    case Execution.list_work_items_for_project(
           project_id,
           actor: actor,
           load: [:status_variant, :priority_variant, :assignment_count, :owner_team_member]
         ) do
      {:ok, work_items} ->
        work_items

      {:error, error} ->
        raise "failed to load work items for project #{project_id}: #{inspect(error)}"
    end
  end

  defp decimal_or_dash(nil), do: "-"
  defp decimal_or_dash(%Decimal{} = value), do: Decimal.to_string(value)
  defp decimal_or_dash(value), do: to_string(value)

  defp project_actions(%{status: :planned}) do
    [
      %{action: "approve", label: "Approve", icon: "hero-check-badge", variant: nil},
      %{action: "start", label: "Start", icon: "hero-play", variant: "primary"},
      %{action: "cancel", label: "Cancel", icon: "hero-x-circle", variant: nil}
    ]
  end

  defp project_actions(%{status: :ready}) do
    [
      %{action: "start", label: "Start", icon: "hero-play", variant: "primary"},
      %{action: "hold", label: "Hold", icon: "hero-pause", variant: nil},
      %{action: "cancel", label: "Cancel", icon: "hero-x-circle", variant: nil}
    ]
  end

  defp project_actions(%{status: :active}) do
    [
      %{action: "hold", label: "Hold", icon: "hero-pause", variant: nil},
      %{action: "complete", label: "Complete", icon: "hero-check", variant: "primary"}
    ]
  end

  defp project_actions(%{status: :on_hold}) do
    [
      %{action: "start", label: "Resume", icon: "hero-play", variant: "primary"},
      %{action: "complete", label: "Complete", icon: "hero-check", variant: nil},
      %{action: "cancel", label: "Cancel", icon: "hero-x-circle", variant: nil}
    ]
  end

  defp project_actions(%{status: :completed}) do
    [
      %{action: "reopen", label: "Reopen", icon: "hero-arrow-path", variant: "primary"}
    ]
  end

  defp project_actions(%{status: :cancelled}) do
    [
      %{action: "reopen", label: "Reopen", icon: "hero-arrow-path", variant: "primary"}
    ]
  end

  defp project_actions(_project), do: []

  defp transition_project(project, :approve, actor),
    do: Execution.approve_project(project, actor: actor)

  defp transition_project(project, :start, actor),
    do: Execution.start_project(project, actor: actor)

  defp transition_project(project, :hold, actor),
    do: Execution.hold_project(project, actor: actor)

  defp transition_project(project, :complete, actor),
    do: Execution.complete_project(project, actor: actor)

  defp transition_project(project, :cancel, actor),
    do: Execution.cancel_project(project, actor: actor)

  defp transition_project(project, :reopen, actor),
    do: Execution.reopen_project(project, actor: actor)
end
