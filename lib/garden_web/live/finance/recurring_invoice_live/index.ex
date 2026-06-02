defmodule GnomeGardenWeb.Finance.RecurringInvoiceLive.Index do
  use GnomeGardenWeb, :live_view

  import GnomeGardenWeb.Finance.Helpers

  alias GnomeGarden.Finance
  alias GnomeGarden.Finance.RecurringInvoice

  require Ash.Query

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Recurring Invoices")
     |> assign(:templates, load_templates())}
  end

  @impl true
  def handle_event("pause", %{"id" => id}, socket) do
    template = Ash.get!(RecurringInvoice, id, domain: Finance, authorize?: false)
    Finance.pause_recurring_invoice(template, authorize?: false)
    {:noreply, assign(socket, :templates, load_templates())}
  end

  @impl true
  def handle_event("resume", %{"id" => id}, socket) do
    template = Ash.get!(RecurringInvoice, id, domain: Finance, authorize?: false)
    Finance.resume_recurring_invoice(template, authorize?: false)
    {:noreply, assign(socket, :templates, load_templates())}
  end

  defp load_templates do
    RecurringInvoice
    |> Ash.Query.sort(inserted_at: :desc)
    |> Ash.Query.load([:organization, :recurring_invoice_lines])
    |> Ash.read!(domain: Finance, authorize?: false)
  end

  defp template_amount(template) do
    template.recurring_invoice_lines
    |> Enum.reduce(Decimal.new(0), fn line, acc -> Decimal.add(acc, line.line_total) end)
  end

  defp interval_label(:daily), do: "Daily"
  defp interval_label(:weekly), do: "Weekly"
  defp interval_label(:monthly), do: "Monthly"
  defp interval_label(:quarterly), do: "Quarterly"
  defp interval_label(:semi_annually), do: "Semi-annually"
  defp interval_label(:annually), do: "Annually"

  defp status_variant(:active), do: :success
  defp status_variant(:paused), do: :warning
  defp status_variant(:stopped), do: :default

  @impl true
  def render(assigns) do
    ~H"""
    <.page class="pb-8">
      <.page_header eyebrow="Finance">
        Recurring Invoices
        <:subtitle>
          Templates that auto-generate invoices on a schedule. Active templates run daily.
        </:subtitle>
        <:actions>
          <.button navigate={~p"/finance/recurring-invoices/new"} variant="primary">
            New Recurring Invoice
          </.button>
        </:actions>
      </.page_header>

      <%= if Enum.empty?(@templates) do %>
        <.empty_state
          icon="hero-arrow-path"
          title="No recurring invoices yet"
          description="Set one up to auto-bill clients on a schedule."
        >
          <:action>
            <.button navigate={~p"/finance/recurring-invoices/new"} variant="primary">
              New Recurring Invoice
            </.button>
          </:action>
        </.empty_state>
      <% else %>
        <.table id="recurring-invoices-table" rows={@templates}>
          <:col :let={t} label="Client">
            <.link navigate={~p"/finance/recurring-invoices/#{t.id}"} class="font-medium text-base-content hover:underline">
              {(t.organization && t.organization.name) || "—"}
            </.link>
          </:col>
          <:col :let={t} label="Interval">{interval_label(t.interval)}</:col>
          <:col :let={t} label="Amount per invoice">{format_currency(template_amount(t))}</:col>
          <:col :let={t} label="Next invoice">
            <%= if t.status in [:stopped, :paused] do %>
              <span class="text-base-content/40">—</span>
            <% else %>
              {format_date(t.next_generation_date)}
            <% end %>
          </:col>
          <:col :let={t} label="Status">
            <.status_badge status={status_variant(t.status)}>{format_atom(t.status)}</.status_badge>
          </:col>
          <:col :let={t} label="">
            <div class="flex gap-2 justify-end">
              <.button navigate={~p"/finance/recurring-invoices/#{t.id}/edit"}>Edit</.button>
              <%= if t.status == :active do %>
                <.button phx-click="pause" phx-value-id={t.id}>Pause</.button>
              <% end %>
              <%= if t.status == :paused do %>
                <.button phx-click="resume" phx-value-id={t.id} variant="primary">Resume</.button>
              <% end %>
              <.button navigate={~p"/finance/recurring-invoices/#{t.id}"}>View</.button>
            </div>
          </:col>
        </.table>
      <% end %>
    </.page>
    """
  end
end
