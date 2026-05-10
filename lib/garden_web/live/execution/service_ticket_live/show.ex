defmodule GnomeGardenWeb.Execution.ServiceTicketLive.Show do
  use GnomeGardenWeb, :live_view

  import GnomeGardenWeb.Execution.Helpers

  alias GnomeGarden.Execution

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    service_ticket = load_service_ticket!(id, socket.assigns.current_user)

    {:ok,
     socket
     |> assign(:page_title, service_ticket.title)
     |> assign(:service_ticket, service_ticket)}
  end

  @impl true
  def handle_event("transition", %{"action" => action}, socket) do
    service_ticket = socket.assigns.service_ticket

    case transition_service_ticket(
           service_ticket,
           String.to_existing_atom(action),
           socket.assigns.current_user
         ) do
      {:ok, updated_service_ticket} ->
        {:noreply,
         socket
         |> assign(
           :service_ticket,
           load_service_ticket!(updated_service_ticket.id, socket.assigns.current_user)
         )
         |> put_flash(:info, "Service ticket updated")}

      {:error, error} ->
        {:noreply,
         put_flash(socket, :error, "Could not update service ticket: #{inspect(error)}")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.page class="pb-8">
      <.page_header eyebrow="Execution">
        {@service_ticket.title}
        <:subtitle>
          <span class="inline-flex items-center gap-2">
            <.status_badge status={@service_ticket.status_variant}>
              {format_atom(@service_ticket.status)}
            </.status_badge>
            <span class="text-base-content/40">/</span>
            <span>{@service_ticket.ticket_number || "No ticket number"}</span>
          </span>
        </:subtitle>
        <:actions>
          <.button navigate={~p"/execution/service-tickets"}>
            Back
          </.button>
          <.button navigate={~p"/execution/work-orders/new?service_ticket_id=#{@service_ticket.id}"}>
            New Work Order
          </.button>
          <.button navigate={~p"/execution/service-tickets/#{@service_ticket}/edit"}>
            Edit
          </.button>
        </:actions>
      </.page_header>

      <.section
        title="Ticket Actions"
        description="Advance the customer-facing service record explicitly so operators can see whether work is waiting on triage, execution, or the customer."
      >
        <div class="flex flex-wrap gap-3">
          <.button
            :for={action <- service_ticket_actions(@service_ticket)}
            phx-click="transition"
            phx-value-action={action.action}
            variant={action.variant}
          >
            <.icon name={action.icon} class="size-4" /> {action.label}
          </.button>
        </div>
      </.section>

      <div class="grid gap-6 lg:grid-cols-2">
        <.section title="Ticket Snapshot">
          <div class="grid gap-5 sm:grid-cols-2">
            <.property_item label="Ticket Type" value={format_atom(@service_ticket.ticket_type)} />
            <.property_item
              label="Source Channel"
              value={format_atom(@service_ticket.source_channel)}
            />
            <.property_item label="Severity" value={format_atom(@service_ticket.severity)} />
            <.property_item label="Impact" value={format_atom(@service_ticket.impact)} />
            <.property_item
              label="Reported At"
              value={format_datetime(@service_ticket.reported_at)}
            />
            <.property_item label="Due On" value={format_date(@service_ticket.due_on)} />
            <.property_item
              label="Resolved At"
              value={format_datetime(@service_ticket.resolved_at)}
            />
            <.property_item label="Closed At" value={format_datetime(@service_ticket.closed_at)} />
          </div>
        </.section>

        <.section title="Operational Context">
          <div class="grid gap-5 sm:grid-cols-2">
            <.property_item
              label="Organization"
              value={(@service_ticket.organization && @service_ticket.organization.name) || "-"}
            />
            <.property_item
              label="Requester"
              value={
                if @service_ticket.requester_person do
                  [
                    @service_ticket.requester_person.first_name,
                    @service_ticket.requester_person.last_name
                  ]
                  |> Enum.reject(&is_nil/1)
                  |> Enum.join(" ")
                else
                  "-"
                end
              }
            />
            <.property_item
              label="Site"
              value={(@service_ticket.site && @service_ticket.site.name) || "-"}
            />
            <.property_item
              label="Managed System"
              value={(@service_ticket.managed_system && @service_ticket.managed_system.name) || "-"}
            />
            <.property_item
              label="Asset"
              value={(@service_ticket.asset && @service_ticket.asset.name) || "-"}
            />
            <.property_item
              label="Agreement"
              value={(@service_ticket.agreement && @service_ticket.agreement.name) || "-"}
            />
            <.property_item
              label="SLA Policy"
              value={
                (@service_ticket.service_level_policy &&
                   @service_ticket.service_level_policy.name) || "-"
              }
            />
            <.property_item
              label="Work Orders"
              value={Integer.to_string(@service_ticket.work_order_count || 0)}
            />
          </div>
        </.section>
      </div>

      <.section :if={@service_ticket.description} title="Description">
        <p class="whitespace-pre-wrap text-sm leading-6 text-base-content/70">
          {@service_ticket.description}
        </p>
      </.section>

      <.section :if={@service_ticket.resolution_summary} title="Resolution Summary">
        <p class="whitespace-pre-wrap text-sm leading-6 text-base-content/70">
          {@service_ticket.resolution_summary}
        </p>
      </.section>

      <.section :if={@service_ticket.notes} title="Notes">
        <p class="whitespace-pre-wrap text-sm leading-6 text-base-content/70">
          {@service_ticket.notes}
        </p>
      </.section>

      <.section
        title="Work Orders"
        description="Tickets capture intake and communication; work orders track the execution that actually resolves the issue."
      >
        <div :if={Enum.empty?(@service_ticket.work_orders || [])}>
          <.empty_state
            icon="hero-wrench-screwdriver"
            title="No work orders yet"
            description="Create a work order when this ticket needs scheduled, dispatched, or tracked execution."
          >
            <:action>
              <.button navigate={
                ~p"/execution/work-orders/new?service_ticket_id=#{@service_ticket.id}"
              }>
                Create Work Order
              </.button>
            </:action>
          </.empty_state>
        </div>

        <div :if={!Enum.empty?(@service_ticket.work_orders || [])} class="space-y-3">
          <.link
            :for={work_order <- @service_ticket.work_orders}
            navigate={~p"/execution/work-orders/#{work_order}"}
            class="flex items-center justify-between rounded-2xl border border-zinc-200 bg-zinc-50/70 px-4 py-4 transition hover:border-emerald-300 hover:bg-white dark:border-white/10 dark:bg-white/[0.03] dark:hover:border-emerald-400/40"
          >
            <div class="space-y-1">
              <p class="font-medium text-base-content">{work_order.title}</p>
              <p class="text-sm text-base-content/50">
                {work_order.reference_number || "No reference number"}
              </p>
            </div>
            <.status_badge status={work_order.status_variant}>
              {format_atom(work_order.status)}
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

  defp load_service_ticket!(id, actor) do
    case Execution.get_service_ticket(
           id,
           actor: actor,
           load: [
             :status_variant,
             :severity_variant,
             :work_order_count,
             organization: [],
             site: [],
             managed_system: [],
             asset: [],
             agreement: [],
             requester_person: [],
             service_level_policy: [],
             work_orders: [:status_variant]
           ]
         ) do
      {:ok, service_ticket} -> service_ticket
      {:error, error} -> raise "failed to load service ticket #{id}: #{inspect(error)}"
    end
  end

  defp service_ticket_actions(%{status: :new}) do
    [
      %{action: "triage", label: "Triage", icon: "hero-funnel", variant: "primary"},
      %{action: "start", label: "Start", icon: "hero-play", variant: nil},
      %{action: "cancel", label: "Cancel", icon: "hero-x-circle", variant: nil}
    ]
  end

  defp service_ticket_actions(%{status: :triaged}) do
    [
      %{action: "start", label: "Start", icon: "hero-play", variant: "primary"},
      %{action: "pause", label: "Pause", icon: "hero-pause", variant: nil},
      %{action: "resolve", label: "Resolve", icon: "hero-check", variant: nil},
      %{action: "cancel", label: "Cancel", icon: "hero-x-circle", variant: nil}
    ]
  end

  defp service_ticket_actions(%{status: :in_progress}) do
    [
      %{action: "pause", label: "Pause", icon: "hero-pause", variant: nil},
      %{action: "resolve", label: "Resolve", icon: "hero-check", variant: "primary"}
    ]
  end

  defp service_ticket_actions(%{status: :waiting_on_customer}) do
    [
      %{action: "start", label: "Resume", icon: "hero-play", variant: "primary"},
      %{action: "resolve", label: "Resolve", icon: "hero-check", variant: nil},
      %{action: "cancel", label: "Cancel", icon: "hero-x-circle", variant: nil}
    ]
  end

  defp service_ticket_actions(%{status: :resolved}) do
    [
      %{action: "close", label: "Close", icon: "hero-lock-closed", variant: "primary"},
      %{action: "reopen", label: "Reopen", icon: "hero-arrow-path", variant: nil}
    ]
  end

  defp service_ticket_actions(%{status: :closed}) do
    [
      %{action: "reopen", label: "Reopen", icon: "hero-arrow-path", variant: "primary"}
    ]
  end

  defp service_ticket_actions(%{status: :cancelled}) do
    [
      %{action: "reopen", label: "Reopen", icon: "hero-arrow-path", variant: "primary"}
    ]
  end

  defp service_ticket_actions(_service_ticket), do: []

  defp transition_service_ticket(service_ticket, :triage, actor),
    do: Execution.triage_service_ticket(service_ticket, actor: actor)

  defp transition_service_ticket(service_ticket, :start, actor),
    do: Execution.start_service_ticket(service_ticket, actor: actor)

  defp transition_service_ticket(service_ticket, :pause, actor),
    do: Execution.pause_service_ticket(service_ticket, actor: actor)

  defp transition_service_ticket(service_ticket, :resolve, actor),
    do: Execution.resolve_service_ticket(service_ticket, actor: actor)

  defp transition_service_ticket(service_ticket, :close, actor),
    do: Execution.close_service_ticket(service_ticket, actor: actor)

  defp transition_service_ticket(service_ticket, :cancel, actor),
    do: Execution.cancel_service_ticket(service_ticket, actor: actor)

  defp transition_service_ticket(service_ticket, :reopen, actor),
    do: Execution.reopen_service_ticket(service_ticket, actor: actor)
end
