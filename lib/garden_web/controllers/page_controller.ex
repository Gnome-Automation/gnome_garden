defmodule GnomeGardenWeb.PageController do
  use GnomeGardenWeb, :controller

  alias GnomeGarden.Commercial
  alias GnomeGarden.Execution
  alias GnomeGarden.Finance
  alias GnomeGarden.Procurement

  def home(conn, _params) do
    actor = conn.assigns[:current_user]

    review_targets = list_review_targets(actor)
    active_discovery_programs = list_active_discovery_programs(actor)
    open_signals = list_open_signals(actor)
    active_pursuits = list_active_pursuits(actor)

    due_soon_maintenance_plans =
      list_due_soon_maintenance_plans(actor)

    open_service_tickets = list_open_service_tickets(actor)
    open_work_orders = list_open_work_orders(actor)
    unbilled_time_entries = list_unbilled_time_entries(actor)
    unbilled_expenses = list_unbilled_expenses(actor)
    overdue_invoices = list_overdue_invoices(actor)
    unapplied_payments = list_unapplied_payments(actor)
    review_bids = list_review_bids()

    render(conn, :home,
      layout: {GnomeGardenWeb.Layouts, :app},
      page_title: "Operations Cockpit",
      current_user: actor,
      current_path: conn.request_path,
      active_discovery_program_count: length(active_discovery_programs),
      review_target_count: length(review_targets),
      review_targets: Enum.take(review_targets, 5),
      open_signal_count: length(open_signals),
      open_signals: Enum.take(open_signals, 5),
      active_pursuit_count: length(active_pursuits),
      active_pursuits: Enum.take(active_pursuits, 5),
      due_soon_maintenance_count: length(due_soon_maintenance_plans),
      due_soon_maintenance_plans: Enum.take(due_soon_maintenance_plans, 5),
      open_service_ticket_count: length(open_service_tickets),
      open_service_tickets: Enum.take(open_service_tickets, 5),
      open_work_order_count: length(open_work_orders),
      open_work_orders: Enum.take(open_work_orders, 5),
      unbilled_time_entry_count: length(unbilled_time_entries),
      unbilled_time_entries: Enum.take(unbilled_time_entries, 5),
      unbilled_expense_count: length(unbilled_expenses),
      unbilled_expenses: Enum.take(unbilled_expenses, 5),
      overdue_invoice_count: length(overdue_invoices),
      overdue_invoices: Enum.take(overdue_invoices, 5),
      unapplied_payment_count: length(unapplied_payments),
      unapplied_payments: Enum.take(unapplied_payments, 5),
      review_bid_count: length(review_bids)
    )
  end

  defp list_open_signals(actor) do
    safe_list(fn ->
      Commercial.list_open_signals(
        actor: actor,
        load: [:status_variant, organization: [], site: []]
      )
    end)
  end

  defp list_review_targets(actor) do
    safe_list(fn ->
      Commercial.list_review_target_accounts(
        actor: actor,
        load: [:status_variant, :organization, :observation_count, :latest_observed_at]
      )
    end)
  end

  defp list_active_discovery_programs(actor) do
    safe_list(fn ->
      Commercial.list_active_discovery_programs(
        actor: actor,
        load: [:status_variant, :priority_variant, :review_target_count]
      )
    end)
  end

  defp list_active_pursuits(actor) do
    safe_list(fn ->
      Commercial.list_active_pursuits(
        actor: actor,
        load: [:stage_variant, :priority_variant, organization: []]
      )
    end)
  end

  defp list_due_soon_maintenance_plans(actor) do
    case Execution.list_due_soon_maintenance_plans(30,
           actor: actor,
           load: [:due_status_variant, :due_status_label, asset: [], organization: []]
         ) do
      {:ok, maintenance_plans} -> maintenance_plans
      {:error, _error} -> []
    end
  end

  defp list_open_service_tickets(actor) do
    safe_list(fn ->
      Execution.list_open_service_tickets(
        actor: actor,
        load: [:status_variant, :severity_variant, organization: [], asset: []]
      )
    end)
  end

  defp list_open_work_orders(actor) do
    safe_list(fn ->
      Execution.list_open_work_orders(
        actor: actor,
        load: [
          :status_variant,
          :priority_variant,
          organization: [],
          asset: [],
          maintenance_plan: []
        ]
      )
    end)
  end

  defp list_unbilled_time_entries(actor) do
    safe_list(fn ->
      Finance.list_unbilled_approved_time_entries(
        actor: actor,
        load: [:status_variant, organization: [], project: [], work_order: []]
      )
    end)
  end

  defp list_unbilled_expenses(actor) do
    safe_list(fn ->
      Finance.list_unbilled_approved_expenses(
        actor: actor,
        load: [:status_variant, organization: [], project: [], work_order: []]
      )
    end)
  end

  defp list_overdue_invoices(actor) do
    safe_list(fn ->
      Finance.list_overdue_invoices(
        actor: actor,
        load: [:status_variant, organization: [], agreement: []]
      )
    end)
  end

  defp list_unapplied_payments(actor) do
    actor
    |> list_open_payments()
    |> Enum.filter(&unapplied_payment?/1)
  end

  defp list_open_payments(actor) do
    safe_list(fn ->
      Finance.list_open_payments(
        actor: actor,
        load: [:status_variant, :applied_amount, organization: []]
      )
    end)
  end

  defp list_review_bids do
    safe_list(fn -> Procurement.list_bids(query: [filter: [status: :new]]) end)
  end

  defp unapplied_payment?(payment) do
    applied_amount = payment.applied_amount || Decimal.new("0")

    payment.amount
    |> Decimal.sub(applied_amount)
    |> Decimal.compare(0)
    |> Kernel.==(:gt)
  end

  defp safe_list(fun) do
    case fun.() do
      {:ok, records} -> records
      {:error, _error} -> []
    end
  end
end
