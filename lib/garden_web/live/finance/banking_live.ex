defmodule GnomeGardenWeb.Finance.BankingLive do
  use GnomeGardenWeb, :live_view
  use Cinder.UrlSync

  import GnomeGardenWeb.Finance.Helpers

  require Logger

  alias GnomeGarden.Finance
  alias GnomeGarden.Finance.BankSyncWorker

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Banking")
     |> assign(:syncing?, false)
     |> load_workspace()}
  end

  @impl true
  def handle_params(params, uri, socket) do
    {:noreply, Cinder.UrlSync.handle_params(params, uri, socket)}
  end

  @impl true
  def handle_event("sync", _params, socket) do
    case Oban.insert(
           BankSyncWorker.new(%{
             "provider" => "mercury",
             "environment" => "production",
             "source" => "manual_sync"
           })
         ) do
      {:ok, _job} ->
        Process.send_after(self(), :reload_after_sync, 4_000)

        {:noreply,
         socket
         |> assign(:syncing?, true)
         |> put_flash(:info, "Bank sync started.")}

      {:error, reason} ->
        Logger.warning("Bank sync enqueue failed", reason: inspect(reason))
        {:noreply, put_flash(socket, :error, "Could not start bank sync.")}
    end
  end

  @impl true
  def handle_info(:reload_after_sync, socket) do
    {:noreply,
     socket
     |> assign(:syncing?, false)
     |> load_workspace()
     |> Cinder.refresh_table("bank-transactions-mobile")
     |> Cinder.refresh_table("bank-transactions")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.page class="pb-8">
      <.page_header eyebrow="Finance">
        Banking
        <:subtitle>
          Bank accounts, imported transactions, sync health, and categorization rules.
        </:subtitle>
        <:actions>
          <.button navigate={~p"/finance/banking/rules"}>
            <.icon name="hero-funnel" class="size-4" /> Rules
          </.button>
          <.button navigate={~p"/finance/banking/review"}>
            <.icon name="hero-queue-list" class="size-4" /> Review Queue
          </.button>
          <.button phx-click="sync" disabled={@syncing?} variant="primary">
            <.icon name="hero-arrow-path" class={["size-4", @syncing? && "animate-spin"]} />
            {if @syncing?, do: "Syncing", else: "Sync"}
          </.button>
        </:actions>
      </.page_header>

      <div class="grid grid-cols-2 gap-2 sm:gap-3 xl:grid-cols-4">
        <.stat_card
          title="Accounts"
          value={Integer.to_string(length(@accounts))}
          description="Provider accounts mirrored locally."
          icon="hero-building-library"
        />
        <.stat_card
          title="Balance"
          value={format_amount(@current_balance)}
          description="Current balance across mirrored accounts."
          icon="hero-banknotes"
          accent="sky"
        />
        <.stat_card
          title="Transactions"
          value={Integer.to_string(@transaction_count)}
          description="Synced bank transaction records."
          icon="hero-arrows-right-left"
          accent="amber"
        />
        <.stat_card
          title="Review"
          value={Integer.to_string(@needs_review_count)}
          description="Transactions still needing a decision."
          icon="hero-exclamation-triangle"
          accent="rose"
        />
      </div>

      <div class="grid gap-4 xl:grid-cols-[minmax(0,1fr)_22rem]">
        <.section
          title="Transactions"
          description="Search and sort imported banking activity. Matching and reconciliation workflows build from this queue."
          compact
        >
          <div class="rounded-lg border border-base-content/10 bg-base-100">
            <div class="md:hidden">
              <Cinder.collection
                id="bank-transactions-mobile"
                layout={:list}
                resource={GnomeGarden.Finance.BankTransaction}
                actor={@current_user}
                url_state={@url_state}
                theme={GnomeGardenWeb.CinderTheme}
                page_size={10}
                show_sort={false}
                search={[
                  label: "Search transactions",
                  placeholder: "Search counterparty or memo"
                ]}
                query_opts={[
                  load: [:bank_account]
                ]}
                empty_message="No bank transactions yet."
              >
                <:col field="counterparty_name" search sort label="Counterparty" />
                <:col field="description" search label="Description" />
                <:col field="memo" search label="Memo" />
                <:col field="occurred_at" sort label="Date" />
                <:col field="amount" sort label="Amount" />
                <:col field="status" sort label="Status" />
                <:col field="category" sort label="Category" />

                <:item :let={txn}>
                  <div class="rounded-lg border border-base-content/10 bg-base-100 p-3">
                    <div class="flex items-start justify-between gap-3">
                      <div class="min-w-0">
                        <p class="truncate text-sm font-semibold text-base-content">
                          {bank_transaction_counterparty(txn)}
                        </p>
                        <p class="mt-0.5 text-xs text-base-content/50">
                          {format_datetime(txn.occurred_at)}
                        </p>
                      </div>
                      <span class={["shrink-0 text-sm", bank_amount_classes(txn.amount)]}>
                        {format_amount(txn.amount)}
                      </span>
                    </div>

                    <p class="mt-2 line-clamp-2 text-xs text-base-content/55">
                      {txn.description || txn.memo || txn.provider_transaction_id}
                    </p>

                    <div class="mt-3 flex flex-wrap gap-1.5">
                      <.status_badge status={bank_transaction_status_variant(txn.status)}>
                        {format_atom(txn.status)}
                      </.status_badge>
                      <.status_badge status={bank_review_status_variant(txn.review_status)}>
                        {format_atom(txn.review_status)}
                      </.status_badge>
                      <.status_badge status={bank_match_status_variant(txn.match_status)}>
                        {bank_match_status_label(txn.match_status)}
                      </.status_badge>
                      <.status_badge :if={txn.category != :unknown} status={:default}>
                        {format_atom(txn.category)}
                      </.status_badge>
                    </div>
                  </div>
                </:item>

                <:empty>
                  <.empty_state
                    icon="hero-building-library"
                    title="No bank transactions yet"
                    description="Run a sync after configuring banking credentials."
                  />
                </:empty>
              </Cinder.collection>
            </div>

            <div class="hidden md:block">
              <Cinder.collection
                id="bank-transactions"
                resource={GnomeGarden.Finance.BankTransaction}
                actor={@current_user}
                url_state={@url_state}
                theme={GnomeGardenWeb.CinderTheme}
                page_size={25}
                query_opts={[
                  load: [:bank_account]
                ]}
              >
                <:col :let={txn} field="counterparty_name" search sort label="Counterparty">
                  <div class="min-w-0 space-y-1">
                    <p class="truncate font-medium text-base-content">
                      {bank_transaction_counterparty(txn)}
                    </p>
                    <p class="truncate text-xs text-base-content/50">
                      {txn.description || txn.memo || txn.provider_transaction_id}
                    </p>
                  </div>
                </:col>

                <:col :let={txn} field="occurred_at" sort label="Date">
                  {format_datetime(txn.occurred_at)}
                </:col>

                <:col :let={txn} field="amount" sort label="Amount">
                  <span class={bank_amount_classes(txn.amount)}>{format_amount(txn.amount)}</span>
                </:col>

                <:col :let={txn} field="status" sort label="Status">
                  <div class="flex flex-wrap gap-1.5">
                    <.status_badge status={bank_transaction_status_variant(txn.status)}>
                      {format_atom(txn.status)}
                    </.status_badge>
                    <.status_badge status={bank_review_status_variant(txn.review_status)}>
                      {format_atom(txn.review_status)}
                    </.status_badge>
                    <.status_badge status={bank_match_status_variant(txn.match_status)}>
                      {bank_match_status_label(txn.match_status)}
                    </.status_badge>
                  </div>
                </:col>

                <:col :let={txn} field="category" sort label="Category">
                  <div class="space-y-1">
                    <p>{format_atom(txn.category)}</p>
                    <p
                      :if={txn.reconciliation_note}
                      class="line-clamp-2 text-xs text-base-content/50"
                    >
                      {txn.reconciliation_note}
                    </p>
                  </div>
                </:col>

                <:empty>
                  <.empty_state
                    icon="hero-building-library"
                    title="No bank transactions yet"
                    description="Run a sync after configuring banking credentials."
                  />
                </:empty>
              </Cinder.collection>
            </div>
          </div>
        </.section>

        <div class="space-y-4">
          <.section
            title="Accounts"
            description="Routing details stay in company payment destinations; this is the internal bank mirror."
          >
            <div :if={@accounts == []}>
              <.empty_state
                icon="hero-building-library"
                title="No accounts yet"
                description="Sync banking to create account mirrors."
              />
            </div>

            <div :if={@accounts != []} class="space-y-3">
              <div
                :for={account <- @accounts}
                class="rounded-lg border border-base-content/10 bg-base-200 p-3"
              >
                <div class="flex items-start justify-between gap-3">
                  <div class="min-w-0">
                    <p class="truncate text-sm font-semibold">{account.name}</p>
                    <p class="text-xs text-base-content/50">
                      {format_atom(account.provider)} · {format_atom(account.kind)}
                    </p>
                  </div>
                  <.status_badge status={account_status_variant(account.status)}>
                    {format_atom(account.status)}
                  </.status_badge>
                </div>
                <div class="mt-3 grid grid-cols-2 gap-2 text-xs">
                  <div>
                    <p class="text-base-content/50">Current</p>
                    <p class="font-medium">{format_amount(account.current_balance)}</p>
                  </div>
                  <div>
                    <p class="text-base-content/50">Available</p>
                    <p class="font-medium">{format_amount(account.available_balance)}</p>
                  </div>
                </div>
              </div>
            </div>
          </.section>

          <.section
            title="Sync Health"
            description="Provider pulls and webhook hints recorded by Finance."
          >
            <div
              :if={@latest_sync_run}
              class="rounded-lg border border-base-content/10 bg-base-200 p-3"
            >
              <div class="flex items-start justify-between gap-3">
                <div class="min-w-0">
                  <p class="truncate text-sm font-semibold">
                    {format_sync_source(@latest_sync_run.source)}
                  </p>
                  <p class="text-xs text-base-content/50">
                    Started {format_datetime(@latest_sync_run.started_at)}
                  </p>
                </div>
                <.status_badge status={sync_run_status_variant(@latest_sync_run.status)}>
                  {format_atom(@latest_sync_run.status)}
                </.status_badge>
              </div>

              <div class="mt-3 grid grid-cols-3 gap-2 text-xs">
                <div>
                  <p class="text-base-content/50">Seen</p>
                  <p class="font-medium">{@latest_sync_run.transactions_seen_count || 0}</p>
                </div>
                <div>
                  <p class="text-base-content/50">Created</p>
                  <p class="font-medium">{@latest_sync_run.transactions_created_count || 0}</p>
                </div>
                <div>
                  <p class="text-base-content/50">Updated</p>
                  <p class="font-medium">{@latest_sync_run.transactions_updated_count || 0}</p>
                </div>
              </div>

              <p
                :if={@latest_sync_run.error_message}
                class="mt-3 line-clamp-3 text-xs text-error"
              >
                {@latest_sync_run.error_message}
              </p>
            </div>

            <div :if={is_nil(@latest_sync_run)}>
              <.empty_state
                icon="hero-arrow-path"
                title="No sync runs yet"
                description="Manual syncs, webhook-triggered pulls, and scheduled pulls will appear here."
              />
            </div>

            <div :if={@integration_events != []} class="mt-4 space-y-2">
              <p class="text-xs font-semibold uppercase text-base-content/50">
                Recent events
              </p>
              <div
                :for={event <- Enum.take(@integration_events, 4)}
                class="rounded-lg border border-base-content/10 bg-base-100 px-3 py-2"
              >
                <div class="flex items-start justify-between gap-3">
                  <div class="min-w-0">
                    <p class="truncate text-xs font-medium">{event.event_type}</p>
                    <p class="text-xs text-base-content/50">
                      {format_atom(event.source)} · {format_datetime(event.received_at)}
                    </p>
                  </div>
                  <.status_badge status={integration_event_status_variant(event.status)}>
                    {format_atom(event.status)}
                  </.status_badge>
                </div>
              </div>
            </div>
          </.section>

          <.section
            title="Automation"
            description="Rules stay in the banking rules workspace so daily banking stays focused on balances, sync health, and transaction review."
          >
            <div class="rounded-lg border border-base-content/10 bg-base-200 p-3">
              <div class="flex items-start justify-between gap-3">
                <div class="min-w-0">
                  <p class="text-sm font-semibold text-base-content">Bank Rules</p>
                  <p class="mt-1 text-xs leading-5 text-base-content/60">
                    {@bank_rule_count} configured, {@enabled_bank_rule_count} enabled.
                  </p>
                </div>
                <.button navigate={~p"/finance/banking/rules"}>
                  <.icon name="hero-funnel" class="size-4" /> Manage
                </.button>
              </div>
            </div>
          </.section>
        </div>
      </div>
    </.page>
    """
  end

  defp load_workspace(socket) do
    workspace = Finance.get_banking_workspace!(actor: socket.assigns.current_user)

    socket
    |> assign(:accounts, workspace.accounts)
    |> assign(:bank_rule_count, length(workspace.bank_rules))
    |> assign(:enabled_bank_rule_count, Enum.count(workspace.bank_rules, & &1.enabled))
    |> assign(:transaction_count, workspace.transaction_count)
    |> assign(:needs_review_count, workspace.needs_review_count)
    |> assign(:current_balance, workspace.current_balance)
    |> assign(:sync_runs, workspace.sync_runs)
    |> assign(:integration_events, workspace.integration_events)
    |> assign(:latest_sync_run, workspace.latest_sync_run)
    |> assign(:latest_integration_event, workspace.latest_integration_event)
    |> assign(:running_sync_count, workspace.running_sync_count)
    |> assign(:failed_sync_count, workspace.failed_sync_count)
    |> assign(:failed_integration_event_count, workspace.failed_integration_event_count)
  end

  defp account_status_variant(:active), do: :success
  defp account_status_variant(:error), do: :error
  defp account_status_variant(:closed), do: :error
  defp account_status_variant(_), do: :default

  defp sync_run_status_variant(:succeeded), do: :success
  defp sync_run_status_variant(:failed), do: :error
  defp sync_run_status_variant(:partial), do: :warning
  defp sync_run_status_variant(:running), do: :info
  defp sync_run_status_variant(_), do: :default

  defp integration_event_status_variant(:processed), do: :success
  defp integration_event_status_variant(:failed), do: :error
  defp integration_event_status_variant(:processing), do: :info
  defp integration_event_status_variant(:ignored), do: :default
  defp integration_event_status_variant(_), do: :warning

  defp format_sync_source(:manual_sync), do: "Manual sync"
  defp format_sync_source(:scheduled_sync), do: "Scheduled sync"
  defp format_sync_source(:webhook), do: "Webhook sync"
  defp format_sync_source(:operator), do: "Operator sync"
  defp format_sync_source(source), do: format_atom(source)
end
