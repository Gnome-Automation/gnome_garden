defmodule GnomeGardenWeb.Execution.ServiceTicketLive.Index do
  use GnomeGardenWeb, :live_view
  use Cinder.UrlSync

  import GnomeGardenWeb.Execution.Helpers

  alias GnomeGarden.Execution

  @impl true
  def mount(_params, _session, socket) do
    counts = load_counts(socket.assigns.current_user)

    {:ok,
     socket
     |> assign(:page_title, "Service Tickets")
     |> assign(:ticket_count, counts.total)
     |> assign(:critical_count, counts.critical)
     |> assign(:active_count, counts.active)
     |> assign(:work_order_count, counts.work_orders)}
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
        Service Tickets
        <:subtitle>
          Customer-facing intake for incidents, requests, warranty calls, and maintenance needs before they become work orders.
        </:subtitle>
        <:actions>
          <.button navigate={~p"/operations/assets"}>
            Assets
          </.button>
          <.button navigate={~p"/execution/service-tickets/new"} variant="primary">
            New Service Ticket
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

      <Cinder.collection
        id="service-tickets-table"
        resource={GnomeGarden.Execution.ServiceTicket}
        actor={@current_user}
        url_state={@url_state}
        theme={GnomeGardenWeb.CinderTheme}
        page_size={25}
        query_opts={[
          load: [
            :status_variant,
            :severity_variant,
            :work_order_count,
            organization: [],
            site: [],
            asset: []
          ]
        ]}
        click={fn row -> JS.navigate(~p"/execution/service-tickets/#{row}") end}
      >
        <:col :let={ticket} field="title" search sort label="Ticket">
          <div class="space-y-1">
            <div class="font-medium text-base-content">{ticket.title}</div>
            <p class="text-sm text-base-content/50">
              {ticket.ticket_number || "No ticket number"}
            </p>
          </div>
        </:col>

        <:col :let={ticket} field="ticket_number" search label="Context">
          <div class="space-y-1">
            <p>{(ticket.organization && ticket.organization.name) || "-"}</p>
            <p class="text-xs text-base-content/40">
              {(ticket.asset && ticket.asset.name) || (ticket.site && ticket.site.name) ||
                "No asset/site"}
            </p>
          </div>
        </:col>

        <:col :let={ticket} field="ticket_type" sort label="Type">
          <div class="space-y-1">
            <p>{format_atom(ticket.ticket_type)}</p>
            <p class="text-xs text-base-content/40">
              {ticket.work_order_count || 0} work orders
            </p>
          </div>
        </:col>

        <:col :let={ticket} field="status" sort label="Status">
          <.status_badge status={ticket.status_variant}>
            {format_atom(ticket.status)}
          </.status_badge>
        </:col>

        <:col :let={ticket} field="severity" sort label="Severity">
          <.status_badge status={ticket.severity_variant}>
            {format_atom(ticket.severity)}
          </.status_badge>
        </:col>

        <:empty>
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
        </:empty>
      </Cinder.collection>
    </.page>
    """
  end

  defp load_counts(actor) do
    case Execution.list_service_tickets(actor: actor, load: [:work_order_count]) do
      {:ok, service_tickets} ->
        %{
          total: length(service_tickets),
          critical: Enum.count(service_tickets, &(&1.severity == :critical)),
          active:
            Enum.count(
              service_tickets,
              &(&1.status in [:new, :triaged, :in_progress, :waiting_on_customer])
            ),
          work_orders:
            Enum.reduce(service_tickets, 0, fn ticket, total ->
              total + (ticket.work_order_count || 0)
            end)
        }

      {:error, _} ->
        %{total: 0, critical: 0, active: 0, work_orders: 0}
    end
  end
end
