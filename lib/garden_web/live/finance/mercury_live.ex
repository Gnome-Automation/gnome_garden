defmodule GnomeGardenWeb.Finance.MercuryLive do
  use GnomeGardenWeb, :live_view
  use Cinder.UrlSync

  import GnomeGardenWeb.Finance.Helpers

  require Logger

  alias GnomeGarden.Finance.BankSyncWorker
  alias GnomeGarden.Mercury

  @direction_options [
    {"Money in", :money_in},
    {"Money out", :money_out},
    {"Both", :both}
  ]

  @amount_operator_options [
    {"Any amount", ""},
    {"Less than", :lt},
    {"Greater than", :gt},
    {"Less than or equal", :lte},
    {"Greater than or equal", :gte},
    {"Equal to", :eq}
  ]

  @category_options [
    {"Bank fee", :bank_fee},
    {"Internal transfer", :internal_transfer},
    {"Misc income", :misc_income},
    {"Refund", :refund},
    {"Interest income", :interest_income},
    {"Owner draw", :owner_draw},
    {"Other", :other}
  ]

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Mercury")
     |> assign(:direction_options, @direction_options)
     |> assign(:amount_operator_options, @amount_operator_options)
     |> assign(:category_options, @category_options)
     |> assign(:syncing?, false)
     |> assign(:rule_error, nil)
     |> assign(:rule_form, default_rule_form())
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
         |> put_flash(:info, "Mercury sync started.")}

      {:error, reason} ->
        Logger.warning("Mercury sync enqueue failed", reason: inspect(reason))
        {:noreply, put_flash(socket, :error, "Could not start Mercury sync.")}
    end
  end

  @impl true
  def handle_event("validate_rule", %{"rule" => params}, socket) do
    {:noreply, assign(socket, :rule_form, Map.merge(default_rule_form(), params))}
  end

  @impl true
  def handle_event("save_rule", %{"rule" => params}, socket) do
    attrs = rule_attrs(params, next_rule_priority(socket.assigns.bank_rules))

    case Mercury.create_bank_rule(attrs, actor: socket.assigns.current_user) do
      {:ok, _rule} ->
        {:noreply,
         socket
         |> put_flash(:info, "Bank rule added.")
         |> assign(:rule_error, nil)
         |> assign(:rule_form, default_rule_form())
         |> load_workspace()}

      {:error, error} ->
        {:noreply,
         socket
         |> assign(:rule_error, error_message(error))
         |> assign(:rule_form, params)}
    end
  end

  @impl true
  def handle_event("delete_rule", %{"id" => id}, socket) do
    rule = Mercury.get_bank_rule!(id, actor: socket.assigns.current_user)
    {:ok, _rule} = Mercury.delete_bank_rule(rule, actor: socket.assigns.current_user)

    {:noreply,
     socket
     |> put_flash(:info, "Bank rule deleted.")
     |> load_workspace()}
  end

  @impl true
  def handle_info(:reload_after_sync, socket) do
    {:noreply,
     socket
     |> assign(:syncing?, false)
     |> load_workspace()
     |> Cinder.refresh_table("mercury-transactions-mobile")
     |> Cinder.refresh_table("mercury-transactions")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.page class="pb-8">
      <.page_header eyebrow="Finance">
        Mercury
        <:subtitle>
          Bank accounts, transactions, and categorization rules synced from Mercury.
        </:subtitle>
        <:actions>
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
          description="Mercury accounts mirrored locally."
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
          description="Synced Mercury transaction records."
          icon="hero-arrows-right-left"
          accent="amber"
        />
        <.stat_card
          title="Unmatched"
          value={Integer.to_string(@unmatched_count)}
          description="Sent transactions without a confident match."
          icon="hero-exclamation-triangle"
          accent="rose"
        />
      </div>

      <div class="grid gap-4 xl:grid-cols-[minmax(0,1fr)_22rem]">
        <.section
          title="Transactions"
          description="Search and sort the local transaction mirror. Matching and reconciliation workflows will build on this table."
          compact
        >
          <div class="rounded-lg border border-base-content/10 bg-base-100">
            <div class="md:hidden">
              <Cinder.collection
                id="mercury-transactions-mobile"
                layout={:list}
                resource={GnomeGarden.Mercury.Transaction}
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
                  load: [:account],
                  sort: [occurred_at: :desc]
                ]}
                empty_message="No Mercury transactions yet."
              >
                <:col field="counterparty_name" search sort label="Counterparty" />
                <:col field="bank_description" search label="Description" />
                <:col field="external_memo" search label="Memo" />
                <:col field="occurred_at" sort label="Date" />
                <:col field="amount" sort label="Amount" />
                <:col field="status" sort label="Status" />
                <:col field="reconciliation_category" sort label="Category" />

                <:item :let={txn}>
                  <div class="rounded-lg border border-base-content/10 bg-base-100 p-3">
                    <div class="flex items-start justify-between gap-3">
                      <div class="min-w-0">
                        <p class="truncate text-sm font-semibold text-base-content">
                          {counterparty(txn)}
                        </p>
                        <p class="mt-0.5 text-xs text-base-content/50">
                          {format_datetime(txn.occurred_at)}
                        </p>
                      </div>
                      <span class={["shrink-0 text-sm", amount_classes(txn.amount)]}>
                        {format_amount(txn.amount)}
                      </span>
                    </div>

                    <p class="mt-2 line-clamp-2 text-xs text-base-content/55">
                      {txn.bank_description || txn.external_memo || txn.mercury_id}
                    </p>

                    <div class="mt-3 flex flex-wrap gap-1.5">
                      <.status_badge status={transaction_status_variant(txn.status)}>
                        {format_atom(txn.status)}
                      </.status_badge>
                      <.status_badge status={match_status_variant(txn.match_confidence)}>
                        {match_status_label(txn.match_confidence)}
                      </.status_badge>
                      <.status_badge :if={txn.reconciliation_category} status={:default}>
                        {format_atom(txn.reconciliation_category)}
                      </.status_badge>
                    </div>
                  </div>
                </:item>

                <:empty>
                  <.empty_state
                    icon="hero-building-library"
                    title="No Mercury transactions yet"
                    description="Run a sync after configuring Mercury credentials."
                  />
                </:empty>
              </Cinder.collection>
            </div>

            <div class="hidden md:block">
              <Cinder.collection
                id="mercury-transactions"
                resource={GnomeGarden.Mercury.Transaction}
                actor={@current_user}
                url_state={@url_state}
                theme={GnomeGardenWeb.CinderTheme}
                page_size={25}
                query_opts={[
                  load: [:account],
                  sort: [occurred_at: :desc]
                ]}
              >
                <:col :let={txn} field="counterparty_name" search sort label="Counterparty">
                  <div class="min-w-0 space-y-1">
                    <p class="truncate font-medium text-base-content">
                      {counterparty(txn)}
                    </p>
                    <p class="truncate text-xs text-base-content/50">
                      {txn.bank_description || txn.external_memo || txn.mercury_id}
                    </p>
                  </div>
                </:col>

                <:col :let={txn} field="occurred_at" sort label="Date">
                  {format_datetime(txn.occurred_at)}
                </:col>

                <:col :let={txn} field="amount" sort label="Amount">
                  <span class={amount_classes(txn.amount)}>{format_amount(txn.amount)}</span>
                </:col>

                <:col :let={txn} field="status" sort label="Status">
                  <div class="flex flex-wrap gap-1.5">
                    <.status_badge status={transaction_status_variant(txn.status)}>
                      {format_atom(txn.status)}
                    </.status_badge>
                    <.status_badge status={match_status_variant(txn.match_confidence)}>
                      {match_status_label(txn.match_confidence)}
                    </.status_badge>
                  </div>
                </:col>

                <:col :let={txn} field="reconciliation_category" sort label="Category">
                  <div class="space-y-1">
                    <p>{format_atom(txn.reconciliation_category)}</p>
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
                    title="No Mercury transactions yet"
                    description="Run a sync after configuring Mercury credentials."
                  />
                </:empty>
              </Cinder.collection>
            </div>
          </div>
        </.section>

        <div class="space-y-4">
          <.section
            title="Accounts"
            description="Routing details stay in company payment destinations; this is the bank mirror."
          >
            <div :if={@accounts == []}>
              <.empty_state
                icon="hero-building-library"
                title="No accounts yet"
                description="Sync Mercury to create account mirrors."
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
                    <p class="text-xs text-base-content/50">{format_atom(account.kind)}</p>
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
            title="Bank Rules"
            description="Rules categorize new synced transactions before manual review."
          >
            <div
              :if={@rule_error}
              class="mb-3 rounded-lg border border-error/20 bg-error/10 px-3 py-2 text-sm text-error"
            >
              {@rule_error}
            </div>

            <form
              id="mercury-rule-form"
              phx-change="validate_rule"
              phx-submit="save_rule"
              class="space-y-3"
            >
              <.input
                name="rule[name]"
                value={@rule_form["name"]}
                label="Rule name"
                placeholder="Customer ACH deposits"
              />
              <.input
                name="rule[counterparty_contains]"
                value={@rule_form["counterparty_contains"]}
                label="Counterparty contains"
                placeholder="customer"
              />
              <div class="grid gap-3 sm:grid-cols-2 xl:grid-cols-1">
                <.input
                  type="select"
                  name="rule[direction]"
                  value={@rule_form["direction"]}
                  label="Direction"
                  options={@direction_options}
                />
                <.input
                  type="select"
                  name="rule[reconciliation_category]"
                  value={@rule_form["reconciliation_category"]}
                  label="Category"
                  options={@category_options}
                />
              </div>
              <div class="grid gap-3 sm:grid-cols-2 xl:grid-cols-1">
                <.input
                  type="select"
                  name="rule[amount_operator]"
                  value={@rule_form["amount_operator"]}
                  label="Amount rule"
                  options={@amount_operator_options}
                />
                <.input
                  name="rule[amount_value]"
                  value={@rule_form["amount_value"]}
                  label="Amount value"
                  placeholder="100.00"
                />
              </div>
              <.input
                name="rule[auto_note]"
                value={@rule_form["auto_note"]}
                label="Auto note"
                placeholder="Categorized from Mercury rule"
              />
              <.button type="submit" variant="primary" class="w-full">Add Rule</.button>
            </form>

            <div class="mt-5 space-y-2">
              <div
                :for={rule <- @bank_rules}
                class="rounded-lg border border-base-content/10 bg-base-200 p-3"
              >
                <div class="flex items-start justify-between gap-3">
                  <div class="min-w-0">
                    <p class="truncate text-sm font-semibold">{rule.name}</p>
                    <p class="text-xs text-base-content/50">
                      {format_atom(rule.direction)} · {format_atom(rule.reconciliation_category)}
                    </p>
                  </div>
                  <button
                    type="button"
                    phx-click="delete_rule"
                    phx-value-id={rule.id}
                    class="rounded-md p-1.5 text-base-content/50 hover:bg-base-300 hover:text-error"
                    aria-label="Delete bank rule"
                  >
                    <.icon name="hero-trash" class="size-4" />
                  </button>
                </div>
                <p class="mt-2 text-xs text-base-content/60">
                  Counterparty {if rule.counterparty_contains,
                    do: "contains #{rule.counterparty_contains}",
                    else: "can be any value"}
                </p>
              </div>

              <p :if={@bank_rules == []} class="text-sm text-base-content/60">
                No bank rules yet.
              </p>
            </div>
          </.section>
        </div>
      </div>
    </.page>
    """
  end

  defp load_workspace(socket) do
    actor = socket.assigns.current_user
    accounts = Mercury.list_mercury_accounts!(actor: actor)
    bank_rules = Mercury.list_bank_rules!(actor: actor)
    transactions = Mercury.list_mercury_transactions!(actor: actor)

    socket
    |> assign(:accounts, accounts)
    |> assign(:bank_rules, bank_rules)
    |> assign(:transaction_count, length(transactions))
    |> assign(:unmatched_count, Enum.count(transactions, &unmatched?/1))
    |> assign(:current_balance, sum_account_balances(accounts))
  end

  defp default_rule_form do
    %{
      "name" => "",
      "direction" => "money_in",
      "counterparty_contains" => "",
      "amount_operator" => "",
      "amount_value" => "",
      "reconciliation_category" => "misc_income",
      "auto_note" => ""
    }
  end

  defp rule_attrs(params, priority) do
    %{
      name: blank_to_nil(params["name"]),
      priority: priority,
      direction: atom_param(params["direction"]),
      counterparty_contains: blank_to_nil(params["counterparty_contains"]),
      amount_operator: atom_param(params["amount_operator"]),
      amount_value: decimal_param(params["amount_value"]),
      reconciliation_category: atom_param(params["reconciliation_category"]),
      auto_note: blank_to_nil(params["auto_note"])
    }
  end

  defp next_rule_priority([]), do: 10

  defp next_rule_priority(rules) do
    rules
    |> Enum.map(&(&1.priority || 0))
    |> Enum.max()
    |> Kernel.+(10)
  end

  defp sum_account_balances(accounts) do
    Enum.reduce(accounts, Decimal.new(0), fn account, total ->
      Decimal.add(total, account.current_balance || Decimal.new(0))
    end)
  end

  defp unmatched?(txn), do: txn.match_confidence in [nil, :unmatched] and txn.status != :pending

  defp counterparty(txn),
    do: txn.counterparty_name || txn.bank_description || "Unknown counterparty"

  defp amount_classes(%Decimal{} = amount) do
    if Decimal.compare(amount, Decimal.new(0)) == :gt do
      "font-medium text-success"
    else
      "font-medium text-error"
    end
  end

  defp amount_classes(_), do: "font-medium"

  defp account_status_variant(:active), do: :success
  defp account_status_variant(:frozen), do: :warning
  defp account_status_variant(:deleted), do: :error
  defp account_status_variant(_), do: :default

  defp transaction_status_variant(:sent), do: :success
  defp transaction_status_variant(:pending), do: :warning
  defp transaction_status_variant(:failed), do: :error
  defp transaction_status_variant(_), do: :default

  defp match_status_variant(value) when value in [:exact, :probable, :possible], do: :success
  defp match_status_variant(_), do: :error

  defp match_status_label(value) when value in [:exact, :probable, :possible], do: "Matched"
  defp match_status_label(_), do: "Unmatched"

  defp atom_param(value) when value in [nil, ""], do: nil
  defp atom_param(value) when is_atom(value), do: value
  defp atom_param(value) when is_binary(value), do: String.to_existing_atom(value)

  defp decimal_param(value) when value in [nil, ""], do: nil

  defp decimal_param(value) do
    Decimal.new(value)
  rescue
    _ -> nil
  end

  defp blank_to_nil(value) when value in [nil, ""], do: nil
  defp blank_to_nil(value), do: value

  defp error_message(error) do
    error
    |> Ash.Error.to_error_class()
    |> Exception.message()
  rescue
    _ -> "Could not save bank rule."
  end
end
