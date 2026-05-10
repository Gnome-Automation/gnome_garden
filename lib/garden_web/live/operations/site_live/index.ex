defmodule GnomeGardenWeb.Operations.SiteLive.Index do
  use GnomeGardenWeb, :live_view
  use Cinder.UrlSync

  import GnomeGardenWeb.Operations.Helpers

  alias GnomeGarden.Operations

  @impl true
  def mount(_params, _session, socket) do
    counts = load_counts(socket.assigns.current_user)

    {:ok,
     socket
     |> assign(:page_title, "Sites")
     |> assign(:site_count, counts.total)
     |> assign(:active_count, counts.active)
     |> assign(:managed_system_count, counts.managed_systems)
     |> assign(:asset_count, counts.assets)}
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
      <.page_header eyebrow="Operations">
        Sites
        <:subtitle>
          Physical and digital operating locations where systems live and service work actually happens.
        </:subtitle>
        <:actions>
          <.button navigate={~p"/operations/organizations"}>
            Organizations
          </.button>
          <.button navigate={~p"/operations/sites/new"} variant="primary">
            New Site
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

      <Cinder.collection
        id="sites-table"
        resource={GnomeGarden.Operations.Site}
        actor={@current_user}
        url_state={@url_state}
        theme={GnomeGardenWeb.CinderTheme}
        page_size={25}
        query_opts={[
          load: [:status_variant, :managed_system_count, :asset_count, organization: []]
        ]}
        click={fn row -> JS.navigate(~p"/operations/sites/#{row}") end}
      >
        <:col :let={site} field="name" sort search label="Site">
          <div class="space-y-0.5">
            <div class="font-medium text-base-content">{site.name}</div>
            <div class="text-xs text-base-content/50">
              {site.code || "No site code"}
            </div>
          </div>
        </:col>

        <:col :let={site} field="organization.name" sort search label="Organization">
          {(site.organization && site.organization.name) || "-"}
        </:col>

        <:col :let={site} field="site_kind" sort label="Location">
          <div class="space-y-0.5">
            <p>{format_atom(site.site_kind)}</p>
            <p class="text-xs text-base-content/40">
              {location_label(site)}
            </p>
          </div>
        </:col>

        <:col :let={site} field="status" sort label="Status">
          <.status_badge status={site.status_variant}>
            {format_atom(site.status)}
          </.status_badge>
        </:col>

        <:col :let={site} label="Footprint">
          <div class="space-y-0.5">
            <p>{site.managed_system_count || 0} systems</p>
            <p class="text-xs text-base-content/40">
              {site.asset_count || 0} assets
            </p>
          </div>
        </:col>

        <:empty>
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
        </:empty>
      </Cinder.collection>
    </.page>
    """
  end

  defp load_counts(actor) do
    case Operations.list_sites(
           actor: actor,
           load: [:managed_system_count, :asset_count]
         ) do
      {:ok, sites} ->
        %{
          total: length(sites),
          active: Enum.count(sites, &(&1.status == :active)),
          managed_systems:
            Enum.reduce(sites, 0, fn site, total -> total + (site.managed_system_count || 0) end),
          assets: Enum.reduce(sites, 0, fn site, total -> total + (site.asset_count || 0) end)
        }

      {:error, _} ->
        %{total: 0, active: 0, managed_systems: 0, assets: 0}
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
