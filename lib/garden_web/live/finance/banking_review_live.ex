defmodule GnomeGardenWeb.Finance.BankingReviewLive do
  use GnomeGardenWeb, :live_view
  use Cinder.UrlSync

  import GnomeGardenWeb.Finance.Helpers

  alias GnomeGarden.Finance
  alias Phoenix.LiveView.JS

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Bank Review Queue")
     |> assign(:category_options, bank_transaction_category_options())
     |> assign(:category_dialog, nil)
     |> assign(:category_form, default_category_form())
     |> assign_queue_summary()}
  end

  @impl true
  def handle_params(params, uri, socket) do
    {:noreply, Cinder.UrlSync.handle_params(params, uri, socket)}
  end

  @impl true
  def handle_event("open_category", %{"id" => id}, socket) do
    transaction = Finance.get_bank_transaction!(id, actor: socket.assigns.current_user)

    {:noreply,
     socket
     |> assign(:category_dialog, transaction)
     |> assign(:category_form, %{
       "category" => Atom.to_string(transaction.category || :misc_income),
       "reconciliation_note" => transaction.reconciliation_note || ""
     })}
  end

  def handle_event("close_category", _params, socket) do
    {:noreply,
     socket
     |> assign(:category_dialog, nil)
     |> assign(:category_form, default_category_form())}
  end

  def handle_event("validate_category", %{"category" => params}, socket) do
    {:noreply, assign(socket, :category_form, Map.merge(default_category_form(), params))}
  end

  def handle_event("save_category", %{"category" => params}, socket) do
    transaction = socket.assigns.category_dialog

    attrs = %{
      category: atom_param(params["category"]),
      reconciliation_note: blank_to_nil(params["reconciliation_note"])
    }

    case Finance.categorize_bank_transaction(transaction, attrs,
           actor: socket.assigns.current_user
         ) do
      {:ok, _transaction} ->
        {:noreply,
         socket
         |> put_flash(:info, "Transaction categorized.")
         |> close_and_refresh()}

      {:error, error} ->
        {:noreply, put_flash(socket, :error, error_message(error))}
    end
  end

  def handle_event("mark_reviewed", %{"id" => id}, socket) do
    transaction = Finance.get_bank_transaction!(id, actor: socket.assigns.current_user)

    case Finance.mark_bank_transaction_reviewed(
           transaction,
           %{reconciliation_note: "Reviewed from bank queue"},
           actor: socket.assigns.current_user
         ) do
      {:ok, _transaction} ->
        {:noreply,
         socket
         |> put_flash(:info, "Transaction marked reviewed.")
         |> refresh_queue()}

      {:error, error} ->
        {:noreply, put_flash(socket, :error, error_message(error))}
    end
  end

  def handle_event("ignore", %{"id" => id}, socket) do
    transaction = Finance.get_bank_transaction!(id, actor: socket.assigns.current_user)

    case Finance.ignore_bank_transaction(
           transaction,
           %{reconciliation_note: "Ignored from bank queue"},
           actor: socket.assigns.current_user
         ) do
      {:ok, _transaction} ->
        {:noreply,
         socket
         |> put_flash(:info, "Transaction ignored.")
         |> refresh_queue()}

      {:error, error} ->
        {:noreply, put_flash(socket, :error, error_message(error))}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.page class="pb-8">
      <.page_header eyebrow="Finance">
        Bank Review Queue
        <:subtitle>
          Clear imported transactions that still need a human finance decision.
        </:subtitle>
        <:actions>
          <.button navigate={~p"/finance/banking"}>
            <.icon name="hero-arrow-left" class="size-4" /> Banking
          </.button>
        </:actions>
      </.page_header>

      <div class="grid grid-cols-3 gap-2 sm:gap-3">
        <.stat_card
          title="Queue"
          value={Integer.to_string(@queue_count)}
          description="Transactions needing review."
          icon="hero-queue-list"
        />
        <.stat_card
          title="Money In"
          value={Integer.to_string(@credit_count)}
          description="Credits to classify or match."
          icon="hero-arrow-down-tray"
          accent="sky"
        />
        <.stat_card
          title="Money Out"
          value={Integer.to_string(@debit_count)}
          description="Debits to categorize."
          icon="hero-arrow-up-tray"
          accent="amber"
        />
      </div>

      <.section
        title="Transactions Needing Review"
        description="Use quick actions for obvious rows. Categorize anything that should leave the queue with a finance category."
        compact
      >
        <div class="rounded-lg border border-base-content/10 bg-base-100">
          <div class="md:hidden">
            <Cinder.collection
              id="bank-review-mobile"
              layout={:list}
              resource={GnomeGarden.Finance.BankTransaction}
              action={:needs_review_page}
              actor={@current_user}
              url_state={@url_state}
              theme={GnomeGardenWeb.CinderTheme}
              page_size={10}
              show_sort={false}
              search={[
                label: "Search queue",
                placeholder: "Search counterparty or memo"
              ]}
              query_opts={[
                load: [:bank_account]
              ]}
              empty_message="No bank transactions need review."
            >
              <:col field="counterparty_name" search sort label="Counterparty" />
              <:col field="description" search label="Description" />
              <:col field="memo" search label="Memo" />
              <:col field="occurred_at" sort label="Date" />
              <:col field="amount" sort label="Amount" />
              <:col field="direction" sort label="Direction" />
              <:col field="category" sort label="Category" />

              <:item :let={txn}>
                <.review_card transaction={txn} />
              </:item>

              <:empty>
                <.empty_state
                  icon="hero-check-circle"
                  title="Queue is clear"
                  description="New synced transactions that need a decision will appear here."
                />
              </:empty>
            </Cinder.collection>
          </div>

          <div class="hidden md:block">
            <Cinder.collection
              id="bank-review"
              resource={GnomeGarden.Finance.BankTransaction}
              action={:needs_review_page}
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

              <:col :let={txn} field="category" sort label="Status">
                <div class="flex flex-wrap gap-1.5">
                  <.status_badge status={bank_review_status_variant(txn.review_status)}>
                    {format_atom(txn.review_status)}
                  </.status_badge>
                  <.status_badge status={bank_match_status_variant(txn.match_status)}>
                    {bank_match_status_label(txn.match_status)}
                  </.status_badge>
                  <.status_badge status={:default}>
                    {format_atom(txn.category)}
                  </.status_badge>
                </div>
              </:col>

              <:col :let={txn} label="Actions">
                <.review_actions transaction={txn} />
              </:col>

              <:empty>
                <.empty_state
                  icon="hero-check-circle"
                  title="Queue is clear"
                  description="New synced transactions that need a decision will appear here."
                />
              </:empty>
            </Cinder.collection>
          </div>
        </div>
      </.section>

      <.modal
        :if={@category_dialog}
        id="bank-transaction-category-modal"
        on_cancel={JS.push("close_category")}
      >
        <:title>Categorize Transaction</:title>

        <div class="space-y-1">
          <p class="text-sm font-semibold text-base-content">
            {bank_transaction_counterparty(@category_dialog)}
          </p>
          <p class="text-sm text-base-content/60">
            {format_amount(@category_dialog.amount)} - {format_datetime(@category_dialog.occurred_at)}
          </p>
        </div>

        <form
          id="bank-transaction-category-form"
          phx-change="validate_category"
          phx-submit="save_category"
          class="mt-4 space-y-4"
        >
          <.input
            type="select"
            name="category[category]"
            value={@category_form["category"]}
            label="Category"
            options={@category_options}
          />
          <.input
            type="textarea"
            name="category[reconciliation_note]"
            value={@category_form["reconciliation_note"]}
            label="Review note"
            placeholder="Why this category is correct"
          />

          <div class="flex items-center justify-end gap-2">
            <.button type="button" phx-click="close_category">Cancel</.button>
            <.button type="submit" variant="primary">Save Category</.button>
          </div>
        </form>
      </.modal>
    </.page>
    """
  end

  attr :transaction, :map, required: true

  defp review_card(assigns) do
    ~H"""
    <div class="rounded-lg border border-base-content/10 bg-base-100 p-3">
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

      <p class="mt-2 line-clamp-2 text-xs text-base-content/55">
        {@transaction.description || @transaction.memo || @transaction.provider_transaction_id}
      </p>

      <div class="mt-3 flex flex-wrap gap-1.5">
        <.status_badge status={bank_review_status_variant(@transaction.review_status)}>
          {format_atom(@transaction.review_status)}
        </.status_badge>
        <.status_badge status={bank_match_status_variant(@transaction.match_status)}>
          {bank_match_status_label(@transaction.match_status)}
        </.status_badge>
        <.status_badge status={:default}>
          {format_atom(@transaction.category)}
        </.status_badge>
      </div>

      <div class="mt-3">
        <.review_actions transaction={@transaction} />
      </div>
    </div>
    """
  end

  attr :transaction, :map, required: true

  defp review_actions(assigns) do
    ~H"""
    <div class="flex flex-wrap items-center gap-1.5">
      <button
        type="button"
        phx-click="open_category"
        phx-value-id={@transaction.id}
        class="inline-flex items-center gap-1 rounded-md border border-base-content/10 px-2 py-1 text-xs font-medium text-base-content hover:bg-base-200"
      >
        <.icon name="hero-tag" class="size-3.5" /> Categorize
      </button>
      <button
        type="button"
        phx-click="mark_reviewed"
        phx-value-id={@transaction.id}
        class="inline-flex items-center gap-1 rounded-md border border-success/20 px-2 py-1 text-xs font-medium text-success hover:bg-success/10"
      >
        <.icon name="hero-check" class="size-3.5" /> Reviewed
      </button>
      <button
        type="button"
        phx-click="ignore"
        phx-value-id={@transaction.id}
        class="inline-flex items-center gap-1 rounded-md border border-base-content/10 px-2 py-1 text-xs font-medium text-base-content/60 hover:bg-base-200 hover:text-base-content"
      >
        <.icon name="hero-no-symbol" class="size-3.5" /> Ignore
      </button>
    </div>
    """
  end

  defp assign_queue_summary(socket) do
    transactions =
      Finance.list_bank_transactions_needing_review!(
        actor: socket.assigns.current_user,
        load: [:bank_account]
      )
      |> page_results()

    socket
    |> assign(:queue_count, length(transactions))
    |> assign(:credit_count, Enum.count(transactions, &(&1.direction == :credit)))
    |> assign(:debit_count, Enum.count(transactions, &(&1.direction == :debit)))
  end

  defp close_and_refresh(socket) do
    socket
    |> assign(:category_dialog, nil)
    |> assign(:category_form, default_category_form())
    |> refresh_queue()
  end

  defp refresh_queue(socket) do
    socket
    |> assign_queue_summary()
    |> Cinder.refresh_table("bank-review-mobile")
    |> Cinder.refresh_table("bank-review")
  end

  defp default_category_form do
    %{"category" => "misc_income", "reconciliation_note" => ""}
  end

  defp page_results(%Ash.Page.Keyset{results: results}), do: results
  defp page_results(%Ash.Page.Offset{results: results}), do: results
  defp page_results(results), do: results

  defp atom_param(value) when value in [nil, ""], do: nil
  defp atom_param(value) when is_atom(value), do: value
  defp atom_param(value) when is_binary(value), do: String.to_existing_atom(value)

  defp blank_to_nil(value) when value in [nil, ""], do: nil
  defp blank_to_nil(value), do: value

  defp error_message(error) do
    error
    |> Ash.Error.to_error_class()
    |> Exception.message()
  rescue
    _ -> "Could not update transaction."
  end
end
