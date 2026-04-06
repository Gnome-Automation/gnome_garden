defmodule GnomeGardenWeb.CRM.LeadLive.Index do
  use GnomeGardenWeb, :live_view

  import GnomeGardenWeb.CRM.Helpers

  alias GnomeGarden.Sales.Lead

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      GnomeGardenWeb.Endpoint.subscribe("lead:created")
      GnomeGardenWeb.Endpoint.subscribe("lead:qualified")
      GnomeGardenWeb.Endpoint.subscribe("lead:updated")
    end

    {:ok, assign(socket, page_title: "Leads")}
  end

  @impl true
  def handle_info(%{topic: "lead:" <> _}, socket) do
    {:noreply, Cinder.refresh_table(socket, "leads")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <div class="flex justify-end">
        <.button navigate={~p"/crm/leads/new"} variant="primary">
          <.icon name="hero-plus" class="size-4" /> Add Lead
        </.button>
      </div>

      <Cinder.collection
        id="leads"
        resource={Lead}
        actor={@current_user}
        search={[placeholder: "Search leads..."]}
      >
        <:col :let={lead} field="first_name" label="Name" sort search>
          <.link navigate={~p"/crm/leads/#{lead}"} class="font-medium hover:text-emerald-600">
            {lead.first_name} {lead.last_name}
          </.link>
        </:col>
        <:col :let={lead} field="company_name" label="Company" search>
          {lead.company_name || "-"}
        </:col>
        <:col :let={lead} field="email" label="Email" search>
          {lead.email || "-"}
        </:col>
        <:col :let={lead} field="status" label="Status" sort>
          <.status_badge status={lead_status(lead.status)}>
            {format_atom(lead.status)}
          </.status_badge>
        </:col>
        <:col :let={lead} field="source" label="Source">
          {format_source(lead.source)}
        </:col>
        <:col :let={lead} label="">
          <.link
            navigate={~p"/crm/leads/#{lead}/edit"}
            class="inline-flex items-center justify-center rounded-md p-1.5 text-zinc-400 transition hover:bg-zinc-900/5 hover:text-zinc-600 dark:hover:bg-white/5 dark:hover:text-zinc-300"
          >
            <.icon name="hero-pencil" class="size-4" />
          </.link>
        </:col>
      </Cinder.collection>
    </div>
    """
  end
end
