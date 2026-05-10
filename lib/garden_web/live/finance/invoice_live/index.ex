defmodule GnomeGardenWeb.Finance.InvoiceLive.Index do
  use GnomeGardenWeb, :live_view
  use Cinder.UrlSync

  import GnomeGardenWeb.Finance.Helpers

  alias GnomeGarden.Finance

  @impl true
  def mount(_params, _session, socket) do
    counts = load_counts(socket.assigns.current_user)

    {:ok,
     socket
     |> assign(:page_title, "Invoices")
     |> assign(:invoice_count, counts.total)
     |> assign(:issued_count, counts.issued)
     |> assign(:paid_count, counts.paid)
     |> assign(:balance_total, counts.balance_total)}
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
        Invoices
        <:subtitle>
          Operational invoice headers that stay traceable to agreements, projects, work orders, and source lines.
        </:subtitle>
        <:actions>
          <.button navigate={~p"/commercial/agreements"}>
            Agreements
          </.button>
          <.button navigate={~p"/finance/invoices/new"} variant="primary">
            New Invoice
          </.button>
        </:actions>
      </.page_header>

      <div class="grid gap-4 md:grid-cols-4">
        <.stat_card
          title="Invoices"
          value={Integer.to_string(@invoice_count)}
          description="Draft, issued, paid, and void invoice headers tracked in operations."
          icon="hero-receipt-percent"
        />
        <.stat_card
          title="Issued"
          value={Integer.to_string(@issued_count)}
          description="Invoices currently open and expected to be collected."
          icon="hero-paper-airplane"
          accent="sky"
        />
        <.stat_card
          title="Paid"
          value={Integer.to_string(@paid_count)}
          description="Invoices already fully paid and closed out operationally."
          icon="hero-check-badge"
          accent="amber"
        />
        <.stat_card
          title="Open Balance"
          value={format_amount(@balance_total)}
          description="Remaining receivable balance across the current invoice set."
          icon="hero-banknotes"
          accent="rose"
        />
      </div>

      <Cinder.collection
        id="invoices-table"
        resource={GnomeGarden.Finance.Invoice}
        actor={@current_user}
        url_state={@url_state}
        theme={GnomeGardenWeb.CinderTheme}
        page_size={25}
        query_opts={[
          load: [:status_variant, organization: [], agreement: [], project: [], work_order: []]
        ]}
        click={fn row -> JS.navigate(~p"/finance/invoices/#{row}") end}
      >
        <:col :let={invoice} field="invoice_number" search sort label="Invoice">
          <div class="space-y-1">
            <div class="font-medium text-base-content">
              {invoice.invoice_number || "Draft Invoice"}
            </div>
            <p class="text-sm text-base-content/50">
              Due {format_date(invoice.due_on)}
            </p>
          </div>
        </:col>

        <:col :let={invoice} label="Organization">
          {(invoice.organization && invoice.organization.name) || "-"}
        </:col>

        <:col :let={invoice} label="Scope">
          <div class="space-y-1">
            <p>{(invoice.agreement && invoice.agreement.name) || "No agreement"}</p>
            <p class="text-xs text-base-content/40">
              {(invoice.project && invoice.project.name) ||
                (invoice.work_order && invoice.work_order.title) || "No project/work order"}
            </p>
          </div>
        </:col>

        <:col :let={invoice} field="total_amount" sort label="Amounts">
          <div class="space-y-1">
            <p>{format_amount(invoice.total_amount)}</p>
            <p class="text-xs text-base-content/40">
              Balance {format_amount(invoice.balance_amount)}
            </p>
          </div>
        </:col>

        <:col :let={invoice} field="status" sort label="Status">
          <.status_badge status={invoice.status_variant}>
            {format_atom(invoice.status)}
          </.status_badge>
        </:col>

        <:empty>
          <.empty_state
            icon="hero-receipt-percent"
            title="No invoices yet"
            description="Create invoices directly, or draft them from agreement-backed billable sources."
          >
            <:action>
              <.button navigate={~p"/finance/invoices/new"} variant="primary">
                Create Invoice
              </.button>
            </:action>
          </.empty_state>
        </:empty>
      </Cinder.collection>
    </.page>
    """
  end

  defp load_counts(actor) do
    case Finance.list_invoices(actor: actor) do
      {:ok, invoices} ->
        %{
          total: length(invoices),
          issued: Enum.count(invoices, &(&1.status == :issued)),
          paid: Enum.count(invoices, &(&1.status == :paid)),
          balance_total: sum_amounts(invoices, :balance_amount)
        }

      {:error, _} ->
        %{total: 0, issued: 0, paid: 0, balance_total: nil}
    end
  end
end
