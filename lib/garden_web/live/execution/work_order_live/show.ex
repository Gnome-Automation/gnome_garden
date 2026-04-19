defmodule GnomeGardenWeb.Execution.WorkOrderLive.Show do
  use GnomeGardenWeb, :live_view

  import GnomeGardenWeb.Execution.Helpers

  alias GnomeGarden.Execution

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    work_order = load_work_order!(id, socket.assigns.current_user)

    {:ok,
     socket
     |> assign(:page_title, work_order.title)
     |> assign(:work_order, work_order)}
  end

  @impl true
  def handle_event("transition", %{"action" => action}, socket) do
    work_order = socket.assigns.work_order

    case transition_work_order(
           work_order,
           String.to_existing_atom(action),
           socket.assigns.current_user
         ) do
      {:ok, updated_work_order} ->
        {:noreply,
         socket
         |> assign(
           :work_order,
           load_work_order!(updated_work_order.id, socket.assigns.current_user)
         )
         |> put_flash(:info, "Work order updated")}

      {:error, error} ->
        {:noreply, put_flash(socket, :error, "Could not update work order: #{inspect(error)}")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.page class="pb-8">
      <.page_header eyebrow="Execution">
        {@work_order.title}
        <:subtitle>
          <span class="inline-flex items-center gap-2">
            <.status_badge status={@work_order.status_variant}>
              {format_atom(@work_order.status)}
            </.status_badge>
            <span class="text-zinc-400 dark:text-zinc-500">/</span>
            <span>{@work_order.reference_number || "No reference number"}</span>
          </span>
        </:subtitle>
        <:actions>
          <.button navigate={~p"/execution/work-orders"}>
            <.icon name="hero-arrow-left" class="size-4" /> Back
          </.button>
          <.button
            :if={@work_order.service_ticket}
            navigate={~p"/execution/service-tickets/#{@work_order.service_ticket}"}
          >
            <.icon name="hero-lifebuoy" class="size-4" /> Service Ticket
          </.button>
          <.button navigate={~p"/execution/work-orders/#{@work_order}/edit"}>
            <.icon name="hero-pencil-square" class="size-4" /> Edit
          </.button>
        </:actions>
      </.page_header>

      <.section
        title="Work Order Actions"
        description="Drive execution through explicit scheduling and completion states so the downstream financial and entitlement automation can trust it."
      >
        <div class="flex flex-wrap gap-3">
          <.button
            :for={action <- work_order_actions(@work_order)}
            phx-click="transition"
            phx-value-action={action.action}
            variant={action.variant}
          >
            <.icon name={action.icon} class="size-4" /> {action.label}
          </.button>
        </div>
      </.section>

      <div class="grid gap-6 lg:grid-cols-2">
        <.section title="Execution Snapshot">
          <div class="grid gap-5 sm:grid-cols-2">
            <.property_item label="Work Type" value={format_atom(@work_order.work_type)} />
            <.property_item label="Priority" value={format_atom(@work_order.priority)} />
            <.property_item
              label="Billable"
              value={if(@work_order.billable, do: "Yes", else: "No")}
            />
            <.property_item
              label="Estimated Minutes"
              value={integer_or_dash(@work_order.estimated_minutes)}
            />
            <.property_item label="Due On" value={format_date(@work_order.due_on)} />
            <.property_item
              label="Scheduled Start"
              value={format_datetime(@work_order.scheduled_start_at)}
            />
            <.property_item
              label="Scheduled End"
              value={format_datetime(@work_order.scheduled_end_at)}
            />
            <.property_item
              label="Completed At"
              value={format_datetime(@work_order.completed_at)}
            />
          </div>
        </.section>

        <.section title="Operational Context">
          <div class="grid gap-5 sm:grid-cols-2">
            <.property_item
              label="Organization"
              value={(@work_order.organization && @work_order.organization.name) || "-"}
            />
            <.property_item label="Site" value={(@work_order.site && @work_order.site.name) || "-"} />
            <.property_item
              label="Managed System"
              value={(@work_order.managed_system && @work_order.managed_system.name) || "-"}
            />
            <.property_item
              label="Asset"
              value={(@work_order.asset && @work_order.asset.name) || "-"}
            />
            <.property_item
              label="Service Ticket"
              value={(@work_order.service_ticket && @work_order.service_ticket.title) || "-"}
            />
            <.property_item
              label="Agreement"
              value={(@work_order.agreement && @work_order.agreement.name) || "-"}
            />
            <.property_item
              label="Project"
              value={(@work_order.project && @work_order.project.name) || "-"}
            />
            <.property_item
              label="Maintenance Plan"
              value={(@work_order.maintenance_plan && @work_order.maintenance_plan.name) || "-"}
            />
          </div>
        </.section>
      </div>

      <.section title="Execution Counts">
        <div class="grid gap-5 sm:grid-cols-3">
          <.property_item
            label="Assignments"
            value={Integer.to_string(@work_order.assignment_count || 0)}
          />
          <.property_item
            label="Material Usage"
            value={Integer.to_string(@work_order.material_usage_count || 0)}
          />
          <.property_item
            label="Entitlement Usage"
            value={Integer.to_string(@work_order.entitlement_usage_count || 0)}
          />
        </div>
      </.section>

      <.section :if={@work_order.description} title="Description">
        <p class="whitespace-pre-wrap text-sm leading-6 text-zinc-600 dark:text-zinc-300">
          {@work_order.description}
        </p>
      </.section>

      <.section :if={@work_order.resolution_notes} title="Resolution Notes">
        <p class="whitespace-pre-wrap text-sm leading-6 text-zinc-600 dark:text-zinc-300">
          {@work_order.resolution_notes}
        </p>
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

  defp load_work_order!(id, actor) do
    case Execution.get_work_order(
           id,
           actor: actor,
           load: [
             :status_variant,
             :priority_variant,
             :assignment_count,
             :material_usage_count,
             :entitlement_usage_count,
             organization: [],
             site: [],
             managed_system: [],
             asset: [],
             service_ticket: [],
             agreement: [],
             project: [],
             maintenance_plan: []
           ]
         ) do
      {:ok, work_order} -> work_order
      {:error, error} -> raise "failed to load work order #{id}: #{inspect(error)}"
    end
  end

  defp integer_or_dash(nil), do: "-"
  defp integer_or_dash(value), do: Integer.to_string(value)

  defp work_order_actions(%{status: :new}) do
    [
      %{action: "schedule", label: "Schedule", icon: "hero-calendar-days", variant: "primary"},
      %{action: "cancel", label: "Cancel", icon: "hero-x-circle", variant: nil}
    ]
  end

  defp work_order_actions(%{status: :scheduled}) do
    [
      %{action: "dispatch", label: "Dispatch", icon: "hero-paper-airplane", variant: "primary"},
      %{action: "start", label: "Start", icon: "hero-play", variant: nil},
      %{action: "cancel", label: "Cancel", icon: "hero-x-circle", variant: nil}
    ]
  end

  defp work_order_actions(%{status: :dispatched}) do
    [
      %{action: "start", label: "Start", icon: "hero-play", variant: "primary"},
      %{action: "complete", label: "Complete", icon: "hero-check", variant: nil},
      %{action: "cancel", label: "Cancel", icon: "hero-x-circle", variant: nil}
    ]
  end

  defp work_order_actions(%{status: :in_progress}) do
    [
      %{action: "complete", label: "Complete", icon: "hero-check", variant: "primary"}
    ]
  end

  defp work_order_actions(%{status: :completed}) do
    [
      %{action: "reopen", label: "Reopen", icon: "hero-arrow-path", variant: "primary"}
    ]
  end

  defp work_order_actions(%{status: :cancelled}) do
    [
      %{action: "reopen", label: "Reopen", icon: "hero-arrow-path", variant: "primary"}
    ]
  end

  defp work_order_actions(_work_order), do: []

  defp transition_work_order(work_order, :schedule, actor),
    do: Execution.schedule_work_order(work_order, actor: actor)

  defp transition_work_order(work_order, :dispatch, actor),
    do: Execution.dispatch_work_order(work_order, actor: actor)

  defp transition_work_order(work_order, :start, actor),
    do: Execution.start_work_order(work_order, actor: actor)

  defp transition_work_order(work_order, :complete, actor),
    do: Execution.complete_work_order(work_order, actor: actor)

  defp transition_work_order(work_order, :cancel, actor),
    do: Execution.cancel_work_order(work_order, actor: actor)

  defp transition_work_order(work_order, :reopen, actor),
    do: Execution.reopen_work_order(work_order, actor: actor)
end
