defmodule GnomeGardenWeb.Commercial.ChangeOrderLive.Index do
  use GnomeGardenWeb, :live_view
  use Cinder.UrlSync

  import GnomeGardenWeb.Commercial.Helpers

  alias GnomeGarden.Commercial

  @impl true
  def mount(_params, _session, socket) do
    counts = load_counts(socket.assigns.current_user)

    {:ok,
     socket
     |> assign(:page_title, "Change Orders")
     |> assign(:change_order_count, counts.total)
     |> assign(:submitted_count, counts.submitted)
     |> assign(:approved_count, counts.approved)
     |> assign(:total_amount, counts.total_amount)}
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
      <.page_header eyebrow="Commercial">
        Change Orders
        <:subtitle>
          Track post-award commercial changes explicitly instead of overwriting the original agreement or project scope.
        </:subtitle>
        <:actions>
          <.button navigate={~p"/commercial/agreements"}>
            Agreements
          </.button>
          <.button navigate={~p"/commercial/change-orders/new"} variant="primary">
            New Change Order
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

      <Cinder.collection
        id="change-orders-table"
        resource={GnomeGarden.Commercial.ChangeOrder}
        actor={@current_user}
        url_state={@url_state}
        theme={GnomeGardenWeb.CinderTheme}
        page_size={25}
        query_opts={[
          load: [
            :status_variant,
            :line_count,
            :total_amount,
            agreement: [],
            project: [],
            organization: []
          ]
        ]}
        click={fn change_order -> JS.navigate(~p"/commercial/change-orders/#{change_order}") end}
      >
        <:col :let={change_order} field="title" sort search label="Change Order">
          <div class="space-y-1">
            <div class="font-medium text-zinc-900 dark:text-white">{change_order.title}</div>
            <p class="text-sm text-base-content/50">
              {change_order.change_order_number}
            </p>
          </div>
        </:col>

        <:col :let={change_order} field="agreement.name" sort search label="Agreement">
          {(change_order.agreement && change_order.agreement.name) || "-"}
        </:col>

        <:col :let={change_order} field="change_type" sort label="Type">
          {format_atom(change_order.change_type)}
        </:col>

        <:col :let={change_order} field="total_amount" sort label="Value">
          <div class="space-y-1">
            <p>{format_amount(change_order.total_amount)}</p>
            <p class="text-xs text-base-content/40">
              {change_order.line_count || 0} lines
            </p>
          </div>
        </:col>

        <:col :let={change_order} field="status" sort label="Status">
          <.status_badge status={change_order.status_variant}>
            {format_atom(change_order.status)}
          </.status_badge>
        </:col>

        <:empty>
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
        </:empty>
      </Cinder.collection>
    </.page>
    """
  end

  defp load_counts(actor) do
    case Commercial.list_change_orders(actor: actor, load: [:total_amount]) do
      {:ok, change_orders} ->
        %{
          total: length(change_orders),
          submitted: Enum.count(change_orders, &(&1.status == :submitted)),
          approved: Enum.count(change_orders, &(&1.status in [:approved, :implemented])),
          total_amount: sum_amounts(change_orders, :total_amount)
        }

      {:error, _} ->
        %{total: 0, submitted: 0, approved: 0, total_amount: Decimal.new(0)}
    end
  end

  defp sum_amounts(records, field) do
    Enum.reduce(records, Decimal.new(0), fn record, total ->
      Decimal.add(total, Map.get(record, field) || Decimal.new(0))
    end)
  end
end
