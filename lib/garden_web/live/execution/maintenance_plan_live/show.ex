defmodule GnomeGardenWeb.Execution.MaintenancePlanLive.Show do
  use GnomeGardenWeb, :live_view

  import GnomeGardenWeb.Execution.Helpers

  alias GnomeGarden.Execution

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    maintenance_plan = load_maintenance_plan!(id, socket.assigns.current_user)

    {:ok,
     socket
     |> assign(:page_title, maintenance_plan.name)
     |> assign(:maintenance_plan, maintenance_plan)}
  end

  @impl true
  def handle_event("transition", %{"action" => action}, socket) do
    maintenance_plan = socket.assigns.maintenance_plan

    case transition_maintenance_plan(
           maintenance_plan,
           String.to_existing_atom(action),
           socket.assigns.current_user
         ) do
      {:ok, updated_maintenance_plan} ->
        {:noreply,
         socket
         |> assign(
           :maintenance_plan,
           load_maintenance_plan!(updated_maintenance_plan.id, socket.assigns.current_user)
         )
         |> put_flash(:info, "Maintenance plan updated")}

      {:error, error} ->
        {:noreply,
         put_flash(socket, :error, "Could not update maintenance plan: #{inspect(error)}")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.page class="pb-8">
      <.page_header eyebrow="Execution">
        {@maintenance_plan.name}
        <:subtitle>
          <span class="inline-flex items-center gap-2">
            <.status_badge status={@maintenance_plan.status_variant}>
              {format_atom(@maintenance_plan.status)}
            </.status_badge>
            <span class="text-zinc-400 dark:text-zinc-500">/</span>
            <span>{format_atom(@maintenance_plan.plan_type)}</span>
          </span>
        </:subtitle>
        <:actions>
          <.button navigate={~p"/execution/maintenance-plans"}>
            <.icon name="hero-arrow-left" class="size-4" /> Back
          </.button>
          <.button phx-click="transition" phx-value-action="generate_work_order">
            <.icon name="hero-wrench-screwdriver" class="size-4" /> Generate Work Order
          </.button>
          <.button navigate={~p"/execution/maintenance-plans/#{@maintenance_plan}/edit"}>
            <.icon name="hero-pencil-square" class="size-4" /> Edit
          </.button>
        </:actions>
      </.page_header>

      <.section
        title="Maintenance Plan Actions"
        description="Keep recurring service schedules explicit so generated work orders and maintenance history stay trustworthy."
      >
        <div class="flex flex-wrap gap-3">
          <.button
            :for={action <- maintenance_plan_actions(@maintenance_plan)}
            phx-click="transition"
            phx-value-action={action.action}
            variant={action.variant}
          >
            <.icon name={action.icon} class="size-4" /> {action.label}
          </.button>
        </div>
      </.section>

      <div class="grid gap-6 lg:grid-cols-2">
        <.section title="Plan Snapshot">
          <div class="grid gap-5 sm:grid-cols-2">
            <.property_item label="Plan Type" value={format_atom(@maintenance_plan.plan_type)} />
            <.property_item label="Priority" value={format_atom(@maintenance_plan.priority)} />
            <.property_item label="Interval" value={interval_label(@maintenance_plan)} />
            <.property_item label="Next Due" value={format_date(@maintenance_plan.next_due_on)} />
            <.property_item
              label="Last Completed"
              value={format_date(@maintenance_plan.last_completed_on)}
            />
            <.property_item
              label="Last Generated"
              value={format_date(@maintenance_plan.last_generated_due_on)}
            />
            <.property_item
              label="Lead Days"
              value={Integer.to_string(@maintenance_plan.generation_lead_days)}
            />
            <.property_item
              label="Auto Create Work Orders"
              value={if(@maintenance_plan.auto_create_work_orders, do: "Yes", else: "No")}
            />
            <.property_item
              label="Billable"
              value={if(@maintenance_plan.billable, do: "Yes", else: "No")}
            />
            <.property_item
              label="Estimated Minutes"
              value={integer_or_dash(@maintenance_plan.estimated_minutes)}
            />
          </div>
        </.section>

        <.section title="Operational Context">
          <div class="grid gap-5 sm:grid-cols-2">
            <.property_item
              label="Organization"
              value={(@maintenance_plan.organization && @maintenance_plan.organization.name) || "-"}
            />
            <.property_item
              label="Site"
              value={(@maintenance_plan.site && @maintenance_plan.site.name) || "-"}
            />
            <.property_item
              label="Managed System"
              value={
                (@maintenance_plan.managed_system && @maintenance_plan.managed_system.name) || "-"
              }
            />
            <.property_item
              label="Asset"
              value={(@maintenance_plan.asset && @maintenance_plan.asset.name) || "-"}
            />
            <.property_item
              label="Agreement"
              value={(@maintenance_plan.agreement && @maintenance_plan.agreement.name) || "-"}
            />
            <.property_item
              label="Work Orders"
              value={Integer.to_string(@maintenance_plan.work_order_count || 0)}
            />
          </div>
        </.section>
      </div>

      <.section :if={@maintenance_plan.description} title="Description">
        <p class="whitespace-pre-wrap text-sm leading-6 text-zinc-600 dark:text-zinc-300">
          {@maintenance_plan.description}
        </p>
      </.section>

      <.section :if={@maintenance_plan.notes} title="Notes">
        <p class="whitespace-pre-wrap text-sm leading-6 text-zinc-600 dark:text-zinc-300">
          {@maintenance_plan.notes}
        </p>
      </.section>

      <.section
        title="Generated Work Orders"
        description="Recurring schedules should leave an explicit execution trail through generated or manually linked work orders."
      >
        <div :if={Enum.empty?(@maintenance_plan.work_orders || [])}>
          <.empty_state
            icon="hero-wrench-screwdriver"
            title="No work orders yet"
            description="Generate a work order when the plan comes due, or let the automatic scheduler create it for you."
          />
        </div>

        <div :if={!Enum.empty?(@maintenance_plan.work_orders || [])} class="space-y-3">
          <.link
            :for={work_order <- @maintenance_plan.work_orders}
            navigate={~p"/execution/work-orders/#{work_order}"}
            class="flex items-center justify-between rounded-2xl border border-zinc-200 bg-zinc-50/70 px-4 py-4 transition hover:border-emerald-300 hover:bg-white dark:border-white/10 dark:bg-white/[0.03] dark:hover:border-emerald-400/40"
          >
            <div class="space-y-1">
              <p class="font-medium text-zinc-900 dark:text-white">{work_order.title}</p>
              <p class="text-sm text-zinc-500 dark:text-zinc-400">
                {work_order.reference_number || "No reference number"}
              </p>
            </div>
            <.status_badge status={work_order.status_variant}>
              {format_atom(work_order.status)}
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

  defp load_maintenance_plan!(id, actor) do
    case Execution.get_maintenance_plan(
           id,
           actor: actor,
           load: [
             :status_variant,
             :priority_variant,
             :work_order_count,
             organization: [],
             site: [],
             managed_system: [],
             asset: [],
             agreement: [],
             work_orders: [:status_variant]
           ]
         ) do
      {:ok, maintenance_plan} -> maintenance_plan
      {:error, error} -> raise "failed to load maintenance plan #{id}: #{inspect(error)}"
    end
  end

  defp interval_label(maintenance_plan) do
    "#{maintenance_plan.interval_value} #{maintenance_plan.interval_unit}"
  end

  defp integer_or_dash(nil), do: "-"
  defp integer_or_dash(value), do: Integer.to_string(value)

  defp maintenance_plan_actions(%{status: :active}) do
    [
      %{action: "suspend", label: "Suspend", icon: "hero-pause", variant: nil},
      %{action: "retire", label: "Retire", icon: "hero-archive-box", variant: nil}
    ]
  end

  defp maintenance_plan_actions(%{status: :suspended}) do
    [
      %{action: "activate", label: "Activate", icon: "hero-play", variant: "primary"},
      %{action: "retire", label: "Retire", icon: "hero-archive-box", variant: nil}
    ]
  end

  defp maintenance_plan_actions(%{status: :retired}) do
    [
      %{action: "reopen", label: "Reopen", icon: "hero-arrow-path", variant: "primary"}
    ]
  end

  defp maintenance_plan_actions(_maintenance_plan), do: []

  defp transition_maintenance_plan(maintenance_plan, :suspend, actor),
    do: Execution.suspend_maintenance_plan(maintenance_plan, actor: actor)

  defp transition_maintenance_plan(maintenance_plan, :activate, actor),
    do: Execution.activate_maintenance_plan(maintenance_plan, actor: actor)

  defp transition_maintenance_plan(maintenance_plan, :retire, actor),
    do: Execution.retire_maintenance_plan(maintenance_plan, actor: actor)

  defp transition_maintenance_plan(maintenance_plan, :reopen, actor),
    do: Execution.reopen_maintenance_plan(maintenance_plan, actor: actor)

  defp transition_maintenance_plan(maintenance_plan, :generate_work_order, actor),
    do: Execution.generate_maintenance_plan_work_order(maintenance_plan, actor: actor)
end
