defmodule GnomeGardenWeb.Execution.MaintenancePlanLive.Index do
  use GnomeGardenWeb, :live_view
  use Cinder.UrlSync

  import GnomeGardenWeb.Execution.Helpers

  alias GnomeGarden.Execution

  @impl true
  def mount(_params, _session, socket) do
    counts = load_counts(socket.assigns.current_user)

    {:ok,
     socket
     |> assign(:page_title, "Maintenance Plans")
     |> assign(:plan_count, counts.total)
     |> assign(:active_count, counts.active)
     |> assign(:auto_count, counts.auto)
     |> assign(:due_soon_count, counts.due_soon)}
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
      <.page_header eyebrow="Execution">
        Maintenance Plans
        <:subtitle>
          Preventive schedules that turn the installed base into recurring, traceable service work instead of one-off memory.
        </:subtitle>
        <:actions>
          <.button navigate={~p"/operations/assets"}>
            Assets
          </.button>
          <.button navigate={~p"/execution/maintenance-plans/new"} variant="primary">
            New Maintenance Plan
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

      <Cinder.collection
        id="maintenance-plans-table"
        resource={GnomeGarden.Execution.MaintenancePlan}
        actor={@current_user}
        url_state={@url_state}
        theme={GnomeGardenWeb.CinderTheme}
        page_size={25}
        query_opts={[
          load: [
            :status_variant,
            :priority_variant,
            :is_due_soon,
            :due_status_variant,
            :due_status_label,
            :work_order_count,
            asset: [],
            managed_system: []
          ]
        ]}
        click={fn row -> JS.navigate(~p"/execution/maintenance-plans/#{row}") end}
      >
        <:col :let={plan} field="name" search sort label="Plan">
          <div class="space-y-1">
            <div class="font-medium text-base-content">{plan.name}</div>
            <p class="text-sm text-base-content/50">
              {format_atom(plan.plan_type)}
            </p>
          </div>
        </:col>

        <:col :let={plan} label="Asset">
          <div class="space-y-1">
            <p>{(plan.asset && plan.asset.name) || "-"}</p>
            <p class="text-xs text-base-content/40">
              {(plan.managed_system && plan.managed_system.name) || "No managed system"}
            </p>
          </div>
        </:col>

        <:col :let={plan} label="Interval">
          <div class="space-y-1">
            <p>{interval_label(plan)}</p>
            <p class="text-xs text-base-content/40">
              {plan.work_order_count || 0} work orders
            </p>
          </div>
        </:col>

        <:col :let={plan} field="status" sort label="Status">
          <div class="space-y-1">
            <.status_badge status={plan.status_variant}>
              {format_atom(plan.status)}
            </.status_badge>
            <.status_badge status={plan.priority_variant}>
              {format_atom(plan.priority)}
            </.status_badge>
          </div>
        </:col>

        <:col :let={plan} field="next_due_on" sort label="Next Due">
          <div class="space-y-1">
            <p>{format_date(plan.next_due_on)}</p>
            <.status_badge status={plan.due_status_variant}>
              {plan.due_status_label}
            </.status_badge>
            <p class="text-xs text-base-content/40">
              {if plan.auto_create_work_orders, do: "Auto work order", else: "Manual generation"}
            </p>
          </div>
        </:col>

        <:empty>
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
        </:empty>
      </Cinder.collection>
    </.page>
    """
  end

  defp load_counts(actor) do
    case Execution.list_maintenance_plans(actor: actor, load: [:is_due_soon]) do
      {:ok, plans} ->
        %{
          total: length(plans),
          active: Enum.count(plans, &(&1.status == :active)),
          auto: Enum.count(plans, & &1.auto_create_work_orders),
          due_soon: Enum.count(plans, & &1.is_due_soon)
        }

      {:error, _} ->
        %{total: 0, active: 0, auto: 0, due_soon: 0}
    end
  end

  defp interval_label(maintenance_plan) do
    "#{maintenance_plan.interval_value} #{maintenance_plan.interval_unit}"
  end
end
