defmodule GnomeGardenWeb.Finance.WorkToBillLive do
  use GnomeGardenWeb, :live_view

  import GnomeGardenWeb.Finance.Helpers

  alias GnomeGarden.Finance

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Work to Bill")
     |> load_workspace()}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.page class="pb-8">
      <.page_header eyebrow="Finance">
        Work to Bill
        <:subtitle>
          Approved billable time and expenses grouped into invoice candidates.
        </:subtitle>
        <:actions>
          <.button navigate={~p"/finance/time-entries/new"}>
            <.icon name="hero-clock" class="size-4" /> Add Time
          </.button>
          <.button navigate={~p"/finance/expenses/new"}>
            <.icon name="hero-receipt-percent" class="size-4" /> Add Expense
          </.button>
          <.button navigate={~p"/finance/invoices/new"} variant="primary">
            <.icon name="hero-plus" class="size-4" /> New Invoice
          </.button>
        </:actions>
      </.page_header>

      <div class="grid gap-2 sm:grid-cols-2 lg:grid-cols-4">
        <.stat_card
          title="Ready"
          value={format_amount(@ready_total)}
          description={"#{@source_group_count} customer groups"}
          icon="hero-document-check"
        />
        <.stat_card
          title="Labor"
          value={format_hours(@billable_minutes)}
          description={"#{@time_entry_count} approved entries"}
          icon="hero-clock"
          accent="sky"
        />
        <.stat_card
          title="Expenses"
          value={format_amount(@expense_total)}
          description={"#{@expense_count} approved expenses"}
          icon="hero-receipt-percent"
          accent="amber"
        />
        <.stat_card
          title="Labor Value"
          value={format_amount(@labor_total)}
          description="Approved labor with bill rates"
          icon="hero-currency-dollar"
          accent="emerald"
        />
      </div>

      <.section
        title="Invoice Candidates"
        description="Groups of approved billable sources that can become draft invoices."
      >
        <div :if={@source_groups == []}>
          <.empty_state
            icon="hero-check-circle"
            title="Nothing ready to bill"
            description="Approved billable time and expenses will appear here before invoicing."
          />
        </div>

        <div :if={@source_groups != []} class="grid gap-2 lg:grid-cols-2">
          <.candidate_card :for={group <- @source_groups} group={group} />
        </div>
      </.section>

      <div class="grid gap-3 xl:grid-cols-2">
        <.section
          title="Approved Time"
          description="Billable labor approved but not yet included on an invoice."
        >
          <div :if={@time_entries == []}>
            <.empty_state
              icon="hero-clock"
              title="No approved time waiting"
              description="Approved billable time entries will appear here."
            />
          </div>

          <div :if={@time_entries != []} class="space-y-2">
            <.time_entry_card :for={entry <- Enum.take(@time_entries, 8)} entry={entry} />
          </div>
        </.section>

        <.section
          title="Approved Expenses"
          description="Billable costs approved but not yet included on an invoice."
        >
          <div :if={@expenses == []}>
            <.empty_state
              icon="hero-receipt-percent"
              title="No approved expenses waiting"
              description="Approved billable expenses will appear here."
            />
          </div>

          <div :if={@expenses != []} class="space-y-2">
            <.expense_card :for={expense <- Enum.take(@expenses, 8)} expense={expense} />
          </div>
        </.section>
      </div>
    </.page>
    """
  end

  attr :group, :map, required: true

  defp candidate_card(assigns) do
    ~H"""
    <div class="rounded-lg border border-base-content/10 bg-base-200 px-3 py-3">
      <div class="flex flex-col gap-3 sm:flex-row sm:items-start sm:justify-between">
        <div class="min-w-0 space-y-1">
          <p class="truncate font-semibold text-base-content">{@group.organization_name}</p>
          <p class="truncate text-sm text-base-content/60">{@group.agreement_name}</p>
          <p class="text-xs text-base-content/50">
            {@group.time_entry_count} time entries - {@group.expense_count} expenses - Latest {format_date(
              @group.latest_on
            )}
          </p>
        </div>

        <div class="flex shrink-0 items-center justify-between gap-3 sm:flex-col sm:items-end">
          <p class="font-semibold tabular-nums">{format_amount(@group.total_amount)}</p>
          <.button
            :if={@group.agreement_id}
            navigate={~p"/finance/invoices/new?agreement_id=#{@group.agreement_id}"}
            variant="primary"
          >
            Draft Invoice
          </.button>
          <.button :if={!@group.agreement_id} navigate={~p"/finance/invoices/new"}>
            New Invoice
          </.button>
        </div>
      </div>
    </div>
    """
  end

  attr :entry, :map, required: true

  defp time_entry_card(assigns) do
    ~H"""
    <div class="rounded-lg border border-base-content/10 bg-base-200 px-3 py-3">
      <div class="flex items-start justify-between gap-3">
        <div class="min-w-0 space-y-1">
          <p class="truncate font-semibold text-base-content">{@entry.description}</p>
          <p class="truncate text-sm text-base-content/60">
            {organization_name(@entry)} - {scope_name(@entry)}
          </p>
          <p class="text-xs text-base-content/50">
            {format_date(@entry.work_date)} - {display_team_member(@entry.member_team_member)}
          </p>
        </div>

        <div class="shrink-0 text-right">
          <p class="font-semibold tabular-nums">{format_minutes(@entry.minutes)}</p>
          <p class="text-xs text-base-content/50">{format_amount(@entry.billable_amount)}</p>
        </div>
      </div>
    </div>
    """
  end

  attr :expense, :map, required: true

  defp expense_card(assigns) do
    ~H"""
    <div class="rounded-lg border border-base-content/10 bg-base-200 px-3 py-3">
      <div class="flex items-start justify-between gap-3">
        <div class="min-w-0 space-y-1">
          <p class="truncate font-semibold text-base-content">{@expense.description}</p>
          <p class="truncate text-sm text-base-content/60">
            {organization_name(@expense)} - {scope_name(@expense)}
          </p>
          <p class="text-xs text-base-content/50">
            {format_atom(@expense.category)} - {format_date(@expense.incurred_on)}
          </p>
        </div>

        <div class="shrink-0 text-right">
          <p class="font-semibold tabular-nums">{format_amount(@expense.amount)}</p>
          <p class="text-xs text-base-content/50">{@expense.vendor || "No vendor"}</p>
        </div>
      </div>
    </div>
    """
  end

  defp load_workspace(socket) do
    workspace = Finance.get_work_to_bill_workspace!(actor: socket.assigns.current_user)

    socket
    |> assign(:time_entries, workspace.time_entries)
    |> assign(:expenses, workspace.expenses)
    |> assign(:source_groups, workspace.source_groups)
    |> assign(:time_entry_count, workspace.time_entry_count)
    |> assign(:expense_count, workspace.expense_count)
    |> assign(:source_group_count, workspace.source_group_count)
    |> assign(:billable_minutes, workspace.billable_minutes)
    |> assign(:labor_total, workspace.labor_total)
    |> assign(:expense_total, workspace.expense_total)
    |> assign(:ready_total, workspace.ready_total)
  end

  defp organization_name(%{organization: %Ash.NotLoaded{}}), do: "No organization"
  defp organization_name(%{organization: nil}), do: "No organization"
  defp organization_name(%{organization: %{name: name}}), do: name || "No organization"

  defp scope_name(%{project: %{name: name}}) when is_binary(name), do: name
  defp scope_name(%{work_order: %{title: title}}) when is_binary(title), do: title
  defp scope_name(%{agreement: %{name: name}}) when is_binary(name), do: name
  defp scope_name(_record), do: "No scope"

  defp format_hours(nil), do: "0 hr"
  defp format_hours(minutes), do: "#{Float.round(minutes / 60, 1)} hr"
end
