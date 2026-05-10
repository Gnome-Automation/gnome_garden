defmodule GnomeGardenWeb.Finance.ExpenseLive.Index do
  use GnomeGardenWeb, :live_view
  use Cinder.UrlSync

  import GnomeGardenWeb.Finance.Helpers

  alias GnomeGarden.Finance

  @impl true
  def mount(_params, _session, socket) do
    counts = load_counts(socket.assigns.current_user)

    {:ok,
     socket
     |> assign(:page_title, "Expenses")
     |> assign(:expense_count, counts.total)
     |> assign(:submitted_count, counts.submitted)
     |> assign(:approved_count, counts.approved)
     |> assign(:expense_total, counts.total_amount)}
  end

  @impl true
  def handle_params(params, uri, socket) do
    socket = Cinder.UrlSync.handle_params(params, uri, socket)
    {:noreply, socket}
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
            Work Orders
          </.button>
          <.button navigate={~p"/finance/expenses/new"} variant="primary">
            New Expense
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

      <Cinder.collection
        id="expenses-table"
        resource={GnomeGarden.Finance.Expense}
        actor={@current_user}
        url_state={@url_state}
        theme={GnomeGardenWeb.CinderTheme}
        page_size={25}
        query_opts={[
          load: [:status_variant, organization: [], project: [], work_order: []]
        ]}
        click={fn row -> JS.navigate(~p"/finance/expenses/#{row}") end}
      >
        <:col :let={expense} field="description" search sort label="Expense">
          <div class="space-y-1">
            <div class="font-medium text-base-content">{expense.description}</div>
            <p class="text-sm text-base-content/50">
              {format_date(expense.incurred_on)}
            </p>
          </div>
        </:col>

        <:col :let={expense} label="Context">
          <div class="space-y-1">
            <p>{(expense.organization && expense.organization.name) || "-"}</p>
            <p class="text-xs text-base-content/40">
              {(expense.project && expense.project.name) ||
                (expense.work_order && expense.work_order.title) || "No project/work order"}
            </p>
          </div>
        </:col>

        <:col :let={expense} field="vendor" search label="Category">
          <div class="space-y-1">
            <p>{format_atom(expense.category)}</p>
            <p class="text-xs text-base-content/40">
              {expense.vendor || "No vendor"}
            </p>
          </div>
        </:col>

        <:col :let={expense} field="amount" sort label="Amount">
          <div class="space-y-1">
            <p>{format_amount(expense.amount)}</p>
            <p class="text-xs text-base-content/40">
              {if(expense.billable, do: "Billable", else: "Non-billable")}
            </p>
          </div>
        </:col>

        <:col :let={expense} field="status" sort label="Status">
          <.status_badge status={expense.status_variant}>
            {format_atom(expense.status)}
          </.status_badge>
        </:col>

        <:empty>
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
        </:empty>
      </Cinder.collection>
    </.page>
    """
  end

  defp load_counts(actor) do
    case Finance.list_expenses(actor: actor) do
      {:ok, expenses} ->
        %{
          total: length(expenses),
          submitted: Enum.count(expenses, &(&1.status == :submitted)),
          approved: Enum.count(expenses, &(&1.status == :approved)),
          total_amount: sum_amounts(expenses, :amount)
        }

      {:error, _} ->
        %{total: 0, submitted: 0, approved: 0, total_amount: nil}
    end
  end
end
