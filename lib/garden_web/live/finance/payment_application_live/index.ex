defmodule GnomeGardenWeb.Finance.PaymentApplicationLive.Index do
  use GnomeGardenWeb, :live_view
  use Cinder.UrlSync

  import GnomeGardenWeb.Finance.Helpers

  alias GnomeGarden.Finance

  @impl true
  def mount(_params, _session, socket) do
    counts = load_counts(socket.assigns.current_user)

    {:ok,
     socket
     |> assign(:page_title, "Payment Applications")
     |> assign(:application_count, counts.total)
     |> assign(:application_total, counts.total_amount)}
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
        Payment Applications
        <:subtitle>
          Explicit allocations that connect received payments to the invoices they settle.
        </:subtitle>
        <:actions>
          <.button navigate={~p"/finance/payments"}>
            Payments
          </.button>
          <.button navigate={~p"/finance/payment-applications/new"} variant="primary">
            New Application
          </.button>
        </:actions>
      </.page_header>

      <div class="grid gap-4 md:grid-cols-2">
        <.stat_card
          title="Applications"
          value={Integer.to_string(@application_count)}
          description="Explicit invoice allocations instead of implicit cash application."
          icon="hero-link"
        />
        <.stat_card
          title="Applied Total"
          value={format_amount(@application_total)}
          description="Aggregate amount already applied across the current application register."
          icon="hero-currency-dollar"
          accent="emerald"
        />
      </div>

      <Cinder.collection
        id="payment-applications-table"
        resource={GnomeGarden.Finance.PaymentApplication}
        actor={@current_user}
        url_state={@url_state}
        theme={GnomeGardenWeb.CinderTheme}
        page_size={25}
        query_opts={[load: [payment: [], invoice: []]]}
        click={fn row -> JS.navigate(~p"/finance/payment-applications/#{row}") end}
      >
        <:col :let={application} field="payment.payment_number" search sort label="Payment">
          {(application.payment && application.payment.payment_number) || "Payment"}
        </:col>

        <:col :let={application} field="invoice.invoice_number" search sort label="Invoice">
          {(application.invoice && application.invoice.invoice_number) || "Invoice"}
        </:col>

        <:col :let={application} field="applied_on" sort label="Applied On">
          {format_date(application.applied_on)}
        </:col>

        <:col :let={application} field="amount" sort label="Amount">
          {format_amount(application.amount)}
        </:col>

        <:empty>
          <.empty_state
            icon="hero-link"
            title="No payment applications yet"
            description="Allocate receipts to invoices explicitly as money is applied."
          >
            <:action>
              <.button navigate={~p"/finance/payment-applications/new"} variant="primary">
                Create Application
              </.button>
            </:action>
          </.empty_state>
        </:empty>
      </Cinder.collection>
    </.page>
    """
  end

  defp load_counts(actor) do
    case Finance.list_payment_applications(actor: actor) do
      {:ok, applications} ->
        %{
          total: length(applications),
          total_amount: sum_amounts(applications, :amount)
        }

      {:error, _} ->
        %{total: 0, total_amount: nil}
    end
  end
end
