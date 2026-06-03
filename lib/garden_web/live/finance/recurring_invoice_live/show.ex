defmodule GnomeGardenWeb.Finance.RecurringInvoiceLive.Show do
  use GnomeGardenWeb, :live_view

  import GnomeGardenWeb.Finance.Helpers

  alias GnomeGarden.Finance
  alias GnomeGarden.Finance.RecurringInvoice
  alias GnomeGarden.Finance.Invoice

  require Ash.Query

  @impl true
  def mount(%{"id" => id} = params, _session, socket) do
    template =
      Ash.get!(RecurringInvoice, id,
        domain: Finance,
        authorize?: false,
        load: [:organization, :agreement, :recurring_invoice_lines]
      )

    generated_invoices = load_generated_invoices(id)
    return_to = params["return_to"] || ~p"/finance/recurring-invoices"

    {:ok,
     socket
     |> assign(:page_title, "Recurring Invoice")
     |> assign(:template, template)
     |> assign(:generated_invoices, generated_invoices)
     |> assign(:return_to, return_to)}
  end

  defp load_generated_invoices(recurring_invoice_id) do
    Invoice
    |> Ash.Query.filter(recurring_invoice_id == ^recurring_invoice_id)
    |> Ash.Query.sort(inserted_at: :desc)
    |> Ash.read!(domain: Finance, authorize?: false)
  end

  @impl true
  def handle_event("pause", _params, socket) do
    {:ok, updated} = Finance.pause_recurring_invoice(socket.assigns.template, authorize?: false)
    {:noreply, assign(socket, :template, updated)}
  end

  @impl true
  def handle_event("resume", _params, socket) do
    {:ok, updated} = Finance.resume_recurring_invoice(socket.assigns.template, authorize?: false)
    {:noreply, assign(socket, :template, updated)}
  end

  @impl true
  def handle_event("stop", _params, socket) do
    {:ok, updated} = Finance.stop_recurring_invoice(socket.assigns.template, authorize?: false)
    {:noreply, assign(socket, :template, updated)}
  end

  # recurring invoice statuses
  defp status_variant(:active), do: :success
  defp status_variant(:paused), do: :warning
  defp status_variant(:stopped), do: :default
  # generated invoice statuses
  defp status_variant(:paid), do: :success
  defp status_variant(:partial), do: :warning
  defp status_variant(:issued), do: :info
  defp status_variant(_), do: :default

  defp interval_label(:daily), do: "Daily"
  defp interval_label(:weekly), do: "Weekly"
  defp interval_label(:monthly), do: "Monthly"
  defp interval_label(:quarterly), do: "Quarterly"
  defp interval_label(:semi_annually), do: "Semi-annually"
  defp interval_label(:annually), do: "Annually"

  defp template_amount(template) do
    template.recurring_invoice_lines
    |> Enum.reduce(Decimal.new(0), fn line, acc -> Decimal.add(acc, line.line_total) end)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.page class="pb-8">
      <.page_header eyebrow="Finance">
        Recurring Invoice
        <:subtitle>
          {(@template.organization && @template.organization.name) || "—"} · {interval_label(@template.interval)}
        </:subtitle>
        <:actions>
          <.button navigate={@return_to}>Back</.button>
          <.button navigate={~p"/finance/recurring-invoices/#{@template.id}/edit"}>Edit</.button>
          <%= if @template.status == :active do %>
            <.button phx-click="pause">Pause</.button>
          <% end %>
          <%= if @template.status == :paused do %>
            <.button phx-click="resume" variant="primary">Resume</.button>
            <.button phx-click="stop">Stop</.button>
          <% end %>
        </:actions>
      </.page_header>

      <%!-- Summary --%>
      <.section title="Template Details">
        <div class="grid grid-cols-2 gap-4 sm:grid-cols-4">
          <div>
            <div class="text-xs text-base-content/50 uppercase tracking-wide">Status</div>
            <.status_badge status={status_variant(@template.status)}>{format_atom(@template.status)}</.status_badge>
          </div>
          <div>
            <div class="text-xs text-base-content/50 uppercase tracking-wide">Interval</div>
            <div class="text-sm font-medium">{interval_label(@template.interval)}</div>
          </div>
          <div>
            <div class="text-xs text-base-content/50 uppercase tracking-wide">Next Invoice</div>
            <div class="text-sm font-medium">
              <%= if @template.status in [:stopped, :paused] do %>
                <span class="text-base-content/40">—</span>
              <% else %>
                {format_date(@template.next_generation_date)}
              <% end %>
            </div>
          </div>
          <div>
            <div class="text-xs text-base-content/50 uppercase tracking-wide">Amount</div>
            <div class="text-sm font-medium">{format_currency(template_amount(@template))}</div>
          </div>
          <div>
            <div class="text-xs text-base-content/50 uppercase tracking-wide">Net Terms</div>
            <div class="text-sm font-medium">Net {@template.net_terms_days}</div>
          </div>
          <div>
            <div class="text-xs text-base-content/50 uppercase tracking-wide">Delivery</div>
            <div class="text-sm font-medium">{format_atom(@template.delivery_mode)}</div>
          </div>
          <div>
            <div class="text-xs text-base-content/50 uppercase tracking-wide">Start Date</div>
            <div class="text-sm font-medium">{format_date(@template.start_date)}</div>
          </div>
          <div>
            <div class="text-xs text-base-content/50 uppercase tracking-wide">End Date</div>
            <div class="text-sm font-medium">{format_date(@template.end_date)}</div>
          </div>
        </div>
      </.section>

      <%!-- Line Items --%>
      <.section title="Line Items" class="mt-6">
        <.table id="line-items-table" rows={@template.recurring_invoice_lines}>
          <:col :let={line} label="Description">{line.description}</:col>
          <:col :let={line} label="Qty">{line.quantity}</:col>
          <:col :let={line} label="Unit Price">{format_currency(line.unit_price)}</:col>
          <:col :let={line} label="Total">{format_currency(line.line_total)}</:col>
        </.table>
        <div class="mt-3 text-right text-sm font-semibold text-gray-900 dark:text-white">
          Total: {format_currency(template_amount(@template))}
        </div>
      </.section>

      <%!-- Generated Invoices --%>
      <.section title="Generated Invoices" class="mt-6">
        <%= if Enum.empty?(@generated_invoices) do %>
          <p class="text-sm text-base-content/50">No invoices generated yet.</p>
        <% else %>
          <.table id="generated-invoices-table" rows={@generated_invoices}>
            <:col :let={inv} label="Invoice">
              <.link navigate={~p"/finance/invoices/#{inv.id}?return_to=#{~p"/finance/recurring-invoices/#{@template.id}"}"} class="font-medium hover:underline">
                {inv.invoice_number || "Draft"}
              </.link>
            </:col>
            <:col :let={inv} label="Issued">{format_date(inv.issued_on)}</:col>
            <:col :let={inv} label="Due">{format_date(inv.due_on)}</:col>
            <:col :let={inv} label="Amount">{format_currency(inv.total_amount)}</:col>
            <:col :let={inv} label="Status">
              <.status_badge status={status_variant(inv.status)}>{format_atom(inv.status)}</.status_badge>
            </:col>
          </.table>
        <% end %>
      </.section>
    </.page>
    """
  end
end
