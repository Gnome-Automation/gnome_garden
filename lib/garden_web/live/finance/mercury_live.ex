defmodule GnomeGardenWeb.Finance.MercuryLive do
  use GnomeGardenWeb, :live_view

  import GnomeGardenWeb.Finance.Helpers
  import Ash.Query

  require Logger

  alias GnomeGarden.Finance
  alias GnomeGarden.Mercury
  alias GnomeGarden.Mercury.SyncWorker
  alias GnomeGarden.Mercury.PaymentMatcherWorker

  @impl true
  def mount(_params, _session, socket) do
    accounts = Mercury.list_mercury_accounts!(actor: socket.assigns.current_user)

    from_date = Date.add(Date.utc_today(), -30)
    to_date = Date.add(Date.utc_today(), 1)
    filters = %{from_date: from_date, to_date: to_date, status_filter: "all", kind: "all"}

    transactions = load_transactions(socket.assigns.current_user, filters)

    {:ok,
     socket
     |> assign(:page_title, "Mercury")
     |> assign(:accounts, accounts)
     |> assign(:filters, filters)
     |> assign(:transactions, transactions)
     |> assign(:syncing, false)
     |> assign(:auto_matching, false)
     |> assign(:matching_txn, nil)
     |> assign(:open_invoices, [])
     |> assign(:reconciling_txn, nil)
     |> assign(:reconciliation_note, "")
     |> assign(:reconciliation_category, nil)
     |> assign(:reconciliation_error, nil)
     |> assign(:show_export_form, false)}
  end

  @impl true
  def handle_event("sync", _params, socket) do
    case Oban.insert(SyncWorker.new(%{})) do
      {:ok, _job} ->
        Process.send_after(self(), :reset_syncing, 4_000)
        {:noreply,
         socket
         |> assign(:syncing, true)
         |> put_flash(:info, "Sync started — refresh in a few seconds to see latest data.")}

      {:error, reason} ->
        Logger.warning("Mercury sync enqueue failed", reason: inspect(reason))
        {:noreply, put_flash(socket, :error, "Could not start sync.")}
    end
  end

  @impl true
  def handle_info(:reset_syncing, socket) do
    transactions = load_transactions(socket.assigns.current_user, socket.assigns.filters)
    {:noreply, socket |> assign(:syncing, false) |> assign(:transactions, transactions)}
  end

  @impl true
  def handle_event("auto_match", _params, socket) do
    actor = socket.assigns.current_user
    zero = Decimal.new("0")

    unmatched =
      GnomeGarden.Mercury.Transaction
      |> filter(match_confidence in [:unmatched, nil])
      |> filter(status in [:sent, :pending])
      |> filter(amount > ^zero)
      |> Ash.read!(actor: actor, domain: Mercury)

    count = length(unmatched)

    Enum.each(unmatched, fn txn ->
      Oban.insert(PaymentMatcherWorker.new(%{"transaction_id" => txn.id}))
    end)

    Process.send_after(self(), :reset_auto_matching, 4_000)

    msg =
      if count == 0,
        do: "No unmatched transactions to process — either all are matched, or there are no open invoices to match against.",
        else: "Auto-match started for #{count} unmatched transaction#{if count == 1, do: "", else: "s"} — results will update shortly."

    {:noreply,
     socket
     |> assign(:auto_matching, true)
     |> put_flash(:info, msg)}
  end

  @impl true
  def handle_info(:reset_auto_matching, socket) do
    transactions = load_transactions(socket.assigns.current_user, socket.assigns.filters)
    {:noreply, socket |> assign(:auto_matching, false) |> assign(:transactions, transactions)}
  end

  @impl true
  def handle_event("reset_filters", _params, socket) do
    filters = %{
      from_date: Date.add(Date.utc_today(), -30),
      to_date: Date.add(Date.utc_today(), 1),
      status_filter: "all",
      kind: "all"
    }

    transactions = load_transactions(socket.assigns.current_user, filters)
    {:noreply, socket |> assign(:filters, filters) |> assign(:transactions, transactions)}
  end

  @impl true
  def handle_event("toggle_export_form", _params, socket) do
    {:noreply, update(socket, :show_export_form, &(!&1))}
  end

  @impl true
  def handle_event("filter_changed", params, socket) do
    from_date = parse_date(params["from_date"]) || socket.assigns.filters.from_date
    to_date = case parse_date(params["to_date"]) do
      nil -> socket.assigns.filters.to_date
      date -> Date.add(date, 1)
    end

    filters = %{
      from_date: from_date,
      to_date: to_date,
      status_filter: params["status_filter"] || "all",
      kind: params["kind"] || "all"
    }

    transactions = load_transactions(socket.assigns.current_user, filters)

    {:noreply,
     socket
     |> assign(:filters, filters)
     |> assign(:transactions, transactions)}
  end

  @impl true
  def handle_event("open_match_modal", %{"txn_id" => txn_id}, socket) do
    txn = Enum.find(socket.assigns.transactions, &(&1.id == txn_id))

    open_invoices =
      case Finance.list_open_invoices(actor: socket.assigns.current_user) do
        {:ok, invoices} ->
          Enum.filter(invoices, fn inv ->
            bal = inv.balance_amount || inv.total_amount
            bal && Decimal.compare(bal, Decimal.new("0")) == :gt
          end)
        {:error, reason} ->
          Logger.warning("list_open_invoices failed: #{inspect(reason)}")
          []
      end

    {:noreply,
     socket
     |> assign(:matching_txn, txn)
     |> assign(:open_invoices, open_invoices)}
  end

  @impl true
  def handle_event("close_match_modal", _params, socket) do
    {:noreply, socket |> assign(:matching_txn, nil) |> assign(:open_invoices, [])}
  end

  @impl true
  def handle_event("open_reconcile_modal", %{"txn_id" => txn_id}, socket) do
    txn = Enum.find(socket.assigns.transactions, &(&1.id == txn_id))
    {:noreply,
     socket
     |> assign(:reconciling_txn, txn)
     |> assign(:reconciliation_note, "")
     |> assign(:reconciliation_category, nil)
     |> assign(:reconciliation_error, nil)}
  end

  @impl true
  def handle_event("close_reconcile_modal", _params, socket) do
    {:noreply,
     socket
     |> assign(:reconciling_txn, nil)
     |> assign(:reconciliation_note, "")
     |> assign(:reconciliation_category, nil)
     |> assign(:reconciliation_error, nil)}
  end

  @impl true
  def handle_event("reconcile_form_changed", params, socket) do
    cat = case params["category"] do
      "" -> nil
      nil -> nil
      val -> String.to_existing_atom(val)
    end
    {:noreply,
     socket
     |> assign(:reconciliation_category, cat)
     |> assign(:reconciliation_note, params["note"] || "")
     |> assign(:reconciliation_error, nil)}
  end

  @impl true
  def handle_event("confirm_reconcile", params, socket) do
    note = String.trim(params["note"] || socket.assigns.reconciliation_note)
    category = case params["category"] do
      "" -> nil
      nil -> socket.assigns.reconciliation_category
      val -> String.to_existing_atom(val)
    end

    cond do
      is_nil(category) ->
        {:noreply, assign(socket, :reconciliation_error, "A category is required.")}

      note == "" ->
        {:noreply, assign(socket, :reconciliation_error, "A reason is required.")}

      true ->
        txn = socket.assigns.reconciling_txn
        actor = socket.assigns.current_user

        Mercury.update_mercury_transaction(txn, %{
          match_confidence: :exact,
          reconciliation_note: note,
          reconciliation_category: category
        })

        applied =
          txn.payment_matches
          |> Enum.map(& &1.finance_payment)
          |> Enum.reject(&is_nil/1)
          |> Enum.reduce(Decimal.new("0"), &Decimal.add(&1.amount, &2))

        remaining = Decimal.sub(Decimal.abs(txn.amount), applied)

        Mercury.create_transaction_event(%{
          mercury_transaction_id: txn.id,
          action: :reconciled,
          actor_id: actor.id,
          amount: remaining,
          note: "[#{format_reconciliation_category(category)}] #{note}"
        }, actor: actor, authorize?: false)

        transactions = load_transactions(actor, socket.assigns.filters)

        {:noreply,
         socket
         |> assign(:reconciling_txn, nil)
         |> assign(:reconciliation_note, "")
         |> assign(:reconciliation_category, nil)
         |> assign(:transactions, transactions)
         |> put_flash(:info, "Transaction reconciled.")}
    end
  end

  @impl true
  def handle_event("unmatch_transaction", %{"txn_id" => txn_id}, socket) do
    actor = socket.assigns.current_user
    txn = Enum.find(socket.assigns.transactions, &(&1.id == txn_id))

    # Load matches with their payments and payment applications (to find affected invoices)
    matches =
      Ash.read!(
        Ash.Query.filter(GnomeGarden.Mercury.PaymentMatch, mercury_transaction_id == ^txn_id)
        |> Ash.Query.load(finance_payment: :applications),
        actor: actor,
        authorize?: false
      )

    # Collect invoice IDs before deleting anything
    invoice_ids =
      matches
      |> Enum.flat_map(& &1.finance_payment.applications)
      |> Enum.map(& &1.invoice_id)
      |> Enum.uniq()

    # Deleting the payment cascades to delete payment_applications and payment_match
    Enum.each(matches, fn match ->
      Ash.destroy!(match.finance_payment, actor: actor, authorize?: false)
    end)

    # Reopen affected invoices back to :issued, then correct balance for any remaining payment applications
    Enum.each(invoice_ids, fn invoice_id ->
      case Finance.get_invoice(invoice_id, actor: actor, authorize?: false) do
        {:ok, invoice} when invoice.status in [:paid, :partial] ->
          case Finance.reopen_invoice(invoice, actor: actor, authorize?: false) do
            {:ok, draft_invoice} ->
              case Finance.issue_invoice(draft_invoice, actor: actor, authorize?: false) do
                {:ok, issued_invoice} ->
                  # Reload after payments deleted to get correct remaining applied amount
                  case Finance.get_invoice(issued_invoice.id, actor: actor, load: [:applied_amount], authorize?: false) do
                    {:ok, reloaded} ->
                      remaining_applied = reloaded.applied_amount || Decimal.new("0")
                      if Decimal.compare(remaining_applied, Decimal.new("0")) == :gt do
                        total = reloaded.total_amount || Decimal.new("0")
                        corrected = Decimal.sub(total, remaining_applied)
                        corrected = if Decimal.compare(corrected, Decimal.new("0")) == :lt, do: Decimal.new("0"), else: corrected
                        Finance.update_invoice(reloaded, %{balance_amount: corrected}, actor: actor, authorize?: false)
                      end
                    _ -> :ok
                  end
                _ -> :ok
              end
            _ -> :ok
          end
        _ -> :ok
      end
    end)

    Mercury.update_mercury_transaction(txn, %{match_confidence: :unmatched, reconciliation_note: nil})

    Mercury.create_transaction_event(%{
      mercury_transaction_id: txn.id,
      action: :unmatched,
      actor_id: actor.id,
      invoice_ids: invoice_ids
    }, actor: actor, authorize?: false)

    transactions = load_transactions(actor, socket.assigns.filters)
    {:noreply, socket |> assign(:transactions, transactions) |> put_flash(:info, "Transaction unmatched.")}
  end

  @impl true
  def handle_event("apply_manual_match", params, socket) do
    txn = socket.assigns.matching_txn
    actor = socket.assigns.current_user

    selected =
      (params["invoices"] || %{})
      |> Enum.filter(fn {_id, v} -> Map.has_key?(v, "selected") end)
      |> Enum.map(fn {id, v} -> {id, Decimal.new(v["amount"] || "0")} end)
      |> Enum.filter(fn {_id, amt} -> Decimal.compare(amt, Decimal.new("0")) == :gt end)

    if selected == [] do
      {:noreply, put_flash(socket, :error, "Select at least one invoice and enter an amount.")}
    else
      first_id = elem(hd(selected), 0)

      case Finance.get_invoice(first_id, actor: actor) do
        {:ok, first_invoice} ->
          applied_on = DateTime.to_date(txn.occurred_at)
          total_amount = Enum.reduce(selected, Decimal.new("0"), fn {_, amt}, acc -> Decimal.add(acc, amt) end)

          result =
            Ash.transaction(
              [GnomeGarden.Finance.Invoice, GnomeGarden.Mercury.PaymentMatch],
              fn ->
                with {:ok, payment} <-
                       Finance.create_payment(
                         %{
                           organization_id: first_invoice.organization_id,
                           agreement_id: first_invoice.agreement_id,
                           received_on: applied_on,
                           payment_method: kind_to_payment_method(txn.kind),
                           currency_code: first_invoice.currency_code || "USD",
                           amount: total_amount,
                           reference: txn.mercury_id
                         },
                         actor: actor
                       ),
                     {:ok, _apps} <- create_payment_applications(payment.id, selected, applied_on, actor),
                     {:ok, _match} <-
                       Mercury.create_payment_match(
                         %{
                           mercury_transaction_id: txn.id,
                           finance_payment_id: payment.id,
                           match_source: :manual
                         },
                         actor: actor
                       ) do
                  :ok
                else
                  {:error, reason} ->
                    Ash.DataLayer.rollback(GnomeGarden.Finance.Invoice, reason)
                end
              end
            )

          invoice_numbers =
            socket.assigns.open_invoices
            |> Enum.filter(fn inv -> Enum.any?(selected, fn {id, _} -> id == inv.id end) end)
            |> Enum.map(& &1.invoice_number)
            |> Enum.join(", ")

          case result do
            {:ok, :ok} ->
              confidence =
                if Decimal.compare(total_amount, Decimal.abs(txn.amount)) == :lt,
                  do: :unmatched,
                  else: :exact

              Mercury.update_mercury_transaction(txn, %{match_confidence: confidence})

              invoice_ids = Enum.map(selected, fn {id, _} -> id end)
              Mercury.create_transaction_event(%{
                mercury_transaction_id: txn.id,
                action: :matched,
                actor_id: actor.id,
                amount: total_amount,
                invoice_ids: invoice_ids
              }, actor: actor, authorize?: false)

              transactions = load_transactions(actor, socket.assigns.filters)

              {:noreply,
               socket
               |> assign(:matching_txn, nil)
               |> assign(:open_invoices, [])
               |> assign(:transactions, transactions)
               |> put_flash(:info, "Transaction matched to #{invoice_numbers}.")}

            {:error, reason} ->
              {:noreply, put_flash(socket, :error, "Could not apply match: #{inspect(reason)}")}
          end

        {:error, _} ->
          {:noreply, put_flash(socket, :error, "Invoice not found.")}
      end
    end
  end

  defp create_payment_applications(payment_id, selected, applied_on, actor) do
    Enum.reduce_while(selected, {:ok, []}, fn {invoice_id, amount}, {:ok, acc} ->
      case Finance.create_payment_application(
             %{payment_id: payment_id, invoice_id: invoice_id, amount: amount, applied_on: applied_on},
             actor: actor
           ) do
        {:ok, app} -> {:cont, {:ok, [app | acc]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  # -- Private helpers -------------------------------------------------------

  defp load_transactions(user, filters) do
    from_dt = DateTime.new!(filters.from_date, ~T[00:00:00], "Etc/UTC")
    to_dt = DateTime.new!(filters.to_date, ~T[00:00:00], "Etc/UTC")
    zero = Decimal.new("0")

    query =
      GnomeGarden.Mercury.Transaction
      |> filter(occurred_at >= ^from_dt)
      |> filter(occurred_at < ^to_dt)
      |> sort(occurred_at: :desc)

    query =
      case filters.status_filter do
        "matched" -> filter(query, match_confidence in [:exact, :probable, :possible])
        "unmatched" -> filter(query, (is_nil(match_confidence) or match_confidence == :unmatched) and status != :pending)
        "pending" -> filter(query, status == :pending)
        _ -> query
      end

    query =
      case filters.kind do
        "inbound" -> filter(query, amount > ^zero)
        "outbound" -> filter(query, amount < ^zero)
        _ -> query
      end

    Ash.read!(query, actor: user, domain: Mercury, load: [payment_matches: [:finance_payment]])
  end

  defp parse_date(nil), do: nil
  defp parse_date(""), do: nil

  defp parse_date(str) do
    case Date.from_iso8601(str) do
      {:ok, date} -> date
      _ -> nil
    end
  end

  defp account_status_variant(:active), do: :success
  defp account_status_variant(:frozen), do: :warning
  defp account_status_variant(:inactive), do: :default
  defp account_status_variant(:deleted), do: :error
  defp account_status_variant(_), do: :default

  defp match_status_variant(nil), do: :error
  defp match_status_variant(:exact), do: :success
  defp match_status_variant(:probable), do: :success
  defp match_status_variant(:possible), do: :success
  defp match_status_variant(:unmatched), do: :error
  defp match_status_variant(_), do: :default

  defp match_status_label(nil), do: "Unmatched"
  defp match_status_label(:exact), do: "Matched"
  defp match_status_label(:probable), do: "Matched"
  defp match_status_label(:possible), do: "Matched"
  defp match_status_label(:unmatched), do: "Unmatched"
  defp match_status_label(_), do: "—"

  defp format_reconciliation_category(:bank_fee), do: "Bank Fee"
  defp format_reconciliation_category(:internal_transfer), do: "Internal Transfer"
  defp format_reconciliation_category(:misc_income), do: "Misc Income"
  defp format_reconciliation_category(:refund), do: "Refund"
  defp format_reconciliation_category(:interest_income), do: "Interest Income"
  defp format_reconciliation_category(:owner_draw), do: "Owner's Draw"
  defp format_reconciliation_category(:other), do: "Other"
  defp format_reconciliation_category(_), do: "—"

  defp counterparty(txn) do
    txn.counterparty_name || txn.bank_description || "—"
  end

  defp format_occurred_at(nil), do: "—"
  defp format_occurred_at(%DateTime{} = dt), do: format_date(DateTime.to_date(dt))

  defp amount_classes(%Decimal{} = amount) do
    if Decimal.compare(amount, Decimal.new("0")) == :gt do
      "text-emerald-600 dark:text-emerald-400 font-medium"
    else
      "text-rose-600 dark:text-rose-400 font-medium"
    end
  end

  defp kind_to_payment_method(:wire), do: :wire
  defp kind_to_payment_method(:ach), do: :ach
  defp kind_to_payment_method(_), do: :other

  @impl true
  def render(assigns) do
    ~H"""
    <.page class="pb-8">
      <.page_header eyebrow="Finance">
        Mercury
        <:subtitle>
          Bank account balances and transaction history from Mercury.
        </:subtitle>
        <:actions>
          <.button phx-click="toggle_export_form" title="Export transactions as CSV or PDF">
            <.icon name="hero-arrow-down-tray" class="size-4" /> Export
          </.button>
          <.button phx-click="auto_match" disabled={@auto_matching} title="Run the auto-matcher on all unmatched inbound transactions">
            <.icon name="hero-sparkles" class={"size-4 #{if @auto_matching, do: "animate-pulse"}"} />
            {if @auto_matching, do: "Matching…", else: "Auto-Match"}
          </.button>
          <.button phx-click="sync" disabled={@syncing} title="Pull the latest accounts and transactions from Mercury">
            <.icon name="hero-arrow-path" class={"size-4 #{if @syncing, do: "animate-spin"}"} />
            {if @syncing, do: "Syncing…", else: "Sync from Mercury"}
          </.button>
        </:actions>
      </.page_header>

      <%= if @show_export_form do %>
        <div class="mb-6 rounded-lg border border-gray-200 bg-white p-5 shadow-sm dark:border-white/10 dark:bg-white/5">
          <h3 class="text-sm font-semibold text-gray-900 dark:text-white mb-4">Batch Export</h3>
          <form method="get" action={~p"/finance/mercury/batch-export"} target="_blank" class="grid grid-cols-1 gap-4 sm:grid-cols-5 items-end">
            <div>
              <label for="mercury_export_from" class="block text-sm/6 font-medium text-gray-900 dark:text-white">From</label>
              <input
                id="mercury_export_from"
                type="date"
                name="from"
                required
                value={Date.to_iso8601(@filters.from_date)}
                class="mt-1 block w-full rounded-md bg-white px-3 py-1.5 text-base text-gray-900 outline-1 -outline-offset-1 outline-gray-300 focus:outline-2 focus:-outline-offset-2 focus:outline-emerald-600 sm:text-sm/6 dark:bg-white/5 dark:text-white dark:outline-white/10"
              />
            </div>
            <div>
              <label for="mercury_export_to" class="block text-sm/6 font-medium text-gray-900 dark:text-white">To</label>
              <input
                id="mercury_export_to"
                type="date"
                name="to"
                required
                value={Date.to_iso8601(Date.add(@filters.to_date, -1))}
                class="mt-1 block w-full rounded-md bg-white px-3 py-1.5 text-base text-gray-900 outline-1 -outline-offset-1 outline-gray-300 focus:outline-2 focus:-outline-offset-2 focus:outline-emerald-600 sm:text-sm/6 dark:bg-white/5 dark:text-white dark:outline-white/10"
              />
            </div>
            <div>
              <label class="block text-sm/6 font-medium text-gray-900 dark:text-white">Status</label>
              <div class="mt-1 grid grid-cols-1">
                <select
                  name="status_filter"
                  class="col-start-1 row-start-1 w-full appearance-none rounded-md bg-white py-1.5 pr-8 pl-3 text-base text-gray-900 outline-1 -outline-offset-1 outline-gray-300 focus:outline-2 focus:-outline-offset-2 focus:outline-emerald-600 sm:text-sm/6 dark:bg-white/5 dark:text-white dark:outline-white/10"
                >
                  <option value="all">All</option>
                  <option value="matched">Matched</option>
                  <option value="unmatched">Unmatched</option>
                  <option value="pending">Pending</option>
                </select>
                <svg class="pointer-events-none col-start-1 row-start-1 mr-2 size-5 self-center justify-self-end text-gray-500 sm:size-4" viewBox="0 0 16 16" fill="currentColor">
                  <path fill-rule="evenodd" d="M4.22 6.22a.75.75 0 0 1 1.06 0L8 8.94l2.72-2.72a.75.75 0 1 1 1.06 1.06l-3.25 3.25a.75.75 0 0 1-1.06 0L4.22 7.28a.75.75 0 0 1 0-1.06Z" clip-rule="evenodd" />
                </svg>
              </div>
            </div>
            <div>
              <label class="block text-sm/6 font-medium text-gray-900 dark:text-white">Direction</label>
              <div class="mt-1 grid grid-cols-1">
                <select
                  name="kind"
                  class="col-start-1 row-start-1 w-full appearance-none rounded-md bg-white py-1.5 pr-8 pl-3 text-base text-gray-900 outline-1 -outline-offset-1 outline-gray-300 focus:outline-2 focus:-outline-offset-2 focus:outline-emerald-600 sm:text-sm/6 dark:bg-white/5 dark:text-white dark:outline-white/10"
                >
                  <option value="all">All</option>
                  <option value="inbound">Inbound</option>
                  <option value="outbound">Outbound</option>
                </select>
                <svg class="pointer-events-none col-start-1 row-start-1 mr-2 size-5 self-center justify-self-end text-gray-500 sm:size-4" viewBox="0 0 16 16" fill="currentColor">
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
              <button type="submit" class="ml-2 rounded-md bg-emerald-600 px-3 py-2 text-sm font-semibold text-white shadow-xs hover:bg-emerald-500">
                Download
              </button>
            </div>
          </form>
        </div>
      <% end %>

      <%!-- Balance section --%>
      <div class="mb-8">
        <div
          :if={@accounts == []}
          class="rounded-lg border border-gray-200 bg-white p-6 text-sm text-gray-500 dark:border-white/10 dark:bg-white/5 dark:text-gray-400"
        >
          No account data — click Sync to pull from Mercury, or wait for a webhook.
        </div>

        <div :if={@accounts != []} class="grid gap-6 md:grid-cols-2 lg:grid-cols-3">
          <div :for={account <- @accounts} class="space-y-2">
            <div class="flex items-center justify-between px-1">
              <p class="text-sm font-medium text-gray-900 dark:text-white">{account.name}</p>
              <.status_badge status={account_status_variant(account.status)}>
                {format_atom(account.status)}
              </.status_badge>
            </div>
            <.stat_card
              title={format_atom(account.kind)}
              value={format_amount(account.current_balance)}
              description={"Available: #{format_amount(account.available_balance)}"}
              icon="hero-building-library"
            />
          </div>
        </div>
      </div>

      <%!-- Filters --%>
      <form phx-change="filter_changed" class="mb-4 flex flex-wrap items-end gap-4">

        <div>
          <label for="filter_from" class="block text-sm/6 font-medium text-base-content">
            From
          </label>
          <input
            id="filter_from"
            type="date"
            name="from_date"
            value={Date.to_iso8601(@filters.from_date)}
            class="mt-1 block rounded-md bg-base-100 px-3 py-1.5 text-sm text-base-content outline-1 -outline-offset-1 outline-base-content/20 hover:bg-base-200 focus:outline-2 focus:-outline-offset-2 focus:outline-primary transition-colors cursor-pointer"
          />
        </div>
        <div>
          <label for="filter_to" class="block text-sm/6 font-medium text-base-content">
            To
          </label>
          <input
            id="filter_to"
            type="date"
            name="to_date"
            value={Date.to_iso8601(Date.add(@filters.to_date, -1))}
            class="mt-1 block rounded-md bg-base-100 px-3 py-1.5 text-sm text-base-content outline-1 -outline-offset-1 outline-base-content/20 hover:bg-base-200 focus:outline-2 focus:-outline-offset-2 focus:outline-primary transition-colors cursor-pointer"
          />
        </div>
        <div>
          <label for="filter_status" class="block text-sm/6 font-medium text-base-content">
            Status
          </label>
          <div class="mt-1 grid grid-cols-1">
            <select
              id="filter_status"
              name="status_filter"
              class="col-start-1 row-start-1 appearance-none rounded-md bg-base-100 py-1.5 pr-8 pl-3 text-sm text-base-content outline-1 -outline-offset-1 outline-base-content/20 hover:bg-base-200 focus:outline-2 focus:-outline-offset-2 focus:outline-primary transition-colors cursor-pointer"
            >
              <option value="all" selected={@filters.status_filter == "all"}>All</option>
              <option value="matched" selected={@filters.status_filter == "matched"}>Matched</option>
              <option value="unmatched" selected={@filters.status_filter == "unmatched"}>Unmatched</option>
              <option value="pending" selected={@filters.status_filter == "pending"}>Pending</option>
            </select>
            <svg class="pointer-events-none col-start-1 row-start-1 mr-2 size-4 self-center justify-self-end text-base-content/40" viewBox="0 0 16 16" fill="currentColor">
              <path fill-rule="evenodd" d="M4.22 6.22a.75.75 0 0 1 1.06 0L8 8.94l2.72-2.72a.75.75 0 1 1 1.06 1.06l-3.25 3.25a.75.75 0 0 1-1.06 0L4.22 7.28a.75.75 0 0 1 0-1.06Z" clip-rule="evenodd" />
            </svg>
          </div>
        </div>
        <div>
          <label for="filter_kind" class="block text-sm/6 font-medium text-base-content">
            Direction
          </label>
          <div class="mt-1 grid grid-cols-1">
            <select
              id="filter_kind"
              name="kind"
              class="col-start-1 row-start-1 appearance-none rounded-md bg-base-100 py-1.5 pr-8 pl-3 text-sm text-base-content outline-1 -outline-offset-1 outline-base-content/20 hover:bg-base-200 focus:outline-2 focus:-outline-offset-2 focus:outline-primary transition-colors cursor-pointer"
            >
              <option value="all" selected={@filters.kind == "all"}>All</option>
              <option value="inbound" selected={@filters.kind == "inbound"}>Inbound</option>
              <option value="outbound" selected={@filters.kind == "outbound"}>Outbound</option>
            </select>
            <svg class="pointer-events-none col-start-1 row-start-1 mr-2 size-4 self-center justify-self-end text-base-content/40" viewBox="0 0 16 16" fill="currentColor">
              <path fill-rule="evenodd" d="M4.22 6.22a.75.75 0 0 1 1.06 0L8 8.94l2.72-2.72a.75.75 0 1 1 1.06 1.06l-3.25 3.25a.75.75 0 0 1-1.06 0L4.22 7.28a.75.75 0 0 1 0-1.06Z" clip-rule="evenodd" />
            </svg>
          </div>
        </div>
        <div>
          <label class="block text-sm/6 font-medium" style="visibility:hidden">x</label>
          <button type="button" phx-click="reset_filters" title="Clear all filters and return to the default 30-day view" class="mt-1 cursor-pointer rounded-md bg-base-100 py-1.5 px-3 text-sm text-base-content outline-1 -outline-offset-1 outline-base-content/20 hover:bg-base-200 active:bg-base-300 transition-colors">
            Reset filters
          </button>
        </div>
      </form>

      <%!-- Transaction table --%>
      <.section title="Transactions" body_class="p-0">
        <div :if={@transactions == []} class="p-6 sm:p-7">
          <.empty_state
            icon="hero-banknotes"
            title="No transactions found"
            description="No transactions found for the selected filters."
          />
        </div>

        <div :if={@transactions != []} class="overflow-x-auto">
          <table class="min-w-full divide-y divide-zinc-200 text-sm dark:divide-white/10">
            <thead class="bg-zinc-50 dark:bg-white/[0.03]">
              <tr>
                <th class="px-5 py-3 text-left font-medium text-zinc-500 dark:text-zinc-400">Date</th>
                <th class="px-5 py-3 text-left font-medium text-zinc-500 dark:text-zinc-400">Counterparty</th>
                <th class="px-5 py-3 text-left font-medium text-zinc-500 dark:text-zinc-400">Kind</th>
                <th class="px-5 py-3 text-left font-medium text-zinc-500 dark:text-zinc-400">Direction</th>
                <th class="px-5 py-3 text-right font-medium text-zinc-500 dark:text-zinc-400">Amount</th>
                <th class="px-5 py-3 text-left font-medium text-zinc-500 dark:text-zinc-400">Status</th>
                <th class="px-5 py-3 text-left font-medium text-zinc-500 dark:text-zinc-400"></th>
              </tr>
            </thead>
            <tbody class="divide-y divide-zinc-200 dark:divide-white/10">
              <tr :for={txn <- @transactions}>
                <td class="px-5 py-4 whitespace-nowrap text-zinc-600 dark:text-zinc-300">
                  {format_occurred_at(txn.occurred_at)}
                </td>
                <td class="px-5 py-4 text-zinc-900 dark:text-white">
                  {counterparty(txn)}
                </td>
                <td class="px-5 py-4">
                  <.status_badge status={:info}>{format_atom(txn.kind)}</.status_badge>
                </td>
                <td class="px-5 py-4">
                  <.status_badge status={if Decimal.compare(txn.amount, Decimal.new("0")) == :gt, do: :success, else: :default}>
                    {if Decimal.compare(txn.amount, Decimal.new("0")) == :gt, do: "Inbound", else: "Outbound"}
                  </.status_badge>
                </td>
                <td class={["px-5 py-4 text-right tabular-nums", amount_classes(txn.amount)]}>
                  {format_amount(txn.amount)}
                </td>
                <td class="px-5 py-4">
                  <.status_badge :if={txn.status == :pending} status={:warning}>Pending</.status_badge>
                  <.status_badge :if={txn.status != :pending} status={match_status_variant(txn.match_confidence)}>
                    {match_status_label(txn.match_confidence)}
                  </.status_badge>
                  <%!-- Partial application indicator --%>
                  <% applied = txn.payment_matches |> Enum.map(& &1.finance_payment) |> Enum.reject(&is_nil/1) |> Enum.reduce(Decimal.new("0"), &Decimal.add(&1.amount, &2)) %>
                  <p :if={txn.match_confidence in [:unmatched, nil] and Decimal.compare(applied, Decimal.new("0")) == :gt} class="mt-1 text-xs text-amber-600 dark:text-amber-400">
                    {format_amount(applied)} applied
                  </p>
                  <div :if={txn.reconciliation_category || txn.reconciliation_note} class="mt-1 flex flex-wrap items-center gap-1">
                    <span :if={txn.reconciliation_category} class="inline-flex items-center rounded px-1.5 py-0.5 text-xs font-medium bg-base-300 text-base-content/70">
                      {format_reconciliation_category(txn.reconciliation_category)}
                    </span>
                    <span :if={txn.reconciliation_note} class="text-xs text-base-content/40 italic">
                      {txn.reconciliation_note}
                    </span>
                  </div>
                </td>
                <td class="px-5 py-4 text-right">
                  <div class="flex items-center justify-end gap-2">
                    <%!-- Match button — only for unmatched inbound sent transactions --%>
                    <% applied = txn.payment_matches |> Enum.map(& &1.finance_payment) |> Enum.reject(&is_nil/1) |> Enum.reduce(Decimal.new("0"), &Decimal.add(&1.amount, &2)) %>
                    <button
                      :if={txn.match_confidence in [:unmatched, nil] and txn.status in [:sent, :pending] and Decimal.compare(txn.amount, Decimal.new("0")) == :gt}
                      phx-click="open_match_modal"
                      phx-value-txn_id={txn.id}
                      title="Link this transaction to one or more open invoices"
                      class="rounded-md border border-emerald-600 px-2.5 py-1 text-xs font-semibold text-emerald-700 hover:bg-emerald-50 dark:border-emerald-500 dark:text-emerald-400 dark:hover:bg-emerald-900/30 cursor-pointer transition-colors"
                    >
                      Match
                    </button>
                    <button
                      :if={txn.match_confidence in [:unmatched, nil] and txn.status in [:sent, :pending] and Decimal.compare(txn.amount, Decimal.new("0")) == :gt}
                      phx-click="open_reconcile_modal"
                      phx-value-txn_id={txn.id}
                      title="Mark this transaction as reconciled with a required explanation"
                      class="rounded-md border border-amber-400 px-2.5 py-1 text-xs font-semibold text-amber-700 hover:bg-amber-50 dark:border-amber-500/50 dark:text-amber-400 dark:hover:bg-amber-900/20 cursor-pointer transition-colors"
                    >
                      Reconcile
                    </button>
                    <%!-- Unmatch button — for matched transactions --%>
                    <button
                      :if={txn.match_confidence in [:exact, :probable, :possible]}
                      phx-click="unmatch_transaction"
                      phx-value-txn_id={txn.id}
                      title="Remove the match — deletes the payment record and reopens the invoice"
                      data-confirm="Remove this match? The payment record will be deleted and the invoice will be reopened."
                      class="rounded-md border border-red-300 px-2.5 py-1 text-xs font-semibold text-red-600 hover:bg-red-50 dark:border-red-500/50 dark:text-red-400 dark:hover:bg-red-900/20 cursor-pointer transition-colors"
                    >
                      Unmatch
                    </button>
                    <%!-- Dashboard link — if Mercury provided one --%>
                    <a
                      :if={txn.dashboard_link}
                      href={txn.dashboard_link}
                      target="_blank"
                      rel="noopener noreferrer"
                      class="rounded px-2 py-1 text-xs font-medium text-zinc-500 hover:bg-zinc-100 dark:text-zinc-400 dark:hover:bg-white/10"
                      title="View in Mercury"
                    >
                      <.icon name="hero-arrow-top-right-on-square" class="size-3.5" />
                    </a>
                    <%!-- Per-row export links --%>
                    <a
                      href={~p"/finance/mercury/transactions/#{txn.id}/export?format=csv"}
                      target="_blank"
                      class="rounded px-2 py-1 text-xs font-medium text-zinc-500 hover:bg-zinc-100 dark:text-zinc-400 dark:hover:bg-white/10"
                      title="Download this transaction as CSV"
                    >
                      CSV
                    </a>
                    <a
                      href={~p"/finance/mercury/transactions/#{txn.id}/export?format=pdf"}
                      target="_blank"
                      class="rounded px-2 py-1 text-xs font-medium text-zinc-500 hover:bg-zinc-100 dark:text-zinc-400 dark:hover:bg-white/10"
                      title="Download this transaction as PDF"
                    >
                      PDF
                    </a>
                  </div>
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </.section>

      <%!-- Manual match modal --%>
      <div
        :if={@matching_txn}
        class="fixed inset-0 z-50 flex items-center justify-center bg-black/50 px-4"
      >
        <div class="w-full max-w-2xl rounded-2xl bg-white p-6 shadow-xl dark:bg-zinc-900">
          <h2 class="text-base font-semibold text-zinc-900 dark:text-white mb-1">
            Match Transaction to Invoice(s)
          </h2>
          <p class="text-sm text-zinc-500 dark:text-zinc-400 mb-5">
            {counterparty(@matching_txn)} · {format_amount(@matching_txn.amount)} · {format_occurred_at(@matching_txn.occurred_at)}
          </p>

          <form phx-submit="apply_manual_match">
            <div :if={@open_invoices == []} class="mb-4 text-sm text-zinc-500 dark:text-zinc-400">
              No open invoices available.
            </div>
            <div :if={@open_invoices != []} class="mb-4">
              <table class="w-full text-sm">
                <thead>
                  <tr class="border-b border-gray-200 dark:border-white/10 text-left text-xs font-medium text-zinc-500 dark:text-zinc-400">
                    <th class="pb-2 pr-3 w-6"></th>
                    <th class="pb-2 pr-3">Invoice</th>
                    <th class="pb-2 pr-3">Client</th>
                    <th class="pb-2 pr-3 text-right">Balance due</th>
                    <th class="pb-2 text-right">Amount to apply</th>
                  </tr>
                </thead>
                <tbody>
                  <tr :for={inv <- @open_invoices} class="border-b border-gray-100 dark:border-white/5 last:border-0">
                    <td class="py-2 pr-3">
                      <input
                        type="checkbox"
                        name={"invoices[#{inv.id}][selected]"}
                        value="true"
                        class="rounded accent-emerald-600 cursor-pointer"
                      />
                    </td>
                    <td class="py-2 pr-3 font-medium text-zinc-900 dark:text-white">
                      {inv.invoice_number || inv.id}
                    </td>
                    <td class="py-2 pr-3 text-zinc-500 dark:text-zinc-400">
                      {if inv.organization, do: inv.organization.name, else: "—"}
                    </td>
                    <td class="py-2 pr-3 text-right text-zinc-700 dark:text-zinc-300">
                      {format_amount(inv.balance_amount || inv.total_amount)}
                    </td>
                    <td class="py-2 text-right">
                      <input
                        type="number"
                        step="0.01"
                        min="0"
                        max={Decimal.to_string(Decimal.round(inv.balance_amount || inv.total_amount || Decimal.new("0"), 2), :normal)}
                        name={"invoices[#{inv.id}][amount]"}
                        value={Decimal.to_string(Decimal.round(inv.balance_amount || inv.total_amount || Decimal.new("0"), 2), :normal)}
                        class="w-28 rounded-md bg-white px-2 py-1 text-sm text-right text-gray-900 outline-1 -outline-offset-1 outline-gray-300 focus:outline-2 focus:-outline-offset-2 focus:outline-emerald-600 dark:bg-white/5 dark:text-white dark:outline-white/10 dark:focus:outline-emerald-500"
                      />
                    </td>
                  </tr>
                </tbody>
              </table>
              <p class="mt-2 text-xs text-zinc-500 dark:text-zinc-400">
                Check one or more invoices. Adjust amounts if needed. Transaction total: {format_amount(@matching_txn.amount)}.
              </p>
            </div>

            <div class="flex justify-end gap-3">
              <button
                type="button"
                phx-click="close_match_modal"
                title="Close without saving"
                class="rounded-md px-3 py-2 text-sm font-semibold text-zinc-700 hover:bg-zinc-100 dark:text-zinc-300 dark:hover:bg-white/10"
              >
                Cancel
              </button>
              <button
                type="submit"
                title="Create a payment record and link it to the selected invoice(s)"
                class="rounded-md bg-emerald-600 px-3 py-2 text-sm font-semibold text-white shadow-xs hover:bg-emerald-500"
              >
                Apply Match
              </button>
            </div>
          </form>
        </div>
      </div>
      <%!-- Reconcile modal --%>
      <div
        :if={@reconciling_txn}
        class="fixed inset-0 z-50 flex items-center justify-center bg-black/50 px-4"
      >
        <div
          class="w-full max-w-md rounded-2xl bg-white p-6 shadow-xl dark:bg-zinc-900"
          phx-click-away="close_reconcile_modal"
        >
          <h2 class="text-base font-semibold text-base-content">Reconcile Transaction</h2>
          <% applied = @reconciling_txn.payment_matches |> Enum.map(& &1.finance_payment) |> Enum.reject(&is_nil/1) |> Enum.reduce(Decimal.new("0"), &Decimal.add(&1.amount, &2)) %>
          <% remaining = Decimal.sub(Decimal.abs(@reconciling_txn.amount), applied) %>
          <p class="mt-1 text-sm text-base-content/60">
            <%= if Decimal.compare(applied, Decimal.new("0")) == :gt do %>
              {format_amount(applied)} of {format_amount(@reconciling_txn.amount)} has been applied.
              The remaining <strong class="text-amber-600">{format_amount(remaining)}</strong> will be marked as reconciled.
            <% else %>
              The full amount of <strong class="text-amber-600">{format_amount(@reconciling_txn.amount)}</strong> will be marked as reconciled.
            <% end %>
          </p>

          <div :if={@reconciliation_error} class="mt-3 rounded-md bg-red-50 px-3 py-2 text-sm text-red-600 dark:bg-red-900/30 dark:text-red-400">
            {@reconciliation_error}
          </div>

          <form phx-change="reconcile_form_changed" phx-submit="confirm_reconcile">
            <div class="mt-4">
              <label class="block text-sm font-medium text-base-content">
                Category <span class="text-red-500">*</span>
              </label>
              <div class="mt-1.5 grid grid-cols-1">
                <select
                  name="category"
                  class="col-start-1 row-start-1 appearance-none rounded-md bg-white py-1.5 pr-8 pl-3 text-sm text-gray-900 outline-1 -outline-offset-1 outline-gray-300 focus:outline-2 focus:-outline-offset-2 focus:outline-emerald-600 dark:bg-white/5 dark:text-white dark:outline-white/10 dark:focus:outline-emerald-500"
                >
                  <option value="">Select a category…</option>
                  <option value="bank_fee" selected={@reconciliation_category == :bank_fee}>Bank Fee / Charge</option>
                  <option value="internal_transfer" selected={@reconciliation_category == :internal_transfer}>Internal Transfer</option>
                  <option value="misc_income" selected={@reconciliation_category == :misc_income}>Misc Income</option>
                  <option value="refund" selected={@reconciliation_category == :refund}>Refund / Reversal</option>
                  <option value="interest_income" selected={@reconciliation_category == :interest_income}>Interest Income</option>
                  <option value="owner_draw" selected={@reconciliation_category == :owner_draw}>Owner's Draw</option>
                  <option value="other" selected={@reconciliation_category == :other}>Other</option>
                </select>
                <svg class="pointer-events-none col-start-1 row-start-1 mr-2 size-4 self-center justify-self-end text-gray-500 dark:text-gray-400" viewBox="0 0 16 16" fill="currentColor">
                  <path fill-rule="evenodd" d="M4.22 6.22a.75.75 0 0 1 1.06 0L8 8.94l2.72-2.72a.75.75 0 1 1 1.06 1.06l-3.25 3.25a.75.75 0 0 1-1.06 0L4.22 7.28a.75.75 0 0 1 0-1.06Z" clip-rule="evenodd" />
                </svg>
              </div>
            </div>

            <div class="mt-4">
              <label class="block text-sm font-medium text-base-content">
                Notes <span class="text-red-500">*</span>
              </label>
              <textarea
                name="note"
                placeholder="e.g. Monthly Mercury account fee, Transfer to payroll account, Rounding difference on wire..."
                rows="3"
                class="mt-1.5 w-full rounded-md bg-white px-3 py-1.5 text-sm text-gray-900 outline-1 -outline-offset-1 outline-gray-300 placeholder:text-gray-400 focus:outline-2 focus:-outline-offset-2 focus:outline-emerald-600 dark:bg-white/5 dark:text-white dark:outline-white/10 dark:placeholder:text-gray-500 dark:focus:outline-emerald-500"
              >{@reconciliation_note}</textarea>
            </div>

            <div class="mt-5 flex justify-end gap-3">
              <button
                type="button"
                phx-click="close_reconcile_modal"
                class="rounded-md px-3 py-2 text-sm font-semibold text-base-content hover:bg-zinc-100 dark:hover:bg-white/10"
              >
                Cancel
              </button>
              <button
                type="submit"
                class="rounded-md bg-amber-500 px-3 py-2 text-sm font-semibold text-white hover:bg-amber-400"
              >
                Mark as Reconciled
              </button>
            </div>
          </form>
        </div>
      </div>
    </.page>
    """
  end
end
