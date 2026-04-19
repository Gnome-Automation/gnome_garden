defmodule GnomeGardenWeb.Finance.ExpenseLive.Index do
  use GnomeGardenWeb, :live_view

  import GnomeGardenWeb.Finance.Helpers

  alias GnomeGarden.Finance

  @impl true
  def mount(_params, _session, socket) do
    expenses = load_expenses(socket.assigns.current_user)

    {:ok,
     socket
     |> assign(:page_title, "Expenses")
     |> assign(:expense_count, length(expenses))
     |> assign(:submitted_count, Enum.count(expenses, &(&1.status == :submitted)))
     |> assign(:approved_count, Enum.count(expenses, &(&1.status == :approved)))
     |> assign(:expense_total, sum_amounts(expenses, :amount))
     |> stream(:expenses, expenses)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.page class="pb-8">
      <.page_header eyebrow="Finance">
        Expenses
        <:subtitle>
          Non-labor operational cost records that feed approvals, agreement consumption, and invoice drafting.
        </:subtitle>
        <:actions>
          <.button navigate={~p"/execution/work-orders"}>
            <.icon name="hero-wrench-screwdriver" class="size-4" /> Work Orders
          </.button>
          <.button navigate={~p"/finance/expenses/new"} variant="primary">
            <.icon name="hero-plus" class="size-4" /> New Expense
          </.button>
        </:actions>
      </.page_header>

      <div class="grid gap-4 md:grid-cols-4">
        <.stat_card
          title="Expenses"
          value={Integer.to_string(@expense_count)}
          description="Operational non-labor costs attached to customer work and service execution."
          icon="hero-credit-card"
        />
        <.stat_card
          title="Submitted"
          value={Integer.to_string(@submitted_count)}
          description="Expenses waiting on explicit approval before billing or contract consumption."
          icon="hero-paper-airplane"
          accent="amber"
        />
        <.stat_card
          title="Approved"
          value={Integer.to_string(@approved_count)}
          description="Approved costs ready for billing or reporting."
          icon="hero-check-badge"
          accent="emerald"
        />
        <.stat_card
          title="Amount"
          value={format_amount(@expense_total)}
          description="Aggregate amount represented by the current expense register."
          icon="hero-banknotes"
          accent="rose"
        />
      </div>

      <.section
        title="Expense Register"
        description="Keep customer-facing and delivery-supporting costs visible as their own operational finance lane."
        compact
        body_class="p-0"
      >
        <div :if={@expense_count == 0} class="p-6 sm:p-7">
          <.empty_state
            icon="hero-credit-card"
            title="No expenses yet"
            description="Create expenses when non-labor costs are incurred so approvals and billing stay grounded in real source rows."
          >
            <:action>
              <.button navigate={~p"/finance/expenses/new"} variant="primary">
                Create Expense
              </.button>
            </:action>
          </.empty_state>
        </div>

        <div :if={@expense_count > 0} class="overflow-x-auto">
          <table class="min-w-full divide-y divide-zinc-200 text-sm dark:divide-white/10">
            <thead class="bg-zinc-50 dark:bg-white/[0.03]">
              <tr>
                <th class="px-5 py-3 text-left font-medium text-zinc-500 dark:text-zinc-400">
                  Expense
                </th>
                <th class="px-5 py-3 text-left font-medium text-zinc-500 dark:text-zinc-400">
                  Context
                </th>
                <th class="px-5 py-3 text-left font-medium text-zinc-500 dark:text-zinc-400">
                  Category
                </th>
                <th class="px-5 py-3 text-left font-medium text-zinc-500 dark:text-zinc-400">
                  Amount
                </th>
                <th class="px-5 py-3 text-left font-medium text-zinc-500 dark:text-zinc-400">
                  Status
                </th>
              </tr>
            </thead>
            <tbody
              id="expenses"
              phx-update="stream"
              class="divide-y divide-zinc-200 dark:divide-white/10"
            >
              <tr :for={{dom_id, expense} <- @streams.expenses} id={dom_id}>
                <td class="px-5 py-4 align-top">
                  <div class="space-y-1">
                    <.link
                      navigate={~p"/finance/expenses/#{expense}"}
                      class="font-medium text-zinc-900 hover:text-emerald-600 dark:text-white"
                    >
                      {expense.description}
                    </.link>
                    <p class="text-sm text-zinc-500 dark:text-zinc-400">
                      {format_date(expense.incurred_on)}
                    </p>
                  </div>
                </td>
                <td class="px-5 py-4 align-top text-zinc-600 dark:text-zinc-300">
                  <div class="space-y-1">
                    <p>{(expense.organization && expense.organization.name) || "-"}</p>
                    <p class="text-xs text-zinc-400 dark:text-zinc-500">
                      {(expense.project && expense.project.name) ||
                        (expense.work_order && expense.work_order.title) || "No project/work order"}
                    </p>
                  </div>
                </td>
                <td class="px-5 py-4 align-top text-zinc-600 dark:text-zinc-300">
                  <div class="space-y-1">
                    <p>{format_atom(expense.category)}</p>
                    <p class="text-xs text-zinc-400 dark:text-zinc-500">
                      {expense.vendor || "No vendor"}
                    </p>
                  </div>
                </td>
                <td class="px-5 py-4 align-top text-zinc-600 dark:text-zinc-300">
                  <div class="space-y-1">
                    <p>{format_amount(expense.amount)}</p>
                    <p class="text-xs text-zinc-400 dark:text-zinc-500">
                      {if(expense.billable, do: "Billable", else: "Non-billable")}
                    </p>
                  </div>
                </td>
                <td class="px-5 py-4 align-top">
                  <.status_badge status={expense.status_variant}>
                    {format_atom(expense.status)}
                  </.status_badge>
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </.section>
    </.page>
    """
  end

  defp load_expenses(actor) do
    case Finance.list_expenses(
           actor: actor,
           query: [sort: [incurred_on: :desc, inserted_at: :desc]],
           load: [:status_variant, organization: [], project: [], work_order: []]
         ) do
      {:ok, expenses} -> expenses
      {:error, error} -> raise "failed to load expenses: #{inspect(error)}"
    end
  end
end
