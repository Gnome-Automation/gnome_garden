defmodule GnomeGardenWeb.Finance.PaymentLive.Index do
  use GnomeGardenWeb, :live_view
  use Cinder.UrlSync

  import GnomeGardenWeb.Finance.Helpers

  alias GnomeGarden.Finance

  @impl true
  def mount(_params, _session, socket) do
    counts = load_counts(socket.assigns.current_user)

    {:ok,
     socket
     |> assign(:page_title, "Payments")
     |> assign(:payment_count, counts.total)
     |> assign(:received_count, counts.received)
     |> assign(:deposited_count, counts.deposited)
     |> assign(:payment_total, counts.total_amount)}
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
      <.page_header eyebrow="Finance">
        Payments
        <:subtitle>
          Operational receipt records that make invoice collection explicit instead of collapsing payment history into a status flag.
        </:subtitle>
        <:actions>
          <.button navigate={~p"/finance/invoices"}>
            Invoices
          </.button>
          <.button navigate={~p"/finance/payments/new"} variant="primary">
            New Payment
          </.button>
        </:actions>
      </.page_header>

      <div class="grid gap-4 md:grid-cols-4">
        <.stat_card
          title="Payments"
          value={Integer.to_string(@payment_count)}
          description="Receipt records tracked independently from invoice status changes."
          icon="hero-banknotes"
        />
        <.stat_card
          title="Received"
          value={Integer.to_string(@received_count)}
          description="Payments acknowledged but not yet marked deposited."
          icon="hero-arrow-down-circle"
          accent="sky"
        />
        <.stat_card
          title="Deposited"
          value={Integer.to_string(@deposited_count)}
          description="Payments that have moved through the receipt workflow cleanly."
          icon="hero-check-badge"
          accent="emerald"
        />
        <.stat_card
          title="Amount"
          value={format_amount(@payment_total)}
          description="Aggregate payment value represented by the current receipt register."
          icon="hero-currency-dollar"
          accent="rose"
        />
      </div>

      <Cinder.collection
        id="payments-table"
        resource={GnomeGarden.Finance.Payment}
        actor={@current_user}
        url_state={@url_state}
        theme={GnomeGardenWeb.CinderTheme}
        page_size={25}
        query_opts={[
          load: [:status_variant, :application_count, :applied_amount, organization: []]
        ]}
        click={fn row -> JS.navigate(~p"/finance/payments/#{row}") end}
      >
        <:col :let={payment} field="payment_number" search sort label="Payment">
          <div class="space-y-1">
            <div class="font-medium text-base-content">
              {payment.payment_number || "Payment"}
            </div>
            <p class="text-sm text-base-content/50">
              Received {format_date(payment.received_on)}
            </p>
          </div>
        </:col>

        <:col :let={payment} label="Organization">
          {(payment.organization && payment.organization.name) || "-"}
        </:col>

        <:col :let={payment} field="reference" search label="Method">
          <div class="space-y-1">
            <p>{format_atom(payment.payment_method)}</p>
            <p class="text-xs text-base-content/40">
              {payment.reference || "No reference"}
            </p>
          </div>
        </:col>

        <:col :let={payment} field="amount" sort label="Amounts">
          <div class="space-y-1">
            <p>{format_amount(payment.amount)}</p>
            <p class="text-xs text-base-content/40">
              Applied {format_amount(payment.applied_amount)}
            </p>
          </div>
        </:col>

        <:col :let={payment} field="status" sort label="Status">
          <div class="space-y-1">
            <.status_badge status={payment.status_variant}>
              {format_atom(payment.status)}
            </.status_badge>
            <p class="text-xs text-base-content/40">
              {payment.application_count || 0} applications
            </p>
          </div>
        </:col>

        <:empty>
          <.empty_state
            icon="hero-banknotes"
            title="No payments yet"
            description="Create payment records when customer money is received, then allocate it against invoices."
          >
            <:action>
              <.button navigate={~p"/finance/payments/new"} variant="primary">
                Create Payment
              </.button>
            </:action>
          </.empty_state>
        </:empty>
      </Cinder.collection>
    </.page>
    """
  end

  defp load_counts(actor) do
    case Finance.list_payments(actor: actor) do
      {:ok, payments} ->
        %{
          total: length(payments),
          received: Enum.count(payments, &(&1.status == :received)),
          deposited: Enum.count(payments, &(&1.status == :deposited)),
          total_amount: sum_amounts(payments, :amount)
        }

      {:error, _} ->
        %{total: 0, received: 0, deposited: 0, total_amount: nil}
    end
  end
end
