defmodule GnomeGardenWeb.Operations.AssetLive.Index do
  use GnomeGardenWeb, :live_view
  use Cinder.UrlSync

  import GnomeGardenWeb.Operations.Helpers

  alias GnomeGarden.Operations

  @impl true
  def mount(_params, _session, socket) do
    counts = load_counts(socket.assigns.current_user)

    {:ok,
     socket
     |> assign(:page_title, "Assets")
     |> assign(:asset_count, counts.total)
     |> assign(:active_count, counts.active)
     |> assign(:critical_count, counts.critical)
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
      <.page_header eyebrow="Operations">
        Assets
        <:subtitle>
          Track the physical, digital, and hybrid equipment that service and delivery work actually happens against.
        </:subtitle>
        <:actions>
          <.button navigate={~p"/operations/organizations"}>
            Organizations
          </.button>
          <.button navigate={~p"/operations/assets/new"} variant="primary">
            New Asset
          </.button>
        </:actions>
      </.page_header>

      <div class="grid gap-4 md:grid-cols-4">
        <.stat_card
          title="Assets"
          value={Integer.to_string(@asset_count)}
          description="Installed or managed components tied to service history and maintenance."
          icon="hero-cpu-chip"
        />
        <.stat_card
          title="Active"
          value={Integer.to_string(@active_count)}
          description="Assets currently in a live supported lifecycle."
          icon="hero-check-badge"
          accent="emerald"
        />
        <.stat_card
          title="Critical"
          value={Integer.to_string(@critical_count)}
          description="Assets whose failure would meaningfully affect delivery or support outcomes."
          icon="hero-exclamation-triangle"
          accent="amber"
        />
        <.stat_card
          title="Work Orders"
          value={Integer.to_string(@work_order_count)}
          description="Historical execution records already tied back to these assets."
          icon="hero-wrench-screwdriver"
          accent="rose"
        />
      </div>

      <Cinder.collection
        id="assets-table"
        resource={GnomeGarden.Operations.Asset}
        actor={@current_user}
        url_state={@url_state}
        theme={GnomeGardenWeb.CinderTheme}
        page_size={25}
        query_opts={[
          load: [
            :lifecycle_variant,
            :criticality_variant,
            :work_order_count,
            organization: [],
            site: [],
            managed_system: []
          ]
        ]}
        click={fn row -> JS.navigate(~p"/operations/assets/#{row}") end}
      >
        <:col :let={asset} field="name" sort search label="Asset">
          <div class="space-y-0.5">
            <div class="font-medium text-base-content">{asset.name}</div>
            <div class="text-xs text-base-content/50">
              {asset.asset_tag || "No asset tag"}
            </div>
          </div>
        </:col>

        <:col :let={asset} field="organization.name" sort search label="Context">
          <div class="space-y-0.5">
            <p>{(asset.organization && asset.organization.name) || "-"}</p>
            <p class="text-xs text-base-content/40">
              {(asset.site && asset.site.name) ||
                (asset.managed_system && asset.managed_system.name) ||
                "No site/system"}
            </p>
          </div>
        </:col>

        <:col :let={asset} field="asset_type" sort label="Type">
          <div class="space-y-0.5">
            <p>{format_atom(asset.asset_type)}</p>
            <p class="text-xs text-base-content/40">
              {format_atom(asset.delivery_mode)}
            </p>
          </div>
        </:col>

        <:col :let={asset} field="lifecycle_status" sort label="Lifecycle">
          <.status_badge status={asset.lifecycle_variant}>
            {format_atom(asset.lifecycle_status)}
          </.status_badge>
        </:col>

        <:col :let={asset} field="criticality" sort label="Criticality">
          <div class="space-y-0.5">
            <.status_badge status={asset.criticality_variant}>
              {format_atom(asset.criticality)}
            </.status_badge>
            <p class="text-xs text-base-content/40">
              {asset.work_order_count || 0} work orders
            </p>
          </div>
        </:col>

        <:empty>
          <.empty_state
            icon="hero-cpu-chip"
            title="No assets yet"
            description="Create assets for panels, controllers, servers, applications, and other managed components."
          >
            <:action>
              <.button navigate={~p"/operations/assets/new"} variant="primary">
                Create Asset
              </.button>
            </:action>
          </.empty_state>
        </:empty>
      </Cinder.collection>
    </.page>
    """
  end

  defp load_counts(actor) do
    case Operations.list_assets(actor: actor, load: [:work_order_count]) do
      {:ok, assets} ->
        %{
          total: length(assets),
          active: Enum.count(assets, &(&1.lifecycle_status == :active)),
          critical: Enum.count(assets, &(&1.criticality == :critical)),
          work_orders:
            Enum.reduce(assets, 0, fn asset, total -> total + (asset.work_order_count || 0) end)
        }

      {:error, _} ->
        %{total: 0, active: 0, critical: 0, work_orders: 0}
    end
  end
end
