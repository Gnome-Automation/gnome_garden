defmodule GnomeGardenWeb.Operations.SiteLive.Index do
  use GnomeGardenWeb, :live_view

  import GnomeGardenWeb.Operations.Helpers

  alias GnomeGarden.Operations

  @impl true
  def mount(_params, _session, socket) do
    sites = load_sites(socket.assigns.current_user)

    {:ok,
     socket
     |> assign(:page_title, "Sites")
     |> assign(:site_count, length(sites))
     |> assign(:active_count, Enum.count(sites, &(&1.status == :active)))
     |> assign(
       :managed_system_count,
       Enum.reduce(sites, 0, fn site, total -> total + (site.managed_system_count || 0) end)
     )
     |> assign(
       :asset_count,
       Enum.reduce(sites, 0, fn site, total -> total + (site.asset_count || 0) end)
     )
     |> stream(:sites, sites)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.page class="pb-8">
      <.page_header eyebrow="Operations">
        Sites
        <:subtitle>
          Physical and digital operating locations where systems live and service work actually happens.
        </:subtitle>
        <:actions>
          <.button navigate={~p"/operations/organizations"}>
            <.icon name="hero-building-office-2" class="size-4" /> Organizations
          </.button>
          <.button navigate={~p"/operations/sites/new"} variant="primary">
            <.icon name="hero-plus" class="size-4" /> New Site
          </.button>
        </:actions>
      </.page_header>

      <div class="grid gap-4 md:grid-cols-4">
        <.stat_card
          title="Sites"
          value={Integer.to_string(@site_count)}
          description="Facilities, campuses, offices, labs, and digital environments tracked explicitly."
          icon="hero-map-pin"
        />
        <.stat_card
          title="Active"
          value={Integer.to_string(@active_count)}
          description="Sites currently in the live delivery or support footprint."
          icon="hero-check-badge"
          accent="emerald"
        />
        <.stat_card
          title="Managed Systems"
          value={Integer.to_string(@managed_system_count)}
          description="Systems already anchored to one of these operating locations."
          icon="hero-circle-stack"
          accent="sky"
        />
        <.stat_card
          title="Assets"
          value={Integer.to_string(@asset_count)}
          description="Assets tied directly to the site context."
          icon="hero-cpu-chip"
          accent="rose"
        />
      </div>

      <.section
        title="Operating Locations"
        description="Sites give service, delivery, and asset records a durable place context instead of burying that information in free text."
        compact
        body_class="p-0"
      >
        <div :if={@site_count == 0} class="p-6 sm:p-7">
          <.empty_state
            icon="hero-map-pin"
            title="No sites yet"
            description="Create sites for plants, offices, labs, cloud environments, and other operating locations."
          >
            <:action>
              <.button navigate={~p"/operations/sites/new"} variant="primary">
                Create Site
              </.button>
            </:action>
          </.empty_state>
        </div>

        <div :if={@site_count > 0} class="overflow-x-auto">
          <table class="min-w-full divide-y divide-zinc-200 text-sm dark:divide-white/10">
            <thead class="bg-zinc-50 dark:bg-white/[0.03]">
              <tr>
                <th class="px-5 py-3 text-left font-medium text-zinc-500 dark:text-zinc-400">
                  Site
                </th>
                <th class="px-5 py-3 text-left font-medium text-zinc-500 dark:text-zinc-400">
                  Organization
                </th>
                <th class="px-5 py-3 text-left font-medium text-zinc-500 dark:text-zinc-400">
                  Location
                </th>
                <th class="px-5 py-3 text-left font-medium text-zinc-500 dark:text-zinc-400">
                  Status
                </th>
                <th class="px-5 py-3 text-left font-medium text-zinc-500 dark:text-zinc-400">
                  Footprint
                </th>
              </tr>
            </thead>
            <tbody
              id="sites"
              phx-update="stream"
              class="divide-y divide-zinc-200 dark:divide-white/10"
            >
              <tr :for={{dom_id, site} <- @streams.sites} id={dom_id}>
                <td class="px-5 py-4 align-top">
                  <div class="space-y-1">
                    <.link
                      navigate={~p"/operations/sites/#{site}"}
                      class="font-medium text-zinc-900 hover:text-emerald-600 dark:text-white"
                    >
                      {site.name}
                    </.link>
                    <p class="text-sm text-zinc-500 dark:text-zinc-400">
                      {site.code || "No site code"}
                    </p>
                  </div>
                </td>
                <td class="px-5 py-4 align-top text-zinc-600 dark:text-zinc-300">
                  {(site.organization && site.organization.name) || "-"}
                </td>
                <td class="px-5 py-4 align-top text-zinc-600 dark:text-zinc-300">
                  <div class="space-y-1">
                    <p>{format_atom(site.site_kind)}</p>
                    <p class="text-xs text-zinc-400 dark:text-zinc-500">
                      {location_label(site)}
                    </p>
                  </div>
                </td>
                <td class="px-5 py-4 align-top">
                  <.status_badge status={site.status_variant}>
                    {format_atom(site.status)}
                  </.status_badge>
                </td>
                <td class="px-5 py-4 align-top text-zinc-600 dark:text-zinc-300">
                  <div class="space-y-1">
                    <p>{site.managed_system_count || 0} systems</p>
                    <p class="text-xs text-zinc-400 dark:text-zinc-500">
                      {site.asset_count || 0} assets
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

  defp load_sites(actor) do
    case Operations.list_sites(
           actor: actor,
           query: [sort: [name: :asc]],
           load: [:status_variant, :managed_system_count, :asset_count, organization: []]
         ) do
      {:ok, sites} -> sites
      {:error, error} -> raise "failed to load sites: #{inspect(error)}"
    end
  end

  defp location_label(site) do
    [site.city, site.state, site.country_code]
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.join(", ")
    |> case do
      "" -> "No location set"
      label -> label
    end
  end
end
