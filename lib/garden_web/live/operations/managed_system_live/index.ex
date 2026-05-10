defmodule GnomeGardenWeb.Operations.ManagedSystemLive.Index do
  use GnomeGardenWeb, :live_view
  use Cinder.UrlSync

  import GnomeGardenWeb.Operations.Helpers

  alias GnomeGarden.Operations

  @impl true
  def mount(_params, _session, socket) do
    counts = load_counts(socket.assigns.current_user)

    {:ok,
     socket
     |> assign(:page_title, "Managed Systems")
     |> assign(:system_count, counts.total)
     |> assign(:active_count, counts.active)
     |> assign(:critical_count, counts.critical)
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
        Managed Systems
        <:subtitle>
          Automation stacks, applications, integrations, and hybrid installations that sit between sites and assets.
        </:subtitle>
        <:actions>
          <.button navigate={~p"/operations/sites"}>
            Sites
          </.button>
          <.button navigate={~p"/operations/managed-systems/new"} variant="primary">
            New Managed System
          </.button>
        </:actions>
      </.page_header>

      <div class="grid gap-4 md:grid-cols-4">
        <.stat_card
          title="Managed Systems"
          value={Integer.to_string(@system_count)}
          description="Named system contexts that delivery, support, and assets can attach to."
          icon="hero-circle-stack"
        />
        <.stat_card
          title="Active"
          value={Integer.to_string(@active_count)}
          description="Systems currently in the live supported or delivered estate."
          icon="hero-check-badge"
          accent="emerald"
        />
        <.stat_card
          title="Critical"
          value={Integer.to_string(@critical_count)}
          description="Systems whose failure would carry high operational risk."
          icon="hero-exclamation-triangle"
          accent="amber"
        />
        <.stat_card
          title="Assets"
          value={Integer.to_string(@asset_count)}
          description="Assets already grouped under a managed system context."
          icon="hero-cpu-chip"
          accent="rose"
        />
      </div>

      <Cinder.collection
        id="managed-systems-table"
        resource={GnomeGarden.Operations.ManagedSystem}
        actor={@current_user}
        url_state={@url_state}
        theme={GnomeGardenWeb.CinderTheme}
        page_size={25}
        query_opts={[
          load: [
            :lifecycle_variant,
            :criticality_variant,
            :asset_count,
            organization: [],
            site: []
          ]
        ]}
        click={fn row -> JS.navigate(~p"/operations/managed-systems/#{row}") end}
      >
        <:col :let={managed_system} field="name" sort search label="Managed System">
          <div class="space-y-0.5">
            <div class="font-medium text-base-content">{managed_system.name}</div>
            <div class="text-xs text-base-content/50">
              {managed_system.code || "No system code"}
            </div>
          </div>
        </:col>

        <:col :let={managed_system} field="organization.name" sort search label="Organization">
          {(managed_system.organization && managed_system.organization.name) || "-"}
        </:col>

        <:col :let={managed_system} field="site.name" sort search label="Site">
          <div class="space-y-0.5">
            <p>{(managed_system.site && managed_system.site.name) || "-"}</p>
            <p class="text-xs text-base-content/40">
              {format_atom(managed_system.system_type)}
            </p>
          </div>
        </:col>

        <:col :let={managed_system} field="lifecycle_status" sort label="Lifecycle">
          <.status_badge status={managed_system.lifecycle_variant}>
            {format_atom(managed_system.lifecycle_status)}
          </.status_badge>
        </:col>

        <:col :let={managed_system} field="criticality" sort label="Criticality">
          <div class="space-y-0.5">
            <.status_badge status={managed_system.criticality_variant}>
              {format_atom(managed_system.criticality)}
            </.status_badge>
            <p class="text-xs text-base-content/40">
              {managed_system.asset_count || 0} assets
            </p>
          </div>
        </:col>

        <:empty>
          <.empty_state
            icon="hero-circle-stack"
            title="No managed systems yet"
            description="Create managed systems for the major automation, application, or integration stacks you build and support."
          >
            <:action>
              <.button navigate={~p"/operations/managed-systems/new"} variant="primary">
                Create Managed System
              </.button>
            </:action>
          </.empty_state>
        </:empty>
      </Cinder.collection>
    </.page>
    """
  end

  defp load_counts(actor) do
    case Operations.list_managed_systems(actor: actor, load: [:asset_count]) do
      {:ok, systems} ->
        %{
          total: length(systems),
          active: Enum.count(systems, &(&1.lifecycle_status == :active)),
          critical: Enum.count(systems, &(&1.criticality == :critical)),
          assets:
            Enum.reduce(systems, 0, fn system, total -> total + (system.asset_count || 0) end)
        }

      {:error, _} ->
        %{total: 0, active: 0, critical: 0, assets: 0}
    end
  end
end
