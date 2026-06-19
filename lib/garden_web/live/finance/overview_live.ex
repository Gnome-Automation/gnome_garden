defmodule GnomeGardenWeb.Finance.OverviewLive do
  use GnomeGardenWeb, :live_view

  import GnomeGardenWeb.Finance.Helpers

  alias GnomeGarden.Finance

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Finance")
     |> load_overview()}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.page class="pb-8">
      <.page_header eyebrow="Finance">
        Finance
        <:subtitle>
          Cash, receivables, review work, and billable work in one operator view.
        </:subtitle>
        <:actions>
          <.button navigate={~p"/finance/banking"}>
            <.icon name="hero-building-library" class="size-4" /> Banking
          </.button>
          <.button navigate={~p"/finance/receivables"} variant="primary">
            <.icon name="hero-banknotes" class="size-4" /> Receivables
          </.button>
        </:actions>
      </.page_header>

      <div class="grid grid-cols-2 gap-2 sm:gap-3 xl:grid-cols-4">
        <.stat_card
          title="Cash"
          value={format_amount(@overview.cash_balance)}
          description={"Across #{@overview.bank_account_count} bank accounts."}
          icon="hero-building-library"
        />
        <.stat_card
          title="Review"
          value={Integer.to_string(@overview.needs_review_count)}
          description="Bank transactions waiting on a decision."
          icon="hero-queue-list"
          accent="sky"
        />
        <.stat_card
          title="Overdue AR"
          value={format_amount(@overview.overdue_balance_total)}
          description={"#{@overview.overdue_invoice_count} overdue invoices."}
          icon="hero-clock"
          accent="amber"
        />
        <.stat_card
          title="Ready"
          value={format_amount(@overview.ready_to_bill_total)}
          description={"#{@overview.source_group_count} customer groups ready to bill."}
          icon="hero-document-check"
          accent="rose"
        />
      </div>

      <div class="grid gap-4 xl:grid-cols-[minmax(0,1fr)_24rem]">
        <div class="space-y-4">
          <.section
            title="Next Actions"
            description="The highest-signal finance work from banking, receivables, and billing prep."
          >
            <div :if={@overview.next_actions == []}>
              <.empty_state
                icon="hero-check-circle"
                title="No finance actions waiting"
                description="Banking, receivables, and work-to-bill queues are clear."
              />
            </div>

            <div :if={@overview.next_actions != []} class="grid gap-3 md:grid-cols-2">
              <.action_item :for={action <- @overview.next_actions} action={action} />
            </div>
          </.section>

          <.section
            title="Workspaces"
            description="Start with the job you need to do, then drill into records only when useful."
          >
            <div class="grid gap-3 sm:grid-cols-2 xl:grid-cols-3">
              <.action_card
                title="Banking"
                description="Cash position, bank accounts, transactions, and sync health."
                icon="hero-building-library"
                navigate={~p"/finance/banking"}
              />
              <.action_card
                title="Review Queue"
                description="Categorize, ignore, or confirm imported bank transactions."
                icon="hero-queue-list"
                navigate={~p"/finance/banking/review"}
              />
              <.action_card
                title="Bank Rules"
                description="Configure provider-neutral automation before manual review."
                icon="hero-funnel"
                navigate={~p"/finance/banking/rules"}
              />
              <.action_card
                title="Sync Health"
                description="Provider pull history, webhook hints, and failed integration events."
                icon="hero-arrow-path"
                navigate={~p"/finance/banking/sync-runs"}
              />
              <.action_card
                title="Receivables"
                description="Open invoices, overdue balances, unapplied payments, and money in."
                icon="hero-banknotes"
                navigate={~p"/finance/receivables"}
              />
              <.action_card
                title="Work to Bill"
                description="Approved time and expenses grouped into invoice candidates."
                icon="hero-document-check"
                navigate={~p"/finance/work-to-bill"}
              />
              <.action_card
                title="Invoices"
                description="Detailed invoice records when the workflow needs record-level edits."
                icon="hero-receipt-percent"
                navigate={~p"/finance/invoices"}
              />
            </div>
          </.section>
        </div>

        <aside class="space-y-4">
          <.section title="Bank Sync" description="Current provider pull status.">
            <div class="space-y-3">
              <div class="rounded-lg border border-base-content/10 bg-base-200 p-3">
                <div class="flex items-start justify-between gap-3">
                  <div class="min-w-0">
                    <p class="text-sm font-semibold text-base-content">
                      {sync_title(@overview.latest_sync_run)}
                    </p>
                    <p class="mt-1 text-xs text-base-content/55">
                      {sync_description(@overview.latest_sync_run)}
                    </p>
                  </div>
                  <.status_badge status={sync_status_variant(@overview.latest_sync_run)}>
                    {sync_status_label(@overview.latest_sync_run)}
                  </.status_badge>
                </div>
              </div>

              <div class="grid grid-cols-2 gap-2 text-xs">
                <div class="rounded-lg border border-base-content/10 bg-base-200 p-3">
                  <p class="text-base-content/50">Running</p>
                  <p class="mt-1 text-lg font-semibold tabular-nums">
                    {@overview.running_sync_count}
                  </p>
                </div>
                <div class="rounded-lg border border-base-content/10 bg-base-200 p-3">
                  <p class="text-base-content/50">Failed</p>
                  <p class="mt-1 text-lg font-semibold tabular-nums">
                    {@overview.failed_sync_count}
                  </p>
                </div>
              </div>
            </div>
          </.section>

          <.section title="Receivables" description="Open customer money.">
            <div class="grid grid-cols-2 gap-2 text-xs">
              <div class="rounded-lg border border-base-content/10 bg-base-200 p-3">
                <p class="text-base-content/50">Open</p>
                <p class="mt-1 text-lg font-semibold tabular-nums">
                  {@overview.open_invoice_count}
                </p>
              </div>
              <div class="rounded-lg border border-base-content/10 bg-base-200 p-3">
                <p class="text-base-content/50">Unapplied</p>
                <p class="mt-1 text-sm font-semibold">
                  {format_amount(@overview.unapplied_payment_total)}
                </p>
              </div>
            </div>
          </.section>

          <.section title="Automation" description="Bank rules applied after import.">
            <div class="rounded-lg border border-base-content/10 bg-base-200 p-3">
              <div class="flex items-center justify-between gap-3">
                <div>
                  <p class="text-sm font-semibold text-base-content">
                    {@overview.enabled_bank_rule_count} enabled
                  </p>
                  <p class="mt-1 text-xs text-base-content/55">
                    {@overview.bank_rule_count} total rules.
                  </p>
                </div>
                <.button navigate={~p"/finance/banking/rules"}>
                  Manage
                </.button>
              </div>
            </div>
          </.section>
        </aside>
      </div>
    </.page>
    """
  end

  attr :action, :map, required: true

  defp action_item(assigns) do
    ~H"""
    <.link
      navigate={@action.path}
      class="block rounded-lg border border-base-content/10 bg-base-200 p-3 transition hover:border-primary/30 hover:bg-primary/5"
    >
      <div class="flex items-start gap-3">
        <div class={[
          "flex size-9 shrink-0 items-center justify-center rounded-md",
          priority_icon_class(@action.priority)
        ]}>
          <.icon name={@action.icon} class="size-4" />
        </div>
        <div class="min-w-0">
          <div class="flex flex-wrap items-center gap-2">
            <p class="text-sm font-semibold text-base-content">{@action.title}</p>
            <.status_badge status={priority_variant(@action.priority)}>
              {format_atom(@action.priority)}
            </.status_badge>
          </div>
          <p class="mt-1 text-xs leading-5 text-base-content/60">
            {@action.description}
          </p>
        </div>
      </div>
    </.link>
    """
  end

  defp load_overview(socket) do
    overview = Finance.get_finance_overview_workspace!(actor: socket.assigns.current_user)
    assign(socket, :overview, overview)
  end

  defp sync_title(nil), do: "No sync runs yet"
  defp sync_title(sync_run), do: format_atom(sync_run.source)

  defp sync_description(nil),
    do: "Manual, scheduled, and webhook-triggered pulls will appear here."

  defp sync_description(sync_run) do
    "Started #{format_datetime(sync_run.started_at)}"
  end

  defp sync_status_variant(nil), do: :default
  defp sync_status_variant(%{status: :succeeded}), do: :success
  defp sync_status_variant(%{status: :failed}), do: :error
  defp sync_status_variant(%{status: :partial}), do: :warning
  defp sync_status_variant(%{status: :running}), do: :info
  defp sync_status_variant(_), do: :default

  defp sync_status_label(nil), do: "Not synced"
  defp sync_status_label(sync_run), do: format_atom(sync_run.status)

  defp priority_variant(:high), do: :error
  defp priority_variant(:medium), do: :warning
  defp priority_variant(_), do: :default

  defp priority_icon_class(:high), do: "bg-error/10 text-error"
  defp priority_icon_class(:medium), do: "bg-warning/10 text-warning"
  defp priority_icon_class(_), do: "bg-primary/10 text-primary"
end
