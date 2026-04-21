defmodule GnomeGardenWeb.PageController do
  use GnomeGardenWeb, :controller

  alias GnomeGarden.Acquisition
  alias GnomeGarden.Commercial
  alias GnomeGarden.Execution
  alias GnomeGarden.Finance

  def home(conn, _params) do
    actor = conn.assigns[:current_user]

    review_findings = list_review_findings(actor)
    acquisition_sources = list_console_sources(actor)
    acquisition_programs = list_console_programs(actor)
    queued_signals = list_signal_queue(actor)
    active_pursuits = list_active_pursuits(actor)

    due_soon_maintenance_plans =
      list_due_soon_maintenance_plans(actor)

    open_service_tickets = list_open_service_tickets(actor)
    open_work_orders = list_open_work_orders(actor)
    unbilled_time_entries = list_unbilled_time_entries(actor)
    unbilled_expenses = list_unbilled_expenses(actor)
    overdue_invoices = list_overdue_invoices(actor)
    unapplied_payments = list_unapplied_payments(actor)

    render(conn, :home,
      layout: {GnomeGardenWeb.Layouts, :app},
      page_title: "Operations Cockpit",
      current_user: actor,
      current_path: conn.request_path,
      runnable_source_count: runnable_source_count(acquisition_sources),
      runnable_sources: acquisition_sources |> runnable_sources() |> Enum.take(5),
      runnable_program_count: runnable_program_count(acquisition_programs),
      runnable_programs: acquisition_programs |> runnable_programs() |> Enum.take(5),
      review_finding_count: length(review_findings),
      review_findings: Enum.take(review_findings, 5),
      open_signal_count: length(queued_signals),
      open_signals: Enum.take(queued_signals, 5),
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
      unapplied_payments: Enum.take(unapplied_payments, 5)
    )
  end

  defp list_console_sources(actor) do
    safe_list(fn ->
      Acquisition.list_console_sources(
        actor: actor,
        load: [
          :organization,
          :runnable,
          :health_status,
          :health_variant,
          :health_note,
          :status_variant,
          :review_finding_count,
          :promoted_finding_count,
          :noise_finding_count,
          :latest_run_id
        ]
      )
    end)
  end

  defp list_console_programs(actor) do
    safe_list(fn ->
      Acquisition.list_console_programs(
        actor: actor,
        load: [
          :runnable,
          :health_status,
          :health_variant,
          :health_note,
          :status_variant,
          :review_finding_count,
          :promoted_finding_count,
          :noise_finding_count,
          :latest_run_id
        ]
      )
    end)
  end

  defp list_signal_queue(actor) do
    safe_list(fn ->
      Commercial.list_signal_queue(
        actor: actor,
        load: [:status_variant, :procurement_bid, organization: [], site: []]
      )
    end)
  end

  defp list_review_findings(actor) do
    safe_list(fn ->
      Acquisition.list_review_findings(
        actor: actor,
        load: [:status_variant, :organization, :source, :program]
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

  defp unapplied_payment?(payment) do
    applied_amount = payment.applied_amount || Decimal.new("0")

    payment.amount
    |> Decimal.sub(applied_amount)
    |> Decimal.compare(0)
    |> Kernel.==(:gt)
  end

  defp runnable_source_count(sources), do: sources |> runnable_sources() |> length()

  defp runnable_sources(sources), do: Enum.filter(sources, & &1.runnable)

  defp runnable_program_count(programs), do: programs |> runnable_programs() |> length()

  defp runnable_programs(programs), do: Enum.filter(programs, & &1.runnable)

  defp safe_list(fun) do
    case fun.() do
      {:ok, records} -> records
      {:error, _error} -> []
    end
  end
end
