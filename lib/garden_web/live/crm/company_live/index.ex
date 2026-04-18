defmodule GnomeGardenWeb.CRM.CompanyLive.Index do
  use GnomeGardenWeb, :live_view

  import GnomeGardenWeb.CRM.Helpers

  alias GnomeGarden.Sales.Company

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      GnomeGardenWeb.Endpoint.subscribe("company:created")
      GnomeGardenWeb.Endpoint.subscribe("company:updated")
    end

    {:ok, assign(socket, page_title: "Companies", is_desktop: true)}
  end

  @impl true
  def handle_info(%{topic: "company:" <> _}, socket) do
    {:noreply, Cinder.refresh_table(socket, "companies")}
  end

  @impl true
  def handle_event("responsive-change", %{"is_desktop" => is_desktop}, socket) do
    {:noreply, assign(socket, :is_desktop, is_desktop)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.responsive_hook />

    <.page class="pb-8">
      <.page_header eyebrow="CRM">
        Companies
        <:subtitle>
          Track organizations across prospecting, pursuit, and customer delivery.
        </:subtitle>
        <:actions>
          <.button navigate={~p"/crm/companies/new"} variant="primary">
            <.icon name="hero-plus" class="size-4" /> Add Company
          </.button>
        </:actions>
      </.page_header>

      <.section
        title="Company Directory"
        description="Search and drill into the organizations that anchor your CRM workflow."
        compact
        body_class="p-0"
      >
        <Cinder.collection
          id="companies"
          resource={Company}
          actor={@current_user}
          layout={if @is_desktop, do: :table, else: :grid}
          grid_columns={[xs: 1, sm: 2]}
          search={[placeholder: "Search companies..."]}
        >
          <:col :let={company} field="name" label="Name" sort search>
            <.link
              navigate={~p"/crm/companies/#{company}"}
              class="font-medium text-zinc-900 hover:text-emerald-600 dark:text-white"
            >
              {company.name}
            </.link>
          </:col>
          <:col :let={company} field="website" label="Website" search>
            <a
              :if={company.website}
              href={company.website}
              target="_blank"
              class="text-emerald-600 hover:text-emerald-500 dark:text-emerald-400 dark:hover:text-emerald-300"
            >
              {URI.parse(company.website).host}
            </a>
            <span :if={!company.website} class="text-zinc-400">-</span>
          </:col>
          <:col :let={company} field="city" label="City" sort search>
            {company.city || "-"}
          </:col>
          <:col :let={company} field="region" label="Region" sort>
            <.tag :if={company.region} color={:zinc}>{format_region(company.region)}</.tag>
            <span :if={!company.region} class="text-zinc-400">-</span>
          </:col>
          <:col :let={company} field="source" label="Source">
            <.tag :if={company.source} color={:emerald}>{format_source(company.source)}</.tag>
            <span :if={!company.source} class="text-zinc-400">-</span>
          </:col>
          <:col :let={company} label="">
            <.link
              navigate={~p"/crm/companies/#{company}/edit"}
              class="inline-flex items-center justify-center rounded-md p-1.5 text-zinc-400 transition hover:bg-zinc-900/5 hover:text-zinc-600 dark:hover:bg-white/5 dark:hover:text-zinc-300"
            >
              <.icon name="hero-pencil" class="size-4" />
            </.link>
          </:col>

          <:item :let={company}>
            <.resource_card
              id={"company-#{company.id}"}
              navigate={~p"/crm/companies/#{company}"}
              title={company.name}
              description={company.website && URI.parse(company.website).host}
              icon="hero-building-office-2"
            >
              <div class="mt-3 flex flex-wrap items-center gap-2">
                <span
                  :if={company.city}
                  class="inline-flex items-center gap-1 text-xs text-zinc-600 dark:text-zinc-400"
                >
                  <.icon name="hero-map-pin" class="size-3" />
                  {company.city}
                </span>
                <.tag :if={company.region} color={:zinc}>{format_region(company.region)}</.tag>
                <.tag :if={company.source} color={:emerald}>{format_source(company.source)}</.tag>
              </div>
            </.resource_card>
          </:item>
        </Cinder.collection>
      </.section>
    </.page>
    """
  end
end
