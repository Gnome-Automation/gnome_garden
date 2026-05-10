defmodule GnomeGardenWeb.Execution.WorkOrderLive.Index do
  use GnomeGardenWeb, :live_view
  use Cinder.UrlSync

  import GnomeGardenWeb.Execution.Helpers

  alias GnomeGarden.Execution

  @impl true
  def mount(_params, _session, socket) do
    counts = load_counts(socket.assigns.current_user)

    {:ok,
     socket
     |> assign(:page_title, "Work Orders")
     |> assign(:work_order_count, counts.total)
     |> assign(:scheduled_count, counts.scheduled)
     |> assign(:in_progress_count, counts.in_progress)
     |> assign(:completed_count, counts.completed)}
  end

  @impl true
  def handle_params(params, uri, socket) do
    socket = Cinder.UrlSync.handle_params(params, uri, socket)
    {:noreply, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.page class="pb-8">
      <.page_header eyebrow="Execution">
        Work Orders
        <:subtitle>
          Scheduled and billable execution records for service calls, inspections, commissioning, and maintenance work.
        </:subtitle>
        <:actions>
          <.button navigate={~p"/execution/service-tickets"}>
            Service Tickets
          </.button>
          <.button navigate={~p"/execution/work-orders/new"} variant="primary">
            New Work Order
          </.button>
        </:actions>
      </.page_header>

      <div class="grid gap-4 md:grid-cols-4">
        <.stat_card
          title="Work Orders"
          value={Integer.to_string(@work_order_count)}
          description="Execution units that move from intake into planned, dispatched, and completed field or digital work."
          icon="hero-wrench-screwdriver"
        />
        <.stat_card
          title="Scheduled"
          value={Integer.to_string(@scheduled_count)}
          description="Work already planned but not yet in active execution."
          icon="hero-calendar-days"
          accent="sky"
        />
        <.stat_card
          title="In Progress"
          value={Integer.to_string(@in_progress_count)}
          description="Work currently being executed in the field, remotely, or through internal engineering."
          icon="hero-play"
          accent="amber"
        />
        <.stat_card
          title="Completed"
          value={Integer.to_string(@completed_count)}
          description="Work finished and ready to support billing, entitlement consumption, and service history."
          icon="hero-check-badge"
          accent="emerald"
        />
      </div>

      <Cinder.collection
        id="work-orders-table"
        resource={GnomeGarden.Execution.WorkOrder}
        actor={@current_user}
        url_state={@url_state}
        theme={GnomeGardenWeb.CinderTheme}
        page_size={25}
        query_opts={[
          load: [
            :status_variant,
            :priority_variant,
            :assignment_count,
            organization: [],
            asset: [],
            service_ticket: []
          ]
        ]}
        click={fn row -> JS.navigate(~p"/execution/work-orders/#{row}") end}
      >
        <:col :let={work_order} field="title" search sort label="Work Order">
          <div class="space-y-1">
            <div class="font-medium text-base-content">{work_order.title}</div>
            <p class="text-sm text-base-content/50">
              {work_order.reference_number || "No reference number"}
            </p>
          </div>
        </:col>

        <:col :let={work_order} label="Context">
          <div class="space-y-1">
            <p>{(work_order.organization && work_order.organization.name) || "-"}</p>
            <p class="text-xs text-base-content/40">
              {(work_order.service_ticket && work_order.service_ticket.title) ||
                (work_order.asset && work_order.asset.name) || "No ticket/asset"}
            </p>
          </div>
        </:col>

        <:col :let={work_order} field="due_on" sort label="Type">
          <div class="space-y-1">
            <p>{format_atom(work_order.work_type)}</p>
            <p class="text-xs text-base-content/40">
              Due {format_date(work_order.due_on)}
            </p>
          </div>
        </:col>

        <:col :let={work_order} field="status" sort label="Status">
          <.status_badge status={work_order.status_variant}>
            {format_atom(work_order.status)}
          </.status_badge>
        </:col>

        <:col :let={work_order} label="Priority">
          <div class="space-y-1">
            <.status_badge status={work_order.priority_variant}>
              {format_atom(work_order.priority)}
            </.status_badge>
            <p class="text-xs text-base-content/40">
              {work_order.assignment_count || 0} assignments
            </p>
          </div>
        </:col>

        <:empty>
          <.empty_state
            icon="hero-wrench-screwdriver"
            title="No work orders yet"
            description="Create work orders directly, or seed them from service tickets and maintenance plans."
          >
            <:action>
              <.button navigate={~p"/execution/work-orders/new"} variant="primary">
                Create Work Order
              </.button>
            </:action>
          </.empty_state>
        </:empty>
      </Cinder.collection>
    </.page>
    """
  end

  defp load_counts(actor) do
    case Execution.list_work_orders(actor: actor) do
      {:ok, work_orders} ->
        %{
          total: length(work_orders),
          scheduled: Enum.count(work_orders, &(&1.status == :scheduled)),
          in_progress: Enum.count(work_orders, &(&1.status == :in_progress)),
          completed: Enum.count(work_orders, &(&1.status == :completed))
        }

      {:error, _} ->
        %{total: 0, scheduled: 0, in_progress: 0, completed: 0}
    end
  end
end
