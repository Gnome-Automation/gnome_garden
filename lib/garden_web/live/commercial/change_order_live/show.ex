defmodule GnomeGardenWeb.Commercial.ChangeOrderLive.Show do
  use GnomeGardenWeb, :live_view

  import GnomeGardenWeb.Commercial.Helpers

  alias GnomeGarden.Commercial

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    change_order = load_change_order!(id, socket.assigns.current_user)

    {:ok,
     socket
     |> assign(:page_title, change_order.title)
     |> assign(:change_order, change_order)}
  end

  @impl true
  def handle_event("transition", %{"action" => action}, socket) do
    change_order = socket.assigns.change_order

    case transition_change_order(
           change_order,
           String.to_existing_atom(action),
           socket.assigns.current_user
         ) do
      {:ok, updated_change_order} ->
        {:noreply,
         socket
         |> assign(
           :change_order,
           load_change_order!(updated_change_order.id, socket.assigns.current_user)
         )
         |> put_flash(:info, "Change order updated")}

      {:error, error} ->
        {:noreply, put_flash(socket, :error, "Could not update change order: #{inspect(error)}")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.page class="pb-8">
      <.page_header eyebrow="Commercial">
        {@change_order.title}
        <:subtitle>
          <span class="inline-flex items-center gap-2">
            <.status_badge status={@change_order.status_variant}>
              {format_atom(@change_order.status)}
            </.status_badge>
            <span class="text-base-content/40">/</span>
            <span>{@change_order.change_order_number}</span>
          </span>
        </:subtitle>
        <:actions>
          <.button navigate={~p"/commercial/change-orders"}>
            Back
          </.button>
          <.button navigate={~p"/commercial/change-orders/#{@change_order}/edit"}>
            Edit
          </.button>
        </:actions>
      </.page_header>

      <.section
        title="Change Order Actions"
        description="Drive post-award scope changes through explicit review and implementation states."
      >
        <div class="flex flex-wrap gap-3">
          <.button
            :for={action <- change_order_actions(@change_order)}
            phx-click="transition"
            phx-value-action={action.action}
            variant={action.variant}
          >
            <.icon name={action.icon} class="size-4" /> {action.label}
          </.button>
        </div>
      </.section>

      <div class="grid gap-6 lg:grid-cols-2">
        <.section title="Commercial Snapshot">
          <div class="grid gap-5 sm:grid-cols-2">
            <.property_item label="Change Type" value={format_atom(@change_order.change_type)} />
            <.property_item label="Pricing Model" value={format_atom(@change_order.pricing_model)} />
            <.property_item label="Requested On" value={format_date(@change_order.requested_on)} />
            <.property_item label="Approved On" value={format_date(@change_order.approved_on)} />
            <.property_item label="Implemented On" value={format_date(@change_order.implemented_on)} />
            <.property_item label="Effective On" value={format_date(@change_order.effective_on)} />
          </div>
        </.section>

        <.section title="Operational Context">
          <div class="grid gap-5 sm:grid-cols-2">
            <.property_item
              label="Agreement"
              value={(@change_order.agreement && @change_order.agreement.name) || "-"}
            />
            <.property_item
              label="Project"
              value={(@change_order.project && @change_order.project.name) || "-"}
            />
            <.property_item
              label="Organization"
              value={(@change_order.organization && @change_order.organization.name) || "-"}
            />
            <.property_item
              label="Schedule Impact"
              value={schedule_impact(@change_order.schedule_impact_days)}
            />
            <.property_item label="Lines" value={Integer.to_string(@change_order.line_count || 0)} />
            <.property_item label="Total Amount" value={format_amount(@change_order.total_amount)} />
          </div>
        </.section>
      </div>

      <.section :if={@change_order.description} title="Description">
        <p class="whitespace-pre-wrap text-sm leading-6 text-base-content/70">
          {@change_order.description}
        </p>
      </.section>

      <.section :if={@change_order.notes} title="Notes">
        <p class="whitespace-pre-wrap text-sm leading-6 text-base-content/70">
          {@change_order.notes}
        </p>
      </.section>

      <.section
        title="Change Order Lines"
        description="Track the priced delta that this amendment adds, removes, or adjusts."
      >
        <div :if={Enum.empty?(@change_order.change_order_lines || [])}>
          <.empty_state
            icon="hero-list-bullet"
            title="No change order lines yet"
            description="Add line items next to capture engineering, software, hardware, service, or credit adjustments."
          />
        </div>

        <div :if={!Enum.empty?(@change_order.change_order_lines || [])} class="space-y-3">
          <div
            :for={line <- @change_order.change_order_lines}
            class="flex items-start justify-between rounded-2xl border border-zinc-200 bg-zinc-50/70 px-4 py-4 dark:border-white/10 dark:bg-white/[0.03]"
          >
            <div class="space-y-1">
              <p class="font-medium text-base-content">
                {line.line_number}. {line.description}
              </p>
              <p class="text-sm text-base-content/50">
                {format_atom(line.line_kind)} · Qty {Decimal.to_string(line.quantity)}
              </p>
            </div>
            <div class="text-right text-sm text-base-content/70">
              <p>{format_amount(line.line_total)}</p>
              <p class="text-xs text-base-content/40">
                {format_amount(line.unit_price)} each
              </p>
            </div>
          </div>
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
      <p class="text-xs font-semibold uppercase tracking-[0.2em] text-base-content/40">
        {@label}
      </p>
      <p class="text-sm font-medium text-base-content">{@value}</p>
    </div>
    """
  end

  defp load_change_order!(id, actor) do
    case Commercial.get_change_order(
           id,
           actor: actor,
           load: [
             :status_variant,
             :line_count,
             :total_amount,
             agreement: [],
             project: [],
             organization: [],
             change_order_lines: []
           ]
         ) do
      {:ok, change_order} -> change_order
      {:error, error} -> raise "failed to load change order #{id}: #{inspect(error)}"
    end
  end

  defp schedule_impact(nil), do: "-"
  defp schedule_impact(days), do: "#{days} days"

  defp change_order_actions(%{status: :draft}) do
    [
      %{action: "submit", label: "Submit", icon: "hero-paper-airplane", variant: "primary"},
      %{action: "cancel", label: "Cancel", icon: "hero-x-circle", variant: nil}
    ]
  end

  defp change_order_actions(%{status: :submitted}) do
    [
      %{action: "approve", label: "Approve", icon: "hero-check-badge", variant: "primary"},
      %{action: "reject", label: "Reject", icon: "hero-x-circle", variant: nil},
      %{action: "cancel", label: "Cancel", icon: "hero-no-symbol", variant: nil}
    ]
  end

  defp change_order_actions(%{status: :approved}) do
    [
      %{
        action: "implement",
        label: "Implement",
        icon: "hero-wrench-screwdriver",
        variant: "primary"
      },
      %{action: "cancel", label: "Cancel", icon: "hero-no-symbol", variant: nil}
    ]
  end

  defp change_order_actions(%{status: :rejected}) do
    [
      %{action: "reopen", label: "Reopen", icon: "hero-arrow-path", variant: "primary"}
    ]
  end

  defp change_order_actions(%{status: :cancelled}) do
    [
      %{action: "reopen", label: "Reopen", icon: "hero-arrow-path", variant: "primary"}
    ]
  end

  defp change_order_actions(_change_order), do: []

  defp transition_change_order(change_order, :submit, actor),
    do: Commercial.submit_change_order(change_order, actor: actor)

  defp transition_change_order(change_order, :approve, actor),
    do: Commercial.approve_change_order(change_order, actor: actor)

  defp transition_change_order(change_order, :reject, actor),
    do: Commercial.reject_change_order(change_order, actor: actor)

  defp transition_change_order(change_order, :implement, actor),
    do: Commercial.implement_change_order(change_order, actor: actor)

  defp transition_change_order(change_order, :cancel, actor),
    do: Commercial.cancel_change_order(change_order, actor: actor)

  defp transition_change_order(change_order, :reopen, actor),
    do: Commercial.reopen_change_order(change_order, actor: actor)
end
