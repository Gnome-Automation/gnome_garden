defmodule GnomeGardenWeb.Operations.AssetLive.Show do
  use GnomeGardenWeb, :live_view

  import GnomeGardenWeb.Operations.Helpers

  alias GnomeGarden.Operations

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    asset = load_asset!(id, socket.assigns.current_user)

    {:ok,
     socket
     |> assign(:page_title, asset.name)
     |> assign(:asset, asset)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.page class="pb-8">
      <.page_header eyebrow="Operations">
        {@asset.name}
        <:subtitle>
          <span class="inline-flex items-center gap-2">
            <.status_badge status={@asset.lifecycle_variant}>
              {format_atom(@asset.lifecycle_status)}
            </.status_badge>
            <span class="text-zinc-400 dark:text-zinc-500">/</span>
            <span>{@asset.asset_tag || "No asset tag"}</span>
          </span>
        </:subtitle>
        <:actions>
          <.button navigate={~p"/operations/assets"}>
            <.icon name="hero-arrow-left" class="size-4" /> Back
          </.button>
          <.button navigate={~p"/execution/maintenance-plans/new?asset_id=#{@asset.id}"}>
            <.icon name="hero-arrow-path" class="size-4" /> New Maintenance Plan
          </.button>
          <.button navigate={~p"/execution/work-orders/new?asset_id=#{@asset.id}"}>
            <.icon name="hero-wrench-screwdriver" class="size-4" /> New Work Order
          </.button>
          <.button navigate={~p"/operations/assets/new?parent_asset_id=#{@asset.id}"}>
            <.icon name="hero-squares-plus" class="size-4" /> Add Child Asset
          </.button>
          <.button navigate={~p"/operations/assets/#{@asset}/edit"}>
            <.icon name="hero-pencil-square" class="size-4" /> Edit
          </.button>
        </:actions>
      </.page_header>

      <div class="grid gap-6 lg:grid-cols-2">
        <.section title="Asset Profile">
          <div class="grid gap-5 sm:grid-cols-2">
            <.property_item label="Asset Type" value={format_atom(@asset.asset_type)} />
            <.property_item label="Delivery Mode" value={format_atom(@asset.delivery_mode)} />
            <.property_item label="Lifecycle" value={format_atom(@asset.lifecycle_status)} />
            <.property_item label="Criticality" value={format_atom(@asset.criticality)} />
            <.property_item label="Vendor" value={@asset.vendor || "-"} />
            <.property_item label="Model Number" value={@asset.model_number || "-"} />
            <.property_item label="Serial Number" value={@asset.serial_number || "-"} />
            <.property_item label="Installed On" value={format_date(@asset.installed_on)} />
            <.property_item
              label="Commissioned On"
              value={format_date(@asset.commissioned_on)}
            />
          </div>
        </.section>

        <.section title="Operational Context">
          <div class="grid gap-5 sm:grid-cols-2">
            <.property_item
              label="Organization"
              value={(@asset.organization && @asset.organization.name) || "-"}
            />
            <.property_item label="Site" value={(@asset.site && @asset.site.name) || "-"} />
            <.property_item
              label="Managed System"
              value={(@asset.managed_system && @asset.managed_system.name) || "-"}
            />
            <.property_item
              label="Parent Asset"
              value={(@asset.parent_asset && @asset.parent_asset.name) || "-"}
            />
            <.property_item
              label="Child Assets"
              value={Integer.to_string(@asset.child_asset_count || 0)}
            />
            <.property_item
              label="Maintenance Plans"
              value={Integer.to_string(@asset.maintenance_plan_count || 0)}
            />
            <.property_item
              label="Work Orders"
              value={Integer.to_string(@asset.work_order_count || 0)}
            />
          </div>
        </.section>
      </div>

      <.section :if={@asset.description} title="Description">
        <p class="whitespace-pre-wrap text-sm leading-6 text-zinc-600 dark:text-zinc-300">
          {@asset.description}
        </p>
      </.section>

      <.section :if={@asset.notes} title="Notes">
        <p class="whitespace-pre-wrap text-sm leading-6 text-zinc-600 dark:text-zinc-300">
          {@asset.notes}
        </p>
      </.section>

      <.section
        title="Maintenance Plans"
        description="Recurring schedules should stay attached to the asset they protect, not hidden in free-text notes or calendar reminders."
      >
        <div :if={Enum.empty?(@asset.maintenance_plans || [])}>
          <.empty_state
            icon="hero-arrow-path"
            title="No maintenance plans yet"
            description="Create preventive schedules here when this asset needs inspections, calibration, patching, or recurring service."
          >
            <:action>
              <.button navigate={~p"/execution/maintenance-plans/new?asset_id=#{@asset.id}"}>
                Create Maintenance Plan
              </.button>
            </:action>
          </.empty_state>
        </div>

        <div :if={!Enum.empty?(@asset.maintenance_plans || [])} class="space-y-3">
          <.link
            :for={maintenance_plan <- @asset.maintenance_plans}
            navigate={~p"/execution/maintenance-plans/#{maintenance_plan}"}
            class="flex items-center justify-between rounded-2xl border border-zinc-200 bg-zinc-50/70 px-4 py-4 transition hover:border-emerald-300 hover:bg-white dark:border-white/10 dark:bg-white/[0.03] dark:hover:border-emerald-400/40"
          >
            <div class="space-y-1">
              <p class="font-medium text-zinc-900 dark:text-white">{maintenance_plan.name}</p>
              <p class="text-sm text-zinc-500 dark:text-zinc-400">
                {format_atom(maintenance_plan.plan_type)}
              </p>
            </div>
            <div class="text-right">
              <.status_badge status={maintenance_plan.status_variant}>
                {format_atom(maintenance_plan.status)}
              </.status_badge>
            </div>
          </.link>
        </div>
      </.section>

      <.section
        title="Child Assets"
        description="Use hierarchy when an asset contains smaller managed components that also need service history."
      >
        <div :if={Enum.empty?(@asset.child_assets || [])}>
          <.empty_state
            icon="hero-squares-plus"
            title="No child assets yet"
            description="Add child assets when this asset contains distinct subcomponents that should be tracked separately."
          />
        </div>

        <div :if={!Enum.empty?(@asset.child_assets || [])} class="space-y-3">
          <.link
            :for={child <- @asset.child_assets}
            navigate={~p"/operations/assets/#{child}"}
            class="flex items-center justify-between rounded-2xl border border-zinc-200 bg-zinc-50/70 px-4 py-4 transition hover:border-emerald-300 hover:bg-white dark:border-white/10 dark:bg-white/[0.03] dark:hover:border-emerald-400/40"
          >
            <div class="space-y-1">
              <p class="font-medium text-zinc-900 dark:text-white">{child.name}</p>
              <p class="text-sm text-zinc-500 dark:text-zinc-400">
                {child.asset_tag || "No asset tag"}
              </p>
            </div>
            <.status_badge status={child.lifecycle_variant}>
              {format_atom(child.lifecycle_status)}
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
      <p class="text-xs font-semibold uppercase tracking-[0.2em] text-zinc-400 dark:text-zinc-500">
        {@label}
      </p>
      <p class="text-sm font-medium text-zinc-900 dark:text-white">{@value}</p>
    </div>
    """
  end

  defp load_asset!(id, actor) do
    case Operations.get_asset(
           id,
           actor: actor,
           load: [
             :lifecycle_variant,
             :criticality_variant,
             :child_asset_count,
             :maintenance_plan_count,
             :work_order_count,
             organization: [],
             site: [],
             managed_system: [],
             parent_asset: [],
             child_assets: [:lifecycle_variant],
             maintenance_plans: [:status_variant, :priority_variant]
           ]
         ) do
      {:ok, asset} -> asset
      {:error, error} -> raise "failed to load asset #{id}: #{inspect(error)}"
    end
  end
end
