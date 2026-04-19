defmodule GnomeGardenWeb.Operations.AssetLive.Index do
  use GnomeGardenWeb, :live_view

  import GnomeGardenWeb.Operations.Helpers

  alias GnomeGarden.Operations

  @impl true
  def mount(_params, _session, socket) do
    assets = load_assets(socket.assigns.current_user)

    {:ok,
     socket
     |> assign(:page_title, "Assets")
     |> assign(:asset_count, length(assets))
     |> assign(:active_count, Enum.count(assets, &(&1.lifecycle_status == :active)))
     |> assign(:critical_count, Enum.count(assets, &(&1.criticality == :critical)))
     |> assign(
       :work_order_count,
       Enum.reduce(assets, 0, fn asset, total -> total + (asset.work_order_count || 0) end)
     )
     |> stream(:assets, assets)}
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
            <.icon name="hero-building-office-2" class="size-4" /> Organizations
          </.button>
          <.button navigate={~p"/operations/assets/new"} variant="primary">
            <.icon name="hero-plus" class="size-4" /> New Asset
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

      <.section
        title="Installed Base"
        description="Assets anchor the CMMS side of the platform so work orders and maintenance plans target real systems."
        compact
        body_class="p-0"
      >
        <div :if={@asset_count == 0} class="p-6 sm:p-7">
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
        </div>

        <div :if={@asset_count > 0} class="overflow-x-auto">
          <table class="min-w-full divide-y divide-zinc-200 text-sm dark:divide-white/10">
            <thead class="bg-zinc-50 dark:bg-white/[0.03]">
              <tr>
                <th class="px-5 py-3 text-left font-medium text-zinc-500 dark:text-zinc-400">
                  Asset
                </th>
                <th class="px-5 py-3 text-left font-medium text-zinc-500 dark:text-zinc-400">
                  Context
                </th>
                <th class="px-5 py-3 text-left font-medium text-zinc-500 dark:text-zinc-400">
                  Type
                </th>
                <th class="px-5 py-3 text-left font-medium text-zinc-500 dark:text-zinc-400">
                  Lifecycle
                </th>
                <th class="px-5 py-3 text-left font-medium text-zinc-500 dark:text-zinc-400">
                  Criticality
                </th>
              </tr>
            </thead>
            <tbody
              id="assets"
              phx-update="stream"
              class="divide-y divide-zinc-200 dark:divide-white/10"
            >
              <tr :for={{dom_id, asset} <- @streams.assets} id={dom_id}>
                <td class="px-5 py-4 align-top">
                  <div class="space-y-1">
                    <.link
                      navigate={~p"/operations/assets/#{asset}"}
                      class="font-medium text-zinc-900 hover:text-emerald-600 dark:text-white"
                    >
                      {asset.name}
                    </.link>
                    <p class="text-sm text-zinc-500 dark:text-zinc-400">
                      {asset.asset_tag || "No asset tag"}
                    </p>
                  </div>
                </td>
                <td class="px-5 py-4 align-top text-zinc-600 dark:text-zinc-300">
                  <div class="space-y-1">
                    <p>{(asset.organization && asset.organization.name) || "-"}</p>
                    <p class="text-xs text-zinc-400 dark:text-zinc-500">
                      {(asset.site && asset.site.name) ||
                        (asset.managed_system && asset.managed_system.name) ||
                        "No site/system"}
                    </p>
                  </div>
                </td>
                <td class="px-5 py-4 align-top text-zinc-600 dark:text-zinc-300">
                  <div class="space-y-1">
                    <p>{format_atom(asset.asset_type)}</p>
                    <p class="text-xs text-zinc-400 dark:text-zinc-500">
                      {format_atom(asset.delivery_mode)}
                    </p>
                  </div>
                </td>
                <td class="px-5 py-4 align-top">
                  <.status_badge status={asset.lifecycle_variant}>
                    {format_atom(asset.lifecycle_status)}
                  </.status_badge>
                </td>
                <td class="px-5 py-4 align-top">
                  <div class="space-y-1">
                    <.status_badge status={asset.criticality_variant}>
                      {format_atom(asset.criticality)}
                    </.status_badge>
                    <p class="text-xs text-zinc-400 dark:text-zinc-500">
                      {asset.work_order_count || 0} work orders
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

  defp load_assets(actor) do
    case Operations.list_assets(
           actor: actor,
           query: [sort: [name: :asc]],
           load: [
             :lifecycle_variant,
             :criticality_variant,
             :work_order_count,
             organization: [],
             site: [],
             managed_system: []
           ]
         ) do
      {:ok, assets} -> assets
      {:error, error} -> raise "failed to load assets: #{inspect(error)}"
    end
  end
end
