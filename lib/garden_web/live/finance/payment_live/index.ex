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
     |> assign(:payment_total, counts.total_amount)
     |> assign(:organizations, nil)
     |> assign(:show_export_form, false)}
  end

  @impl true
  def handle_event("toggle_export_form", _params, socket) do
    socket =
      if socket.assigns.show_export_form do
        socket
      else
        if socket.assigns.organizations == nil do
          orgs = GnomeGarden.Operations.list_organizations!(actor: socket.assigns.current_user)
          assign(socket, :organizations, orgs)
        else
          socket
        end
      end

    {:noreply, assign(socket, :show_export_form, !socket.assigns.show_export_form)}
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
          <.button phx-click="toggle_export_form" title="Export payments filtered by date range">
            <.icon name="hero-arrow-down-tray" class="size-4" /> Batch Export
          </.button>
          <.button navigate={~p"/finance/payments/new"} variant="primary" title="Record a new payment receipt — then allocate it against invoices">
            New Payment
          </.button>
        </:actions>
      </.page_header>

      <%= if @show_export_form do %>
        <div class="mb-6 rounded-lg border border-gray-200 bg-white p-5 shadow-sm dark:border-white/10 dark:bg-white/5">
          <h3 class="text-sm font-semibold text-gray-900 dark:text-white mb-4">Batch Export</h3>
          <form method="get" action={~p"/finance/payments/batch-export"} target="_blank" class="grid grid-cols-1 gap-4 sm:grid-cols-4 items-end">
            <div>
              <label for="pay_export_from" class="block text-sm/6 font-medium text-gray-900 dark:text-white">From</label>
              <input
                id="pay_export_from"
                type="date"
                name="from"
                required
                class="mt-1 block w-full rounded-md bg-white px-3 py-1.5 text-base text-gray-900 outline-1 -outline-offset-1 outline-gray-300 focus:outline-2 focus:-outline-offset-2 focus:outline-emerald-600 sm:text-sm/6 dark:bg-white/5 dark:text-white dark:outline-white/10"
              />
            </div>
            <div>
              <label for="pay_export_to" class="block text-sm/6 font-medium text-gray-900 dark:text-white">To</label>
              <input
                id="pay_export_to"
                type="date"
                name="to"
                required
                class="mt-1 block w-full rounded-md bg-white px-3 py-1.5 text-base text-gray-900 outline-1 -outline-offset-1 outline-gray-300 focus:outline-2 focus:-outline-offset-2 focus:outline-emerald-600 sm:text-sm/6 dark:bg-white/5 dark:text-white dark:outline-white/10"
              />
            </div>
            <div>
              <label class="block text-sm/6 font-medium text-gray-900 dark:text-white">Client (optional)</label>
              <div class="mt-1 grid grid-cols-1">
                <select
                  name="organization_id"
                  class="col-start-1 row-start-1 w-full appearance-none rounded-md bg-white py-1.5 pr-8 pl-3 text-base text-gray-900 outline-1 -outline-offset-1 outline-gray-300 focus:outline-2 focus:-outline-offset-2 focus:outline-emerald-600 sm:text-sm/6 dark:bg-white/5 dark:text-white dark:outline-white/10 dark:*:bg-gray-800"
                >
                  <option value="">All clients</option>
                  <%= for org <- (@organizations || []) do %>
                    <option value={org.id}><%= org.name %></option>
                  <% end %>
                </select>
                <svg class="pointer-events-none col-start-1 row-start-1 mr-2 size-5 self-center justify-self-end text-gray-500 sm:size-4 dark:text-gray-400" viewBox="0 0 16 16" fill="currentColor">
                  <path fill-rule="evenodd" d="M4.22 6.22a.75.75 0 0 1 1.06 0L8 8.94l2.72-2.72a.75.75 0 1 1 1.06 1.06l-3.25 3.25a.75.75 0 0 1-1.06 0L4.22 7.28a.75.75 0 0 1 0-1.06Z" clip-rule="evenodd" />
                </svg>
              </div>
            </div>
            <div class="flex gap-2 items-center">
              <label class="flex items-center gap-1 text-sm text-gray-700 dark:text-gray-300">
                <input type="radio" name="format" value="csv" checked={true} /> CSV
              </label>
              <label class="flex items-center gap-1 text-sm text-gray-700 dark:text-gray-300">
                <input type="radio" name="format" value="pdf" /> PDF
              </label>
              <button type="submit" class="ml-2 rounded-md bg-emerald-600 px-3 py-2 text-sm font-semibold text-white shadow-xs hover:bg-emerald-500">
                Download
              </button>
            </div>
          </form>
        </div>
      <% end %>

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

        <:col :let={payment} field="status" sort filter={:select} filter_options={[options: [{"Received", "received"}, {"Deposited", "deposited"}, {"Reversed", "reversed"}]]} label="Status">
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
