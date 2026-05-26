defmodule GnomeGardenWeb.ClientPortal.DashboardLive do
  use GnomeGardenWeb, :live_view

  alias GnomeGarden.Finance
  alias GnomeGarden.Commercial

  @impl true
  def mount(_params, _session, socket) do
    actor = socket.assigns.current_client_user

    invoices = load_portal_invoices(actor)
    agreements = load_portal_agreements(actor)
    payments = load_portal_payments(actor)

    today = Date.utc_today()
    open_invoices = Enum.filter(invoices, &(&1.status in [:issued, :partial]))
    overdue_invoices = Enum.filter(open_invoices, &(&1.due_on && Date.compare(&1.due_on, today) == :lt))

    outstanding_balance =
      Enum.reduce(open_invoices, Decimal.new("0"), fn inv, acc ->
        Decimal.add(acc, inv.balance_amount || Decimal.new("0"))
      end)

    total_paid_ytd =
      payments
      |> Enum.filter(&(&1.received_on && &1.received_on.year == today.year))
      |> Enum.reduce(Decimal.new("0"), fn p, acc -> Decimal.add(acc, p.amount) end)

    next_due =
      open_invoices
      |> Enum.filter(& &1.due_on)
      |> Enum.sort_by(& &1.due_on, Date)
      |> List.first()

    recent_payments = Enum.take(Enum.sort_by(payments, & &1.received_on, {:desc, Date}), 3)
    recent_invoices = Enum.take(Enum.sort_by(invoices, & &1.inserted_at, {:desc, DateTime}), 3)

    {:ok,
     socket
     |> assign(:page_title, "Dashboard")
     |> assign(:outstanding_balance, outstanding_balance)
     |> assign(:total_paid_ytd, total_paid_ytd)
     |> assign(:active_agreements_count, length(agreements))
     |> assign(:payments_count, length(payments))
     |> assign(:overdue_invoices, overdue_invoices)
     |> assign(:next_due, next_due)
     |> assign(:recent_payments, recent_payments)
     |> assign(:recent_invoices, recent_invoices)
     |> assign(:today, today)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.page max_width="max-w-full" class="pb-8">
      <.page_header eyebrow="Client Portal">
        Dashboard
        <:subtitle>Your account at a glance.</:subtitle>
      </.page_header>

      <%!-- Stats row --%>
      <div class="grid grid-cols-2 gap-4 sm:grid-cols-4 mb-6">
        <.stat_card
          title="Outstanding Balance"
          value={"$#{Decimal.to_string(Decimal.round(@outstanding_balance, 2))}"}
          description="Across open invoices"
          icon="hero-banknotes"
        />
        <.stat_card
          title={"Paid #{Date.utc_today().year}"}
          value={"$#{Decimal.to_string(Decimal.round(@total_paid_ytd, 2))}"}
          description="Year to date"
          icon="hero-check-badge"
          accent="emerald"
        />
        <.stat_card
          title="Active Agreements"
          value={to_string(@active_agreements_count)}
          description="Current service agreements"
          icon="hero-document-text"
          accent="sky"
        />
        <.stat_card
          title="Payments Made"
          value={to_string(@payments_count)}
          description="Total payments on record"
          icon="hero-credit-card"
          accent="amber"
        />
      </div>

      <%!-- Needs attention --%>
      <div :if={@overdue_invoices != []} class="mb-6 rounded-lg border border-red-200 bg-red-50 dark:border-red-500/20 dark:bg-red-500/5 p-4">
        <p class="text-sm font-semibold text-red-700 dark:text-red-400 mb-2">
          Action needed — <%= length(@overdue_invoices) %> overdue invoice<%= if length(@overdue_invoices) > 1, do: "s" %>
        </p>
        <div class="space-y-1">
          <div :for={inv <- @overdue_invoices} class="flex items-center justify-between text-sm">
            <.link navigate={~p"/portal/invoices/#{inv.id}"} class="text-red-600 hover:underline font-medium dark:text-red-400">
              {inv.invoice_number}
            </.link>
            <span class="text-red-600 dark:text-red-400">
              ${ Decimal.to_string(Decimal.round(inv.balance_amount || Decimal.new("0"), 2)) } — due {Date.to_string(inv.due_on)}
            </span>
          </div>
        </div>
      </div>

      <%!-- Next due --%>
      <div :if={@next_due && @overdue_invoices == []} class="mb-6 rounded-lg border border-amber-200 bg-amber-50 dark:border-amber-500/20 dark:bg-amber-500/5 p-4">
        <p class="text-sm font-semibold text-amber-700 dark:text-amber-400 mb-1">Next payment due</p>
        <div class="flex items-center justify-between text-sm">
          <.link navigate={~p"/portal/invoices/#{@next_due.id}"} class="text-amber-700 hover:underline font-medium dark:text-amber-300">
            {@next_due.invoice_number}
          </.link>
          <span class="text-amber-700 dark:text-amber-400">
            ${ Decimal.to_string(Decimal.round(@next_due.balance_amount || Decimal.new("0"), 2)) } due {Date.to_string(@next_due.due_on)}
          </span>
        </div>
      </div>

      <%!-- Quick links --%>
      <div class="grid grid-cols-3 gap-3 mb-6">
        <.link navigate={~p"/portal/invoices"} class="flex flex-col items-center justify-center gap-1 rounded-lg border border-base-content/10 bg-base-100 px-4 py-4 text-sm font-medium text-base-content hover:bg-base-200 transition-colors">
          <.icon name="hero-receipt-percent" class="size-5 text-emerald-500" />
          Invoices
        </.link>
        <.link navigate={~p"/portal/payments"} class="flex flex-col items-center justify-center gap-1 rounded-lg border border-base-content/10 bg-base-100 px-4 py-4 text-sm font-medium text-base-content hover:bg-base-200 transition-colors">
          <.icon name="hero-banknotes" class="size-5 text-emerald-500" />
          Payments
        </.link>
        <.link navigate={~p"/portal/agreements"} class="flex flex-col items-center justify-center gap-1 rounded-lg border border-base-content/10 bg-base-100 px-4 py-4 text-sm font-medium text-base-content hover:bg-base-200 transition-colors">
          <.icon name="hero-document-text" class="size-5 text-emerald-500" />
          Agreements
        </.link>
      </div>

      <%!-- Recent activity --%>
      <div class="grid grid-cols-1 gap-6 sm:grid-cols-2">
        <.section title="Recent Invoices" body_class="p-0">
          <div :if={@recent_invoices != []}>
            <div :for={inv <- @recent_invoices} class="flex items-center justify-between px-4 py-3 border-b border-base-content/5 last:border-0 hover:bg-base-200/30 transition-colors">
              <div>
                <.link navigate={~p"/portal/invoices/#{inv.id}"} class="text-sm font-medium text-emerald-600 hover:underline">
                  {inv.invoice_number}
                </.link>
                <p class="text-xs text-base-content/40 mt-0.5">Due {if inv.due_on, do: Date.to_string(inv.due_on), else: "—"}</p>
              </div>
              <div class="text-right">
                <p class="text-sm font-medium text-base-content">${inv.total_amount}</p>
                <.status_badge status={invoice_status_variant(inv.status)}>
                  {String.capitalize(to_string(inv.status))}
                </.status_badge>
              </div>
            </div>
          </div>
          <div :if={@recent_invoices == []} class="px-4 py-6 text-sm text-base-content/40 italic">No invoices yet.</div>
          <div class="px-4 py-3 border-t border-base-content/5">
            <.link navigate={~p"/portal/invoices"} class="text-xs font-medium text-emerald-600 hover:underline">View all invoices →</.link>
          </div>
        </.section>

        <.section title="Recent Payments" body_class="p-0">
          <div :if={@recent_payments != []}>
            <div :for={pay <- @recent_payments} class="flex items-center justify-between px-4 py-3 border-b border-base-content/5 last:border-0 hover:bg-base-200/30 transition-colors">
              <div>
                <p class="text-sm font-medium text-base-content">{pay.payment_number}</p>
                <p class="text-xs text-base-content/40 mt-0.5">{if pay.received_on, do: Date.to_string(pay.received_on), else: "—"}</p>
              </div>
              <p class="text-sm font-semibold text-emerald-600">${Decimal.to_string(Decimal.round(pay.amount, 2))}</p>
            </div>
          </div>
          <div :if={@recent_payments == []} class="px-4 py-6 text-sm text-base-content/40 italic">No payments yet.</div>
          <div class="px-4 py-3 border-t border-base-content/5">
            <.link navigate={~p"/portal/payments"} class="text-xs font-medium text-emerald-600 hover:underline">View all payments →</.link>
          </div>
        </.section>
      </div>
    </.page>
    """
  end

  defp load_portal_invoices(actor) do
    case Finance.list_portal_invoices(actor: actor) do
      {:ok, invoices} -> invoices
      _ -> []
    end
  end

  defp load_portal_agreements(actor) do
    case Commercial.list_portal_agreements(actor: actor) do
      {:ok, agreements} -> agreements
      _ -> []
    end
  end

  defp load_portal_payments(actor) do
    case Finance.list_portal_payments(actor: actor) do
      {:ok, payments} -> payments
      _ -> []
    end
  end

  defp invoice_status_variant(:issued), do: :warning
  defp invoice_status_variant(:partial), do: :info
  defp invoice_status_variant(:paid), do: :success
  defp invoice_status_variant(:void), do: :error
  defp invoice_status_variant(:write_off), do: :error
  defp invoice_status_variant(_), do: :default
end
