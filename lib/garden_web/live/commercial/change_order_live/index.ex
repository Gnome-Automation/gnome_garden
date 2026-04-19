defmodule GnomeGardenWeb.Commercial.ChangeOrderLive.Index do
  use GnomeGardenWeb, :live_view

  import GnomeGardenWeb.Commercial.Helpers

  alias GnomeGarden.Commercial

  @impl true
  def mount(_params, _session, socket) do
    change_orders = load_change_orders(socket.assigns.current_user)

    {:ok,
     socket
     |> assign(:page_title, "Change Orders")
     |> assign(:change_order_count, length(change_orders))
     |> assign(:submitted_count, Enum.count(change_orders, &(&1.status == :submitted)))
     |> assign(
       :approved_count,
       Enum.count(change_orders, &(&1.status in [:approved, :implemented]))
     )
     |> assign(:total_amount, sum_amounts(change_orders, :total_amount))
     |> stream(:change_orders, change_orders)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.page class="pb-8">
      <.page_header eyebrow="Commercial">
        Change Orders
        <:subtitle>
          Track post-award commercial changes explicitly instead of overwriting the original agreement or project scope.
        </:subtitle>
        <:actions>
          <.button navigate={~p"/commercial/agreements"}>
            <.icon name="hero-document-check" class="size-4" /> Agreements
          </.button>
          <.button navigate={~p"/commercial/change-orders/new"} variant="primary">
            <.icon name="hero-plus" class="size-4" /> New Change Order
          </.button>
        </:actions>
      </.page_header>

      <div class="grid gap-4 md:grid-cols-4">
        <.stat_card
          title="Change Orders"
          value={Integer.to_string(@change_order_count)}
          description="Commercial amendments requested after the original agreement was created."
          icon="hero-arrow-path"
        />
        <.stat_card
          title="Submitted"
          value={Integer.to_string(@submitted_count)}
          description="Change orders currently awaiting commercial approval."
          icon="hero-paper-airplane"
          accent="sky"
        />
        <.stat_card
          title="Approved"
          value={Integer.to_string(@approved_count)}
          description="Approved or implemented changes already affecting delivery and financial outcomes."
          icon="hero-check-badge"
          accent="amber"
        />
        <.stat_card
          title="Change Value"
          value={format_amount(@total_amount)}
          description="Aggregate priced delta represented across all current change orders."
          icon="hero-banknotes"
          accent="rose"
        />
      </div>

      <.section
        title="Post-Award Changes"
        description="Keep scope, schedule, and pricing deltas explicit so the original agreement remains historically accurate."
        compact
        body_class="p-0"
      >
        <div :if={@change_order_count == 0} class="p-6 sm:p-7">
          <.empty_state
            icon="hero-arrow-path"
            title="No change orders yet"
            description="Create change orders when scope, schedule, or pricing shifts after award."
          >
            <:action>
              <.button navigate={~p"/commercial/change-orders/new"} variant="primary">
                Create Change Order
              </.button>
            </:action>
          </.empty_state>
        </div>

        <div :if={@change_order_count > 0} class="overflow-x-auto">
          <table class="min-w-full divide-y divide-zinc-200 text-sm dark:divide-white/10">
            <thead class="bg-zinc-50 dark:bg-white/[0.03]">
              <tr>
                <th class="px-5 py-3 text-left font-medium text-zinc-500 dark:text-zinc-400">
                  Change Order
                </th>
                <th class="px-5 py-3 text-left font-medium text-zinc-500 dark:text-zinc-400">
                  Agreement
                </th>
                <th class="px-5 py-3 text-left font-medium text-zinc-500 dark:text-zinc-400">
                  Type
                </th>
                <th class="px-5 py-3 text-left font-medium text-zinc-500 dark:text-zinc-400">
                  Value
                </th>
                <th class="px-5 py-3 text-left font-medium text-zinc-500 dark:text-zinc-400">
                  Status
                </th>
              </tr>
            </thead>
            <tbody
              id="change-orders"
              phx-update="stream"
              class="divide-y divide-zinc-200 dark:divide-white/10"
            >
              <tr :for={{dom_id, change_order} <- @streams.change_orders} id={dom_id}>
                <td class="px-5 py-4 align-top">
                  <div class="space-y-1">
                    <.link
                      navigate={~p"/commercial/change-orders/#{change_order}"}
                      class="font-medium text-zinc-900 hover:text-emerald-600 dark:text-white"
                    >
                      {change_order.title}
                    </.link>
                    <p class="text-sm text-zinc-500 dark:text-zinc-400">
                      {change_order.change_order_number}
                    </p>
                  </div>
                </td>
                <td class="px-5 py-4 align-top text-zinc-600 dark:text-zinc-300">
                  {(change_order.agreement && change_order.agreement.name) || "-"}
                </td>
                <td class="px-5 py-4 align-top text-zinc-600 dark:text-zinc-300">
                  {format_atom(change_order.change_type)}
                </td>
                <td class="px-5 py-4 align-top text-zinc-600 dark:text-zinc-300">
                  <div class="space-y-1">
                    <p>{format_amount(change_order.total_amount)}</p>
                    <p class="text-xs text-zinc-400 dark:text-zinc-500">
                      {change_order.line_count || 0} lines
                    </p>
                  </div>
                </td>
                <td class="px-5 py-4 align-top">
                  <.status_badge status={change_order.status_variant}>
                    {format_atom(change_order.status)}
                  </.status_badge>
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </.section>
    </.page>
    """
  end

  defp load_change_orders(actor) do
    case Commercial.list_change_orders(
           actor: actor,
           query: [sort: [requested_on: :desc, inserted_at: :desc]],
           load: [
             :status_variant,
             :line_count,
             :total_amount,
             agreement: [],
             project: [],
             organization: []
           ]
         ) do
      {:ok, change_orders} -> change_orders
      {:error, error} -> raise "failed to load change orders: #{inspect(error)}"
    end
  end

  defp sum_amounts(records, field) do
    Enum.reduce(records, Decimal.new(0), fn record, total ->
      Decimal.add(total, Map.get(record, field) || Decimal.new(0))
    end)
  end
end
