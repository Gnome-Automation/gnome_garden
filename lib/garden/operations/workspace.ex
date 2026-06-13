defmodule GnomeGarden.Operations.Workspace do
  @moduledoc """
  Builds the company operations workspace shown at `/`.

  This is intentionally a cross-domain read model. Individual resources still
  own their persisted behavior; this module owns the grouped operator shape for
  deciding what needs attention now.
  """

  alias GnomeGarden.Acquisition
  alias GnomeGarden.Commercial
  alias GnomeGarden.Execution
  alias GnomeGarden.Finance

  @item_limit 5
  @maintenance_window_days 30

  def build(opts \\ []) do
    actor = Keyword.get(opts, :actor)

    review_findings = list_review_findings(actor)
    acquisition_sources = list_console_sources(actor)
    acquisition_programs = list_console_programs(actor)
    queued_signals = list_signal_queue(actor)
    active_pursuits = list_active_pursuits(actor)
    due_soon_maintenance_plans = list_due_soon_maintenance_plans(actor)
    open_service_tickets = list_open_service_tickets(actor)
    open_work_orders = list_open_work_orders(actor)
    unbilled_time_entries = list_unbilled_time_entries(actor)
    unbilled_expenses = list_unbilled_expenses(actor)
    overdue_invoices = list_overdue_invoices(actor)
    unapplied_payments = list_unapplied_payments(actor)

    runnable_sources = runnable_sources(acquisition_sources)
    runnable_programs = runnable_programs(acquisition_programs)

    workspace = %{
      runnable_source_count: length(runnable_sources),
      runnable_sources: Enum.take(runnable_sources, @item_limit),
      runnable_program_count: length(runnable_programs),
      runnable_programs: Enum.take(runnable_programs, @item_limit),
      review_finding_count: length(review_findings),
      review_findings: Enum.take(review_findings, @item_limit),
      open_signal_count: length(queued_signals),
      open_signals: Enum.take(queued_signals, @item_limit),
      active_pursuit_count: length(active_pursuits),
      active_pursuits: Enum.take(active_pursuits, @item_limit),
      due_soon_maintenance_count: length(due_soon_maintenance_plans),
      due_soon_maintenance_plans: Enum.take(due_soon_maintenance_plans, @item_limit),
      open_service_ticket_count: length(open_service_tickets),
      open_service_tickets: Enum.take(open_service_tickets, @item_limit),
      open_work_order_count: length(open_work_orders),
      open_work_orders: Enum.take(open_work_orders, @item_limit),
      unbilled_time_entry_count: length(unbilled_time_entries),
      unbilled_time_entries: Enum.take(unbilled_time_entries, @item_limit),
      unbilled_expense_count: length(unbilled_expenses),
      unbilled_expenses: Enum.take(unbilled_expenses, @item_limit),
      overdue_invoice_count: length(overdue_invoices),
      overdue_invoices: Enum.take(overdue_invoices, @item_limit),
      unapplied_payment_count: length(unapplied_payments),
      unapplied_payments: Enum.take(unapplied_payments, @item_limit)
    }

    Map.put(workspace, :priority_items, priority_items(workspace))
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
    safe_list(fn ->
      Execution.list_due_soon_maintenance_plans(@maintenance_window_days,
        actor: actor,
        load: [:due_status_variant, :due_status_label, asset: [], organization: []]
      )
    end)
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

  defp runnable_sources(sources), do: Enum.filter(sources, & &1.runnable)

  defp runnable_programs(programs), do: Enum.filter(programs, & &1.runnable)

  defp priority_items(workspace) do
    [
      priority_item(
        workspace.overdue_invoice_count,
        "Collect overdue receivables",
        "Follow up on overdue invoices before adding more delivery load.",
        "/finance/invoices",
        "hero-exclamation-triangle",
        "rose"
      ),
      priority_item(
        workspace.unapplied_payment_count,
        "Allocate received cash",
        "Apply received payments so the finance queue reflects real balances.",
        "/finance/payments",
        "hero-banknotes",
        "sky"
      ),
      priority_item(
        workspace.review_finding_count,
        "Clear acquisition intake",
        "Review procurement and discovery findings waiting on a pursue-or-pass decision.",
        "/acquisition/findings",
        "hero-inbox-stack",
        "emerald"
      ),
      priority_item(
        workspace.active_pursuit_count,
        "Advance active pursuits",
        "Move open commercial pursuits through research, estimating, proposal, or negotiation.",
        "/commercial/pursuits",
        "hero-arrow-trending-up",
        "sky"
      ),
      priority_item(
        workspace.open_service_ticket_count,
        "Triage service tickets",
        "Handle customer-facing service work still moving through triage or resolution.",
        "/execution/service-tickets",
        "hero-lifebuoy",
        "rose"
      ),
      priority_item(
        workspace.open_work_order_count,
        "Dispatch open work orders",
        "Keep field execution moving through scheduling, dispatch, and completion.",
        "/execution/work-orders",
        "hero-wrench-screwdriver",
        "amber"
      ),
      priority_item(
        workspace.due_soon_maintenance_count,
        "Plan due maintenance",
        "Schedule preventive work before it becomes reactive service pressure.",
        "/execution/maintenance-plans",
        "hero-clock",
        "amber"
      ),
      priority_item(
        workspace.unbilled_time_entry_count + workspace.unbilled_expense_count,
        "Prepare approved billing",
        "Turn approved labor and costs into invoice-ready work.",
        "/finance/invoices",
        "hero-banknotes",
        "emerald"
      ),
      priority_item(
        workspace.runnable_source_count + workspace.runnable_program_count,
        "Launch runnable scans",
        "Run ready acquisition sources and programs to keep future intake flowing.",
        "/acquisition/dashboard",
        "hero-bolt",
        "amber"
      )
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.take(@item_limit)
  end

  defp priority_item(0, _title, _description, _path, _icon, _accent), do: nil

  defp priority_item(count, title, description, path, icon, accent) do
    %{
      count: count,
      title: title,
      description: description,
      path: path,
      icon: icon,
      accent: accent
    }
  end

  defp safe_list(fun) do
    case fun.() do
      {:ok, records} -> records
      {:error, _error} -> []
    end
  end
end
