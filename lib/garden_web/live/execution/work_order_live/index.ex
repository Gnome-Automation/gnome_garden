defmodule GnomeGardenWeb.Execution.WorkOrderLive.Index do
  use GnomeGardenWeb, :live_view

  import GnomeGardenWeb.Execution.Helpers

  alias GnomeGarden.Execution

  @impl true
  def mount(_params, _session, socket) do
    work_orders = load_work_orders(socket.assigns.current_user)

    {:ok,
     socket
     |> assign(:page_title, "Work Orders")
     |> assign(:work_order_count, length(work_orders))
     |> assign(:scheduled_count, Enum.count(work_orders, &(&1.status == :scheduled)))
     |> assign(:in_progress_count, Enum.count(work_orders, &(&1.status == :in_progress)))
     |> assign(:completed_count, Enum.count(work_orders, &(&1.status == :completed)))
     |> stream(:work_orders, work_orders)}
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
            <.icon name="hero-lifebuoy" class="size-4" /> Service Tickets
          </.button>
          <.button navigate={~p"/execution/work-orders/new"} variant="primary">
            <.icon name="hero-plus" class="size-4" /> New Work Order
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

      <.section
        title="Execution Queue"
        description="Keep service work and delivery-adjacent field work explicit so scheduling, billing, and reporting stay grounded."
        compact
        body_class="p-0"
      >
        <div :if={@work_order_count == 0} class="p-6 sm:p-7">
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
        </div>

        <div :if={@work_order_count > 0} class="overflow-x-auto">
          <table class="min-w-full divide-y divide-zinc-200 text-sm dark:divide-white/10">
            <thead class="bg-zinc-50 dark:bg-white/[0.03]">
              <tr>
                <th class="px-5 py-3 text-left font-medium text-zinc-500 dark:text-zinc-400">
                  Work Order
                </th>
                <th class="px-5 py-3 text-left font-medium text-zinc-500 dark:text-zinc-400">
                  Context
                </th>
                <th class="px-5 py-3 text-left font-medium text-zinc-500 dark:text-zinc-400">
                  Type
                </th>
                <th class="px-5 py-3 text-left font-medium text-zinc-500 dark:text-zinc-400">
                  Status
                </th>
                <th class="px-5 py-3 text-left font-medium text-zinc-500 dark:text-zinc-400">
                  Priority
                </th>
              </tr>
            </thead>
            <tbody
              id="work-orders"
              phx-update="stream"
              class="divide-y divide-zinc-200 dark:divide-white/10"
            >
              <tr :for={{dom_id, work_order} <- @streams.work_orders} id={dom_id}>
                <td class="px-5 py-4 align-top">
                  <div class="space-y-1">
                    <.link
                      navigate={~p"/execution/work-orders/#{work_order}"}
                      class="font-medium text-zinc-900 hover:text-emerald-600 dark:text-white"
                    >
                      {work_order.title}
                    </.link>
                    <p class="text-sm text-zinc-500 dark:text-zinc-400">
                      {work_order.reference_number || "No reference number"}
                    </p>
                  </div>
                </td>
                <td class="px-5 py-4 align-top text-zinc-600 dark:text-zinc-300">
                  <div class="space-y-1">
                    <p>{(work_order.organization && work_order.organization.name) || "-"}</p>
                    <p class="text-xs text-zinc-400 dark:text-zinc-500">
                      {(work_order.service_ticket && work_order.service_ticket.title) ||
                        (work_order.asset && work_order.asset.name) || "No ticket/asset"}
                    </p>
                  </div>
                </td>
                <td class="px-5 py-4 align-top text-zinc-600 dark:text-zinc-300">
                  <div class="space-y-1">
                    <p>{format_atom(work_order.work_type)}</p>
                    <p class="text-xs text-zinc-400 dark:text-zinc-500">
                      Due {format_date(work_order.due_on)}
                    </p>
                  </div>
                </td>
                <td class="px-5 py-4 align-top">
                  <.status_badge status={work_order.status_variant}>
                    {format_atom(work_order.status)}
                  </.status_badge>
                </td>
                <td class="px-5 py-4 align-top">
                  <div class="space-y-1">
                    <.status_badge status={work_order.priority_variant}>
                      {format_atom(work_order.priority)}
                    </.status_badge>
                    <p class="text-xs text-zinc-400 dark:text-zinc-500">
                      {work_order.assignment_count || 0} assignments
                    </p>
                  </div>
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </.section>
    </.page>
    """
  end

  defp load_work_orders(actor) do
    case Execution.list_work_orders(
           actor: actor,
           query: [sort: [due_on: :asc, inserted_at: :desc]],
           load: [
             :status_variant,
             :priority_variant,
             :assignment_count,
             organization: [],
             asset: [],
             service_ticket: []
           ]
         ) do
      {:ok, work_orders} -> work_orders
      {:error, error} -> raise "failed to load work orders: #{inspect(error)}"
    end
  end
end
