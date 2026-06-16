defmodule GnomeGardenWeb.Finance.ReceivablesLive do
  use GnomeGardenWeb, :live_view

  import GnomeGardenWeb.Finance.Helpers

  alias GnomeGarden.Finance

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Receivables")
     |> load_workspace()}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.page class="pb-8">
      <.page_header eyebrow="Finance">
        Receivables
        <:subtitle>
          Money due, money received, and incoming bank activity that needs a decision.
        </:subtitle>
        <:actions>
          <.button navigate={~p"/finance/banking/review"}>
            <.icon name="hero-queue-list" class="size-4" /> Bank Review
          </.button>
          <.button navigate={~p"/finance/payments/new"}>
            <.icon name="hero-banknotes" class="size-4" /> Record Payment
          </.button>
          <.button navigate={~p"/finance/invoices/new"} variant="primary">
            <.icon name="hero-plus" class="size-4" /> New Invoice
          </.button>
        </:actions>
      </.page_header>

      <div class="grid gap-2 sm:grid-cols-2 lg:grid-cols-4">
        <.stat_card
          title="Open Balance"
          value={format_amount(@open_balance_total)}
          description={"#{@open_invoice_count} open invoices"}
          icon="hero-receipt-percent"
        />
        <.stat_card
          title="Overdue"
          value={format_amount(@overdue_balance_total)}
          description={"#{@overdue_invoice_count} past due invoices"}
          icon="hero-exclamation-triangle"
          accent="rose"
        />
        <.stat_card
          title="Unapplied Cash"
          value={format_amount(@unapplied_payment_total)}
          description={"#{@open_payment_count} received payments"}
          icon="hero-banknotes"
          accent="sky"
        />
        <.stat_card
          title="Bank Queue"
          value={Integer.to_string(@review_transaction_count)}
          description="Incoming bank rows to classify"
          icon="hero-queue-list"
          accent="amber"
        />
      </div>

      <div class="grid gap-3 xl:grid-cols-[minmax(0,1.35fr)_minmax(22rem,0.65fr)]">
        <div class="space-y-3">
          <.section
            title="Collection Priorities"
            description="Past-due invoices first, then the oldest open balances."
          >
            <div :if={@overdue_invoices == [] and @open_invoices == []}>
              <.empty_state
                icon="hero-check-circle"
                title="No open receivables"
                description="Issued invoices with remaining balances will appear here."
              >
                <:action>
                  <.button navigate={~p"/finance/invoices/new"} variant="primary">
                    Create Invoice
                  </.button>
                </:action>
              </.empty_state>
            </div>

            <div :if={@overdue_invoices != [] or @open_invoices != []} class="space-y-2">
              <.invoice_card
                :for={invoice <- priority_invoices(@overdue_invoices, @open_invoices)}
                invoice={invoice}
              />
            </div>
          </.section>

          <.section
            title="Received Payments"
            description="Cash we have recorded that still needs deposit confirmation or invoice application."
          >
            <div :if={@open_payments == []}>
              <.empty_state
                icon="hero-banknotes"
                title="No open payments"
                description="Received customer payments will appear here until they are deposited or applied."
              >
                <:action>
                  <.button navigate={~p"/finance/payments/new"} variant="primary">
                    Record Payment
                  </.button>
                </:action>
              </.empty_state>
            </div>

            <div :if={@open_payments != []} class="space-y-2">
              <.payment_card :for={payment <- Enum.take(@open_payments, 8)} payment={payment} />
            </div>
          </.section>
        </div>

        <aside class="space-y-3">
          <.section
            title="Bank Review Signals"
            description="Incoming bank rows that may explain received payments."
          >
            <div :if={@review_transactions == []}>
              <.empty_state
                icon="hero-check-circle"
                title="Bank queue is clear"
                description="New unmatched deposits and transfers will show up here after sync."
              />
            </div>

            <div :if={@review_transactions != []} class="space-y-2">
              <.bank_transaction_card
                :for={transaction <- Enum.take(@review_transactions, 6)}
                transaction={transaction}
              />
            </div>

            <div :if={@review_transactions != []} class="mt-3">
              <.button navigate={~p"/finance/banking/review"} class="w-full">
                Open Bank Review
              </.button>
            </div>
          </.section>

          <.section title="Registers" description="Detailed records stay available when needed.">
            <div class="grid gap-2">
              <.action_card
                title="Invoices"
                description="Search, edit, issue, void, or inspect invoice history."
                icon="hero-receipt-percent"
                navigate={~p"/finance/invoices"}
              />
              <.action_card
                title="Payments"
                description="Review receipt records and payment applications."
                icon="hero-banknotes"
                navigate={~p"/finance/payments"}
              />
            </div>
          </.section>
        </aside>
      </div>
    </.page>
    """
  end

  attr :invoice, :map, required: true

  defp invoice_card(assigns) do
    ~H"""
    <.link
      navigate={~p"/finance/invoices/#{@invoice}"}
      class="block rounded-lg border border-base-content/10 bg-base-200 px-3 py-3 transition hover:border-primary/40 hover:bg-base-300/70"
    >
      <div class="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
        <div class="min-w-0 space-y-1">
          <div class="flex flex-wrap items-center gap-2">
            <p class="font-semibold text-base-content">
              {@invoice.invoice_number || "Draft Invoice"}
            </p>
            <.status_badge status={@invoice.status_variant}>
              {format_atom(@invoice.status)}
            </.status_badge>
          </div>
          <p class="truncate text-sm text-base-content/60">
            {organization_name(@invoice)} - Due {format_date(@invoice.due_on)}
          </p>
        </div>

        <div class="grid grid-cols-2 gap-3 text-sm sm:min-w-56">
          <div>
            <p class="text-xs uppercase text-base-content/50">Balance</p>
            <p class="font-semibold tabular-nums">{format_amount(@invoice.balance_amount)}</p>
          </div>
          <div>
            <p class="text-xs uppercase text-base-content/50">Applied</p>
            <p class="font-semibold tabular-nums">{format_amount(@invoice.applied_amount)}</p>
          </div>
        </div>
      </div>
    </.link>
    """
  end

  attr :payment, :map, required: true

  defp payment_card(assigns) do
    assigns = assign(assigns, :unapplied_amount, unapplied_payment_amount(assigns.payment))

    ~H"""
    <.link
      navigate={~p"/finance/payments/#{@payment}"}
      class="block rounded-lg border border-base-content/10 bg-base-200 px-3 py-3 transition hover:border-primary/40 hover:bg-base-300/70"
    >
      <div class="flex items-start justify-between gap-3">
        <div class="min-w-0 space-y-1">
          <div class="flex flex-wrap items-center gap-2">
            <p class="font-semibold text-base-content">
              {@payment.payment_number || "Payment"}
            </p>
            <.status_badge status={@payment.status_variant}>
              {format_atom(@payment.status)}
            </.status_badge>
          </div>
          <p class="truncate text-sm text-base-content/60">
            {organization_name(@payment)} - {format_atom(@payment.payment_method)}
          </p>
          <p class="truncate text-xs text-base-content/50">
            {@payment.reference || "No reference"} - Received {format_date(@payment.received_on)}
          </p>
        </div>

        <div class="shrink-0 text-right">
          <p class="font-semibold tabular-nums">{format_amount(@payment.amount)}</p>
          <p class="text-xs text-base-content/50">
            {format_amount(@unapplied_amount)} unapplied
          </p>
        </div>
      </div>
    </.link>
    """
  end

  attr :transaction, :map, required: true

  defp bank_transaction_card(assigns) do
    ~H"""
    <.link
      navigate={~p"/finance/banking/review"}
      class="block rounded-lg border border-base-content/10 bg-base-200 px-3 py-3 transition hover:border-primary/40 hover:bg-base-300/70"
    >
      <div class="flex items-start justify-between gap-3">
        <div class="min-w-0 space-y-1">
          <p class="truncate font-semibold text-base-content">
            {bank_transaction_counterparty(@transaction)}
          </p>
          <p class="truncate text-sm text-base-content/60">
            {@transaction.description || @transaction.memo || @transaction.provider_transaction_id}
          </p>
          <div class="flex flex-wrap gap-1.5">
            <.status_badge status={bank_review_status_variant(@transaction.review_status)}>
              {format_atom(@transaction.review_status)}
            </.status_badge>
            <.status_badge status={bank_match_status_variant(@transaction.match_status)}>
              {bank_match_status_label(@transaction.match_status)}
            </.status_badge>
          </div>
        </div>

        <div class="shrink-0 text-right">
          <p class={bank_amount_classes(@transaction.amount)}>
            {format_amount(@transaction.amount)}
          </p>
          <p class="text-xs text-base-content/50">{format_datetime(@transaction.occurred_at)}</p>
        </div>
      </div>
    </.link>
    """
  end

  defp load_workspace(socket) do
    workspace = Finance.get_receivables_workspace!(actor: socket.assigns.current_user)

    socket
    |> assign(:open_invoices, workspace.open_invoices)
    |> assign(:overdue_invoices, workspace.overdue_invoices)
    |> assign(:open_payments, workspace.open_payments)
    |> assign(:review_transactions, workspace.review_transactions)
    |> assign(:open_invoice_count, workspace.open_invoice_count)
    |> assign(:overdue_invoice_count, workspace.overdue_invoice_count)
    |> assign(:open_payment_count, workspace.open_payment_count)
    |> assign(:review_transaction_count, workspace.review_transaction_count)
    |> assign(:open_balance_total, workspace.open_balance_total)
    |> assign(:overdue_balance_total, workspace.overdue_balance_total)
    |> assign(:received_payment_total, workspace.received_payment_total)
    |> assign(:unapplied_payment_total, workspace.unapplied_payment_total)
  end

  defp priority_invoices(overdue_invoices, open_invoices) do
    overdue_ids = MapSet.new(overdue_invoices, & &1.id)

    (overdue_invoices ++ Enum.reject(open_invoices, &MapSet.member?(overdue_ids, &1.id)))
    |> Enum.take(8)
  end

  defp organization_name(%{organization: %Ash.NotLoaded{}}), do: "No organization"
  defp organization_name(%{organization: nil}), do: "No organization"
  defp organization_name(%{organization: %{name: name}}), do: name || "No organization"
  defp organization_name(_record), do: "No organization"

  defp unapplied_payment_amount(payment) do
    Decimal.sub(payment.amount || Decimal.new(0), payment.applied_amount || Decimal.new(0))
  end
end
