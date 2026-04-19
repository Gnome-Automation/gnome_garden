defmodule GnomeGardenWeb.Execution.MaintenancePlanLive.Index do
  use GnomeGardenWeb, :live_view

  import GnomeGardenWeb.Execution.Helpers

  alias GnomeGarden.Execution

  @impl true
  def mount(_params, _session, socket) do
    maintenance_plans = load_maintenance_plans(socket.assigns.current_user)

    {:ok,
     socket
     |> assign(:page_title, "Maintenance Plans")
     |> assign(:plan_count, length(maintenance_plans))
     |> assign(:active_count, Enum.count(maintenance_plans, &(&1.status == :active)))
     |> assign(:auto_count, Enum.count(maintenance_plans, & &1.auto_create_work_orders))
     |> assign(:due_soon_count, Enum.count(maintenance_plans, &due_soon?(&1.next_due_on)))
     |> stream(:maintenance_plans, maintenance_plans)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.page class="pb-8">
      <.page_header eyebrow="Execution">
        Maintenance Plans
        <:subtitle>
          Preventive schedules that turn the installed base into recurring, traceable service work instead of one-off memory.
        </:subtitle>
        <:actions>
          <.button navigate={~p"/operations/assets"}>
            <.icon name="hero-cpu-chip" class="size-4" /> Assets
          </.button>
          <.button navigate={~p"/execution/maintenance-plans/new"} variant="primary">
            <.icon name="hero-plus" class="size-4" /> New Maintenance Plan
          </.button>
        </:actions>
      </.page_header>

      <div class="grid gap-4 md:grid-cols-4">
        <.stat_card
          title="Plans"
          value={Integer.to_string(@plan_count)}
          description="Recurring maintenance schedules tied to real assets and customer contexts."
          icon="hero-arrow-path"
        />
        <.stat_card
          title="Active"
          value={Integer.to_string(@active_count)}
          description="Plans currently driving recurring service expectations."
          icon="hero-check-badge"
          accent="emerald"
        />
        <.stat_card
          title="Auto Generate"
          value={Integer.to_string(@auto_count)}
          description="Plans configured to create work orders automatically through AshOban."
          icon="hero-bolt"
          accent="sky"
        />
        <.stat_card
          title="Due Soon"
          value={Integer.to_string(@due_soon_count)}
          description="Plans whose next due date is close enough to need operational attention."
          icon="hero-clock"
          accent="amber"
        />
      </div>

      <.section
        title="Preventive Schedule Register"
        description="Recurring plans keep preventive work visible and auditable instead of relying on tribal memory."
        compact
        body_class="p-0"
      >
        <div :if={@plan_count == 0} class="p-6 sm:p-7">
          <.empty_state
            icon="hero-arrow-path"
            title="No maintenance plans yet"
            description="Create schedules for inspections, calibrations, patching, backups, and other recurring work."
          >
            <:action>
              <.button navigate={~p"/execution/maintenance-plans/new"} variant="primary">
                Create Maintenance Plan
              </.button>
            </:action>
          </.empty_state>
        </div>

        <div :if={@plan_count > 0} class="overflow-x-auto">
          <table class="min-w-full divide-y divide-zinc-200 text-sm dark:divide-white/10">
            <thead class="bg-zinc-50 dark:bg-white/[0.03]">
              <tr>
                <th class="px-5 py-3 text-left font-medium text-zinc-500 dark:text-zinc-400">
                  Plan
                </th>
                <th class="px-5 py-3 text-left font-medium text-zinc-500 dark:text-zinc-400">
                  Asset
                </th>
                <th class="px-5 py-3 text-left font-medium text-zinc-500 dark:text-zinc-400">
                  Interval
                </th>
                <th class="px-5 py-3 text-left font-medium text-zinc-500 dark:text-zinc-400">
                  Status
                </th>
                <th class="px-5 py-3 text-left font-medium text-zinc-500 dark:text-zinc-400">
                  Next Due
                </th>
              </tr>
            </thead>
            <tbody
              id="maintenance-plans"
              phx-update="stream"
              class="divide-y divide-zinc-200 dark:divide-white/10"
            >
              <tr :for={{dom_id, maintenance_plan} <- @streams.maintenance_plans} id={dom_id}>
                <td class="px-5 py-4 align-top">
                  <div class="space-y-1">
                    <.link
                      navigate={~p"/execution/maintenance-plans/#{maintenance_plan}"}
                      class="font-medium text-zinc-900 hover:text-emerald-600 dark:text-white"
                    >
                      {maintenance_plan.name}
                    </.link>
                    <p class="text-sm text-zinc-500 dark:text-zinc-400">
                      {format_atom(maintenance_plan.plan_type)}
                    </p>
                  </div>
                </td>
                <td class="px-5 py-4 align-top text-zinc-600 dark:text-zinc-300">
                  <div class="space-y-1">
                    <p>{(maintenance_plan.asset && maintenance_plan.asset.name) || "-"}</p>
                    <p class="text-xs text-zinc-400 dark:text-zinc-500">
                      {(maintenance_plan.managed_system && maintenance_plan.managed_system.name) ||
                        "No managed system"}
                    </p>
                  </div>
                </td>
                <td class="px-5 py-4 align-top text-zinc-600 dark:text-zinc-300">
                  <div class="space-y-1">
                    <p>{interval_label(maintenance_plan)}</p>
                    <p class="text-xs text-zinc-400 dark:text-zinc-500">
                      {maintenance_plan.work_order_count || 0} work orders
                    </p>
                  </div>
                </td>
                <td class="px-5 py-4 align-top">
                  <div class="space-y-1">
                    <.status_badge status={maintenance_plan.status_variant}>
                      {format_atom(maintenance_plan.status)}
                    </.status_badge>
                    <.status_badge status={maintenance_plan.priority_variant}>
                      {format_atom(maintenance_plan.priority)}
                    </.status_badge>
                  </div>
                </td>
                <td class="px-5 py-4 align-top text-zinc-600 dark:text-zinc-300">
                  <div class="space-y-1">
                    <p>{format_date(maintenance_plan.next_due_on)}</p>
                    <p class="text-xs text-zinc-400 dark:text-zinc-500">
                      {if maintenance_plan.auto_create_work_orders,
                        do: "Auto work order",
                        else: "Manual generation"}
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

  defp load_maintenance_plans(actor) do
    case Execution.list_maintenance_plans(
           actor: actor,
           query: [sort: [next_due_on: :asc, inserted_at: :asc]],
           load: [
             :status_variant,
             :priority_variant,
             :work_order_count,
             asset: [],
             managed_system: []
           ]
         ) do
      {:ok, maintenance_plans} -> maintenance_plans
      {:error, error} -> raise "failed to load maintenance plans: #{inspect(error)}"
    end
  end

  defp interval_label(maintenance_plan) do
    "#{maintenance_plan.interval_value} #{maintenance_plan.interval_unit}"
  end

  defp due_soon?(nil), do: false
  defp due_soon?(%Date{} = date), do: Date.diff(date, Date.utc_today()) <= 30
end
