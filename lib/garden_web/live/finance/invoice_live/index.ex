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
     |> assign(:balance_total, counts.balance_total)
     |> assign(:organizations, nil)
     |> assign(:show_export_form, false)}
  end

  @impl true
  def handle_params(params, uri, socket) do
    socket = Cinder.UrlSync.handle_params(params, uri, socket)
    {:noreply, socket}
  end

  @impl true
  def handle_event("toggle_export_form", _params, socket) do
    socket =
      if socket.assigns.show_export_form do
        # closing the form — no need to reload
        socket
      else
        # opening the form — load organizations if not already loaded
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
          <.button phx-click="toggle_export_form">
            <.icon name="hero-arrow-down-tray" class="size-4" /> Batch Export
          </.button>
          <.button navigate={~p"/finance/invoices/new"} variant="primary">
            New Invoice
          </.button>
        </:actions>
      </.page_header>

      <%= if @show_export_form do %>
        <div class="mb-6 rounded-lg border border-gray-200 bg-white p-5 shadow-sm dark:border-white/10 dark:bg-white/5">
          <h3 class="text-sm font-semibold text-gray-900 dark:text-white mb-4">Batch Export</h3>
          <form method="get" action="/finance/invoices/batch-export" class="grid grid-cols-1 gap-4 sm:grid-cols-4 items-end">
            <div>
              <label for="export_from" class="block text-sm/6 font-medium text-gray-900 dark:text-white">From</label>
              <input
                id="export_from"
                type="date"
                name="from"
                required
                class="mt-1 block w-full rounded-md bg-white px-3 py-1.5 text-base text-gray-900 outline-1 -outline-offset-1 outline-gray-300 focus:outline-2 focus:-outline-offset-2 focus:outline-emerald-600 sm:text-sm/6 dark:bg-white/5 dark:text-white dark:outline-white/10"
              />
            </div>
            <div>
              <label for="export_to" class="block text-sm/6 font-medium text-gray-900 dark:text-white">To</label>
              <input
                id="export_to"
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
                  class="col-start-1 row-start-1 w-full appearance-none rounded-md bg-white py-1.5 pr-8 pl-3 text-base text-gray-900 outline-1 -outline-offset-1 outline-gray-300 focus:outline-2 focus:-outline-offset-2 focus:outline-emerald-600 sm:text-sm/6 dark:bg-white/5 dark:text-white dark:outline-white/10 dark:*:bg-gray-800 dark:focus:outline-emerald-500"
                >
                  <option value="">All clients</option>
                  <%= for org <- (@organizations || []) do %>
                    <option value={org.id}><%= org.name %></option>
                  <% end %>
                </select>
                <svg
                  class="pointer-events-none col-start-1 row-start-1 mr-2 size-5 self-center justify-self-end text-gray-500 sm:size-4 dark:text-gray-400"
                  viewBox="0 0 16 16"
                  fill="currentColor"
                >
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
              <button
                type="submit"
                class="ml-2 rounded-md bg-emerald-600 px-3 py-2 text-sm font-semibold text-white shadow-xs hover:bg-emerald-500 dark:bg-emerald-500 dark:hover:bg-emerald-400"
              >
                Download
              </button>
            </div>
          </form>
        </div>
      <% end %>

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
