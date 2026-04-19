defmodule GnomeGardenWeb.Execution.ServiceTicketLive.Index do
  use GnomeGardenWeb, :live_view

  import GnomeGardenWeb.Execution.Helpers

  alias GnomeGarden.Execution

  @impl true
  def mount(_params, _session, socket) do
    service_tickets = load_service_tickets(socket.assigns.current_user)

    {:ok,
     socket
     |> assign(:page_title, "Service Tickets")
     |> assign(:ticket_count, length(service_tickets))
     |> assign(:critical_count, Enum.count(service_tickets, &(&1.severity == :critical)))
     |> assign(
       :active_count,
       Enum.count(
         service_tickets,
         &(&1.status in [:new, :triaged, :in_progress, :waiting_on_customer])
       )
     )
     |> assign(
       :work_order_count,
       Enum.reduce(service_tickets, 0, fn ticket, total ->
         total + (ticket.work_order_count || 0)
       end)
     )
     |> stream(:service_tickets, service_tickets)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.page class="pb-8">
      <.page_header eyebrow="Execution">
        Service Tickets
        <:subtitle>
          Customer-facing intake for incidents, requests, warranty calls, and maintenance needs before they become work orders.
        </:subtitle>
        <:actions>
          <.button navigate={~p"/operations/assets"}>
            <.icon name="hero-cpu-chip" class="size-4" /> Assets
          </.button>
          <.button navigate={~p"/execution/service-tickets/new"} variant="primary">
            <.icon name="hero-plus" class="size-4" /> New Service Ticket
          </.button>
        </:actions>
      </.page_header>

      <div class="grid gap-4 md:grid-cols-4">
        <.stat_card
          title="Tickets"
          value={Integer.to_string(@ticket_count)}
          description="All customer-facing intake records currently tracked in operations."
          icon="hero-lifebuoy"
        />
        <.stat_card
          title="Active"
          value={Integer.to_string(@active_count)}
          description="Tickets that still require triage, execution, or customer follow-up."
          icon="hero-arrow-path"
          accent="sky"
        />
        <.stat_card
          title="Critical"
          value={Integer.to_string(@critical_count)}
          description="High-severity issues that should stand out immediately in the service queue."
          icon="hero-exclamation-triangle"
          accent="amber"
        />
        <.stat_card
          title="Work Orders"
          value={Integer.to_string(@work_order_count)}
          description="Execution units already created downstream from these tickets."
          icon="hero-wrench-screwdriver"
          accent="rose"
        />
      </div>

      <.section
        title="Service Intake Queue"
        description="Use tickets for customer communication and triage, then drive the actual work through explicit work orders."
        compact
        body_class="p-0"
      >
        <div :if={@ticket_count == 0} class="p-6 sm:p-7">
          <.empty_state
            icon="hero-lifebuoy"
            title="No service tickets yet"
            description="Create tickets for incidents, support requests, warranty calls, and preventive maintenance intake."
          >
            <:action>
              <.button navigate={~p"/execution/service-tickets/new"} variant="primary">
                Create Service Ticket
              </.button>
            </:action>
          </.empty_state>
        </div>

        <div :if={@ticket_count > 0} class="overflow-x-auto">
          <table class="min-w-full divide-y divide-zinc-200 text-sm dark:divide-white/10">
            <thead class="bg-zinc-50 dark:bg-white/[0.03]">
              <tr>
                <th class="px-5 py-3 text-left font-medium text-zinc-500 dark:text-zinc-400">
                  Ticket
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
                  Severity
                </th>
              </tr>
            </thead>
            <tbody
              id="service-tickets"
              phx-update="stream"
              class="divide-y divide-zinc-200 dark:divide-white/10"
            >
              <tr :for={{dom_id, ticket} <- @streams.service_tickets} id={dom_id}>
                <td class="px-5 py-4 align-top">
                  <div class="space-y-1">
                    <.link
                      navigate={~p"/execution/service-tickets/#{ticket}"}
                      class="font-medium text-zinc-900 hover:text-emerald-600 dark:text-white"
                    >
                      {ticket.title}
                    </.link>
                    <p class="text-sm text-zinc-500 dark:text-zinc-400">
                      {ticket.ticket_number || "No ticket number"}
                    </p>
                  </div>
                </td>
                <td class="px-5 py-4 align-top text-zinc-600 dark:text-zinc-300">
                  <div class="space-y-1">
                    <p>{(ticket.organization && ticket.organization.name) || "-"}</p>
                    <p class="text-xs text-zinc-400 dark:text-zinc-500">
                      {(ticket.asset && ticket.asset.name) || (ticket.site && ticket.site.name) ||
                        "No asset/site"}
                    </p>
                  </div>
                </td>
                <td class="px-5 py-4 align-top text-zinc-600 dark:text-zinc-300">
                  <div class="space-y-1">
                    <p>{format_atom(ticket.ticket_type)}</p>
                    <p class="text-xs text-zinc-400 dark:text-zinc-500">
                      {ticket.work_order_count || 0} work orders
                    </p>
                  </div>
                </td>
                <td class="px-5 py-4 align-top">
                  <.status_badge status={ticket.status_variant}>
                    {format_atom(ticket.status)}
                  </.status_badge>
                </td>
                <td class="px-5 py-4 align-top">
                  <.status_badge status={ticket.severity_variant}>
                    {format_atom(ticket.severity)}
                  </.status_badge>
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </.section>
    </.page>
    """
  end

  defp load_service_tickets(actor) do
    case Execution.list_service_tickets(
           actor: actor,
           query: [sort: [reported_at: :desc, inserted_at: :desc]],
           load: [
             :status_variant,
             :severity_variant,
             :work_order_count,
             organization: [],
             site: [],
             asset: []
           ]
         ) do
      {:ok, service_tickets} -> service_tickets
      {:error, error} -> raise "failed to load service tickets: #{inspect(error)}"
    end
  end
end
