defmodule GnomeGardenWeb.CRM.CompanyLive.Index do
  use GnomeGardenWeb, :live_view

  alias GnomeGarden.Sales.Company

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, page_title: "Companies", is_desktop: true)}
  end

  @impl true
  def handle_event("responsive-change", %{"is_desktop" => is_desktop}, socket) do
    {:noreply, assign(socket, :is_desktop, is_desktop)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.responsive_hook />

    <div class="space-y-6">
      <div class="flex items-center justify-end">
        <.button navigate={~p"/crm/companies/new"} variant="primary">
          <.icon name="hero-plus" class="size-4" />
          Add Company
        </.button>
      </div>

      <Cinder.collection
        id="companies"
        resource={Company}
        actor={@current_user}
        layout={if @is_desktop, do: :table, else: :grid}
        grid_columns={[xs: 1, sm: 2]}
        search={[placeholder: "Search companies..."]}
      >
        <:col :let={company} field="name" label="Name" sort search>
          <span class="font-medium text-zinc-900 dark:text-white">{company.name}</span>
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
          <span :if={company.city} class="text-zinc-600 dark:text-zinc-400">{company.city}</span>
          <span :if={!company.city} class="text-zinc-400">-</span>
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
            navigate={~p"/crm/companies/#{company}"}
            class="inline-flex items-center justify-center rounded-md p-1.5 text-zinc-400 transition hover:bg-zinc-900/5 hover:text-zinc-600 dark:hover:bg-white/5 dark:hover:text-zinc-300"
          >
            <.icon name="hero-pencil" class="size-4" />
          </.link>
        </:col>

        <:item :let={company}>
          <.company_card company={company} />
        </:item>
      </Cinder.collection>
    </div>
    """
  end

  defp company_card(assigns) do
    ~H"""
    <div class="group relative flex rounded-2xl bg-zinc-50 transition-shadow hover:shadow-md hover:shadow-zinc-900/5 dark:bg-white/[0.025] dark:hover:shadow-black/5">
      <%!-- Grid pattern background --%>
      <div class="pointer-events-none">
        <div class="absolute inset-0 rounded-2xl [mask-image:linear-gradient(white,transparent)] transition duration-300 group-hover:opacity-50">
          <.grid_pattern
            id={"company-#{@company.id}"}
            y={16}
            squares={[[0, 1], [1, 3]]}
            class="fill-black/[0.02] stroke-black/5 dark:fill-white/[0.01] dark:stroke-white/[0.025]"
          />
        </div>
        <%!-- Hover gradient --%>
        <div class="absolute inset-0 rounded-2xl bg-gradient-to-r from-[#D7EDEA] to-[#F4FBDF] opacity-0 transition duration-300 group-hover:opacity-100 dark:from-[#202D2E] dark:to-[#303428]" />
      </div>

      <%!-- Ring border --%>
      <div class="absolute inset-0 rounded-2xl ring-1 ring-inset ring-zinc-900/[0.075] group-hover:ring-zinc-900/10 dark:ring-white/10 dark:group-hover:ring-white/20" />

      <%!-- Content --%>
      <div class="relative w-full rounded-2xl p-4">
        <div class="flex items-start justify-between gap-3">
          <%!-- Company icon --%>
          <div class="flex h-8 w-8 items-center justify-center rounded-full bg-zinc-900/5 ring-1 ring-zinc-900/25 backdrop-blur-[2px] transition duration-300 group-hover:bg-white/50 group-hover:ring-zinc-900/25 dark:bg-white/[0.075] dark:ring-white/15 dark:group-hover:bg-emerald-300/10 dark:group-hover:ring-emerald-400">
            <.icon name="hero-building-office-2" class="size-4 text-zinc-700 transition-colors duration-300 group-hover:text-zinc-900 dark:text-zinc-400 dark:group-hover:text-emerald-400" />
          </div>

          <div class="min-w-0 flex-1">
            <h3 class="text-sm font-semibold text-zinc-900 dark:text-white truncate">
              <.link navigate={~p"/crm/companies/#{@company}"}>
                <span class="absolute inset-0 rounded-2xl" />
                {@company.name}
              </.link>
            </h3>
            <p :if={@company.website} class="mt-0.5 text-sm text-emerald-600 dark:text-emerald-400 truncate">
              {URI.parse(@company.website).host}
            </p>
          </div>

          <.link
            navigate={~p"/crm/companies/#{@company}/edit"}
            class="relative z-10 shrink-0 rounded-md p-1.5 text-zinc-400 transition hover:bg-zinc-900/5 hover:text-zinc-600 dark:hover:bg-white/5 dark:hover:text-zinc-300"
          >
            <.icon name="hero-pencil" class="size-4" />
          </.link>
        </div>

        <div class="mt-3 flex flex-wrap items-center gap-2">
          <span :if={@company.city} class="inline-flex items-center gap-1 text-xs text-zinc-600 dark:text-zinc-400">
            <.icon name="hero-map-pin" class="size-3" />
            {@company.city}
          </span>
          <.tag :if={@company.region} color={:zinc}>{format_region(@company.region)}</.tag>
          <.tag :if={@company.source} color={:emerald}>{format_source(@company.source)}</.tag>
        </div>
      </div>
    </div>
    """
  end

  defp format_region(nil), do: "-"
  defp format_region(region), do: region |> to_string() |> String.upcase()

  defp format_source(nil), do: "-"
  defp format_source(source), do: source |> to_string() |> String.replace("_", " ")
end
