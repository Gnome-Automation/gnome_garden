defmodule GnomeGardenWeb.Finance.BankAccountLive do
  use GnomeGardenWeb, :live_view

  import GnomeGardenWeb.Finance.Helpers

  require Logger

  alias GnomeGarden.Finance
  alias GnomeGarden.Finance.BankSyncWorker

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Bank Account")
     |> assign(:syncing?, false)
     |> load_workspace(id)}
  end

  @impl true
  def handle_event("sync_account", _params, socket) do
    case socket.assigns do
      %{account_missing?: true} ->
        {:noreply, socket}

      %{account: account} ->
        case Oban.insert(
               BankSyncWorker.new(%{
                 "bank_connection_id" => account.bank_connection_id,
                 "source" => "operator"
               })
             ) do
          {:ok, _job} ->
            Process.send_after(self(), {:reload_after_sync, account.id}, 4_000)

            {:noreply,
             socket
             |> assign(:syncing?, true)
             |> put_flash(:info, "Account sync started.")}

          {:error, reason} ->
            Logger.warning("Bank account sync enqueue failed", reason: inspect(reason))
            {:noreply, put_flash(socket, :error, "Could not start account sync.")}
        end
    end
  end

  @impl true
  def handle_info({:reload_after_sync, account_id}, socket) do
    {:noreply,
     socket
     |> assign(:syncing?, false)
     |> load_workspace(account_id)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.page class="pb-8">
      <%= if @account_missing? do %>
        <.page_header eyebrow="Finance">
          Bank account not found
          <:subtitle>
            This account may have been deleted, or the link may point to an unknown account.
          </:subtitle>
          <:actions>
            <.button navigate={~p"/finance/banking"}>
              <.icon name="hero-building-library" class="size-4" /> Banking
            </.button>
            <.button navigate={~p"/finance/banking/review"}>
              <.icon name="hero-queue-list" class="size-4" /> Review Queue
            </.button>
          </:actions>
        </.page_header>

        <.section
          title="Account unavailable"
          description="Return to banking to choose an active account or continue review work from the queue."
        >
          <.empty_state
            icon="hero-exclamation-triangle"
            title="No account details to show"
            description="The requested bank account could not be loaded."
            class="py-10"
          />
        </.section>
      <% else %>
        <.page_header eyebrow="Finance">
          {@account.name}
          <:subtitle>
            Provider-neutral account detail, cash position, recent activity, and sync audit.
          </:subtitle>
          <:actions>
            <.button navigate={~p"/finance/banking"}>
              <.icon name="hero-building-library" class="size-4" /> Banking
            </.button>
            <.button navigate={~p"/finance/banking/review"}>
              <.icon name="hero-queue-list" class="size-4" /> Review Queue
            </.button>
            <.button navigate={~p"/finance/banking/sync-runs"}>
              <.icon name="hero-arrow-path" class="size-4" /> Sync Health
            </.button>
            <.button
              id="sync-bank-account"
              phx-click="sync_account"
              disabled={@syncing?}
              variant="primary"
            >
              <.icon name="hero-arrow-path" class={["size-4", @syncing? && "animate-spin"]} />
              {if @syncing?, do: "Syncing", else: "Sync Now"}
            </.button>
          </:actions>
        </.page_header>

        <div class="grid grid-cols-2 gap-2 sm:gap-3 xl:grid-cols-4">
          <.stat_card
            title="Current"
            value={format_amount(@workspace.current_balance)}
            description={"Balance as of #{format_datetime(@account.balance_as_of)}."}
            icon="hero-banknotes"
          />
          <.stat_card
            title="Available"
            value={format_amount(@workspace.available_balance)}
            description="Available cash reported by the provider."
            icon="hero-wallet"
            accent="sky"
          />
          <.stat_card
            title="Review"
            value={Integer.to_string(@workspace.needs_review_count)}
            description="Recent transactions needing review."
            icon="hero-queue-list"
            accent="amber"
          />
          <.stat_card
            title="Activity"
            value={Integer.to_string(@workspace.transaction_count)}
            description="Recent account transactions loaded."
            icon="hero-arrows-right-left"
            accent="rose"
          />
        </div>

        <div class="grid gap-4 xl:grid-cols-[minmax(0,1fr)_24rem]">
          <div class="space-y-4">
            <.section
              title="Recent Transactions"
              description="The latest provider-neutral activity mirrored for this account."
              compact
            >
              <div :if={@workspace.transactions == []} class="p-3 sm:p-4">
                <.empty_state
                  icon="hero-arrows-right-left"
                  title="No transactions yet"
                  description="Run a bank sync after the provider connection is configured."
                />
              </div>

              <div :if={@workspace.transactions != []} class="md:hidden">
                <div class="divide-y divide-base-content/10">
                  <.transaction_card
                    :for={transaction <- @workspace.transactions}
                    transaction={transaction}
                  />
                </div>
              </div>

              <div :if={@workspace.transactions != []} class="hidden md:block">
                <div class="overflow-x-auto">
                  <table class="min-w-full divide-y divide-base-content/10 text-sm">
                    <thead class="bg-base-200/60">
                      <tr>
                        <th class="px-4 py-3 text-left text-xs font-semibold uppercase text-base-content/50">
                          Counterparty
                        </th>
                        <th class="px-4 py-3 text-left text-xs font-semibold uppercase text-base-content/50">
                          Date
                        </th>
                        <th class="px-4 py-3 text-left text-xs font-semibold uppercase text-base-content/50">
                          Amount
                        </th>
                        <th class="px-4 py-3 text-left text-xs font-semibold uppercase text-base-content/50">
                          Review
                        </th>
                        <th class="px-4 py-3 text-left text-xs font-semibold uppercase text-base-content/50">
                          Category
                        </th>
                        <th class="px-4 py-3 text-left text-xs font-semibold uppercase text-base-content/50">
                          Actions
                        </th>
                      </tr>
                    </thead>
                    <tbody class="divide-y divide-base-content/10">
                      <tr :for={transaction <- @workspace.transactions} class="bg-base-100">
                        <td class="px-4 py-4 align-top">
                          <div class="min-w-0 space-y-1">
                            <p class="truncate font-medium text-base-content">
                              {bank_transaction_counterparty(transaction)}
                            </p>
                            <p class="truncate text-xs text-base-content/50">
                              {transaction.description || transaction.memo ||
                                transaction.provider_transaction_id}
                            </p>
                          </div>
                        </td>
                        <td class="px-4 py-4 align-top text-base-content/70">
                          {format_datetime(transaction.occurred_at)}
                        </td>
                        <td class="px-4 py-4 align-top">
                          <span class={bank_amount_classes(transaction.amount)}>
                            {format_amount(transaction.amount)}
                          </span>
                        </td>
                        <td class="px-4 py-4 align-top">
                          <div class="flex flex-wrap gap-1.5">
                            <.status_badge status={
                              bank_review_status_variant(transaction.review_status)
                            }>
                              {format_atom(transaction.review_status)}
                            </.status_badge>
                            <.status_badge status={
                              bank_match_status_variant(transaction.match_status)
                            }>
                              {bank_match_status_label(transaction.match_status)}
                            </.status_badge>
                          </div>
                        </td>
                        <td class="px-4 py-4 align-top text-base-content/70">
                          {format_atom(transaction.category)}
                        </td>
                        <td class="px-4 py-4 align-top">
                          <.button navigate={~p"/finance/banking/transactions/#{transaction.id}"}>
                            <.icon name="hero-eye" class="size-4" /> Open
                          </.button>
                        </td>
                      </tr>
                    </tbody>
                  </table>
                </div>
              </div>
            </.section>

            <.section
              title="Sync Activity"
              description="Recent provider pulls and account-scoped integration events."
            >
              <div class="grid gap-3 md:grid-cols-2">
                <div>
                  <p class="mb-2 text-xs font-semibold uppercase text-base-content/50">
                    Sync runs
                  </p>
                  <div :if={@workspace.sync_runs == []}>
                    <.empty_state
                      icon="hero-arrow-path"
                      title="No sync runs"
                      description="Connection sync history will appear here."
                      class="py-6"
                    />
                  </div>
                  <div :if={@workspace.sync_runs != []} class="space-y-2">
                    <.sync_run_card :for={sync_run <- @workspace.sync_runs} sync_run={sync_run} />
                  </div>
                </div>

                <div>
                  <p class="mb-2 text-xs font-semibold uppercase text-base-content/50">
                    Events
                  </p>
                  <div :if={@workspace.integration_events == []}>
                    <.empty_state
                      icon="hero-bolt"
                      title="No account events"
                      description="Webhook and provider event hints for this account will appear here."
                      class="py-6"
                    />
                  </div>
                  <div :if={@workspace.integration_events != []} class="space-y-2">
                    <.integration_event_card
                      :for={event <- @workspace.integration_events}
                      event={event}
                    />
                  </div>
                </div>
              </div>
            </.section>
          </div>

          <aside class="space-y-4">
            <.section title="Account" description="Internal mirror of a provider account.">
              <div class="rounded-lg border border-base-content/10 bg-base-200 p-3">
                <div class="flex items-start justify-between gap-3">
                  <div class="min-w-0">
                    <p class="truncate text-sm font-semibold text-base-content">
                      {@account.nickname || @account.name}
                    </p>
                    <p class="mt-1 text-xs text-base-content/55">
                      {@account.name}
                    </p>
                  </div>
                  <.status_badge status={account_status_variant(@account.status)}>
                    {format_atom(@account.status)}
                  </.status_badge>
                </div>

                <dl class="mt-4 grid grid-cols-2 gap-3 text-xs">
                  <div>
                    <dt class="text-base-content/45">Provider</dt>
                    <dd class="font-medium">{format_atom(@account.provider)}</dd>
                  </div>
                  <div>
                    <dt class="text-base-content/45">Kind</dt>
                    <dd class="font-medium">{format_atom(@account.kind)}</dd>
                  </div>
                  <div>
                    <dt class="text-base-content/45">Currency</dt>
                    <dd class="font-medium">{@account.currency_code}</dd>
                  </div>
                  <div>
                    <dt class="text-base-content/45">Last 4</dt>
                    <dd class="font-medium">{@account.account_number_last4 || "-"}</dd>
                  </div>
                </dl>
              </div>
            </.section>

            <.section title="Provider Connection" description="Connection that feeds this mirror.">
              <div class="rounded-lg border border-base-content/10 bg-base-200 p-3">
                <div class="flex items-start justify-between gap-3">
                  <div class="min-w-0">
                    <p class="truncate text-sm font-semibold text-base-content">
                      {connection_name(@bank_connection)}
                    </p>
                    <p class="mt-1 text-xs text-base-content/55">
                      {connection_provider(@bank_connection)}
                    </p>
                  </div>
                  <.status_badge status={connection_status_variant(@bank_connection)}>
                    {connection_status_label(@bank_connection)}
                  </.status_badge>
                </div>
              </div>
            </.section>

            <.section
              title="Payment Destination"
              description="Masked routing information. Full operational destination management belongs in company payment destinations."
            >
              <details class="rounded-lg border border-base-content/10 bg-base-200 p-3">
                <summary class="cursor-pointer text-sm font-semibold text-base-content">
                  Show masked details
                </summary>
                <dl class="mt-4 grid gap-3 text-xs">
                  <div>
                    <dt class="text-base-content/45">ACH routing</dt>
                    <dd class="font-medium">{masked_value(@account.routing_number)}</dd>
                  </div>
                  <div>
                    <dt class="text-base-content/45">Wire routing</dt>
                    <dd class="font-medium">{masked_value(@account.wire_routing_number)}</dd>
                  </div>
                  <div>
                    <dt class="text-base-content/45">Account number</dt>
                    <dd class="font-medium">{masked_account(@account.account_number_last4)}</dd>
                  </div>
                </dl>
              </details>
            </.section>

            <.section title="Actions" description="Continue account review from focused workspaces.">
              <div class="grid gap-2">
                <.button navigate={~p"/finance/banking/review"} class="w-full">
                  <.icon name="hero-queue-list" class="size-4" /> Open Review Queue
                </.button>
                <.button navigate={~p"/finance/banking/rules"} class="w-full">
                  <.icon name="hero-funnel" class="size-4" /> Manage Rules
                </.button>
                <.button navigate={~p"/finance/banking/sync-runs"} class="w-full">
                  <.icon name="hero-arrow-path" class="size-4" /> Open Sync Health
                </.button>
                <.button
                  id="sync-bank-account-sidebar"
                  phx-click="sync_account"
                  disabled={@syncing?}
                  class="w-full"
                  variant="primary"
                >
                  <.icon name="hero-arrow-path" class={["size-4", @syncing? && "animate-spin"]} />
                  {if @syncing?, do: "Syncing", else: "Sync Now"}
                </.button>
              </div>
            </.section>
          </aside>
        </div>
      <% end %>
    </.page>
    """
  end

  attr :transaction, :map, required: true

  defp transaction_card(assigns) do
    ~H"""
    <div class="space-y-3 bg-base-100 p-3">
      <div class="flex items-start justify-between gap-3">
        <div class="min-w-0">
          <p class="truncate text-sm font-semibold text-base-content">
            {bank_transaction_counterparty(@transaction)}
          </p>
          <p class="mt-0.5 text-xs text-base-content/50">
            {format_datetime(@transaction.occurred_at)}
          </p>
        </div>
        <span class={["shrink-0 text-sm", bank_amount_classes(@transaction.amount)]}>
          {format_amount(@transaction.amount)}
        </span>
      </div>

      <p class="line-clamp-2 text-xs text-base-content/55">
        {@transaction.description || @transaction.memo || @transaction.provider_transaction_id}
      </p>

      <div class="flex flex-wrap gap-1.5">
        <.status_badge status={bank_transaction_status_variant(@transaction.status)}>
          {format_atom(@transaction.status)}
        </.status_badge>
        <.status_badge status={bank_review_status_variant(@transaction.review_status)}>
          {format_atom(@transaction.review_status)}
        </.status_badge>
        <.status_badge status={bank_match_status_variant(@transaction.match_status)}>
          {bank_match_status_label(@transaction.match_status)}
        </.status_badge>
      </div>

      <.link
        navigate={~p"/finance/banking/transactions/#{@transaction.id}"}
        class="inline-flex items-center gap-1 text-xs font-medium text-primary"
      >
        Open transaction <.icon name="hero-arrow-right" class="size-3.5" />
      </.link>
    </div>
    """
  end

  attr :sync_run, :map, required: true

  defp sync_run_card(assigns) do
    ~H"""
    <div class="rounded-lg border border-base-content/10 bg-base-200 p-3">
      <div class="flex items-start justify-between gap-3">
        <div class="min-w-0">
          <p class="text-sm font-semibold text-base-content">{format_atom(@sync_run.source)}</p>
          <p class="mt-1 text-xs text-base-content/55">
            {format_datetime(@sync_run.started_at)}
          </p>
        </div>
        <.status_badge status={sync_run_status_variant(@sync_run.status)}>
          {format_atom(@sync_run.status)}
        </.status_badge>
      </div>

      <div class="mt-3 grid grid-cols-3 gap-2 text-xs">
        <div>
          <p class="text-base-content/45">Seen</p>
          <p class="font-semibold">{@sync_run.transactions_seen_count || 0}</p>
        </div>
        <div>
          <p class="text-base-content/45">Created</p>
          <p class="font-semibold">{@sync_run.transactions_created_count || 0}</p>
        </div>
        <div>
          <p class="text-base-content/45">Updated</p>
          <p class="font-semibold">{@sync_run.transactions_updated_count || 0}</p>
        </div>
      </div>
    </div>
    """
  end

  attr :event, :map, required: true

  defp integration_event_card(assigns) do
    ~H"""
    <div class="rounded-lg border border-base-content/10 bg-base-200 p-3">
      <div class="flex items-start justify-between gap-3">
        <div class="min-w-0">
          <p class="truncate text-sm font-semibold text-base-content">{@event.event_type}</p>
          <p class="mt-1 text-xs text-base-content/55">
            {format_atom(@event.source)} · {format_datetime(@event.received_at)}
          </p>
        </div>
        <.status_badge status={integration_event_status_variant(@event.status)}>
          {format_atom(@event.status)}
        </.status_badge>
      </div>
    </div>
    """
  end

  defp load_workspace(socket, id) do
    case Finance.get_bank_account_workspace(id, actor: socket.assigns.current_user) do
      {:ok, workspace} ->
        socket
        |> assign(:page_title, workspace.account.name)
        |> assign(:account_missing?, false)
        |> assign(:workspace, workspace)
        |> assign(:account, workspace.account)
        |> assign(:bank_connection, workspace.bank_connection)

      {:error, error} ->
        if missing_account_error?(error) do
          socket
          |> assign(:page_title, "Bank account not found")
          |> assign(:account_missing?, true)
          |> assign(:requested_account_id, id)
          |> assign(:workspace, nil)
          |> assign(:account, nil)
          |> assign(:bank_connection, nil)
        else
          raise error
        end
    end
  end

  defp missing_account_error?(%Ash.Error.Invalid{errors: errors}) do
    Enum.any?(errors, &missing_account_error?/1)
  end

  defp missing_account_error?(%Ash.Error.Query.NotFound{}), do: true

  defp missing_account_error?(_error), do: false

  defp account_status_variant(:active), do: :success
  defp account_status_variant(:error), do: :error
  defp account_status_variant(:closed), do: :error
  defp account_status_variant(_), do: :default

  defp connection_status_variant(%Ash.NotLoaded{}), do: :default
  defp connection_status_variant(nil), do: :default
  defp connection_status_variant(%{status: :active}), do: :success
  defp connection_status_variant(%{status: :error}), do: :error
  defp connection_status_variant(%{status: :paused}), do: :warning
  defp connection_status_variant(_), do: :default

  defp connection_status_label(%Ash.NotLoaded{}), do: "-"
  defp connection_status_label(nil), do: "-"
  defp connection_status_label(%{status: status}), do: format_atom(status)

  defp connection_name(%Ash.NotLoaded{}), do: "Unknown connection"
  defp connection_name(nil), do: "Unknown connection"
  defp connection_name(%{name: name}) when is_binary(name), do: name
  defp connection_name(_), do: "Unknown connection"

  defp connection_provider(%Ash.NotLoaded{}), do: "-"
  defp connection_provider(nil), do: "-"

  defp connection_provider(%{provider: provider, environment: environment}) do
    "#{format_atom(provider)} · #{format_atom(environment)}"
  end

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

  defp masked_value(nil), do: "-"

  defp masked_value(value) when is_binary(value) do
    visible = String.slice(value, -4, 4)
    "ending #{visible}"
  end

  defp masked_account(nil), do: "-"
  defp masked_account(last4), do: "****#{last4}"
end
