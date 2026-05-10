defmodule GnomeGardenWeb.Finance.ExpenseLive.Show do
  use GnomeGardenWeb, :live_view

  import GnomeGardenWeb.Finance.Helpers

  alias GnomeGarden.Finance

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    expense = load_expense!(id, socket.assigns.current_user)

    {:ok,
     socket
     |> assign(:page_title, "Expense")
     |> assign(:expense, expense)}
  end

  @impl true
  def handle_event("transition", %{"action" => action}, socket) do
    expense = socket.assigns.expense
    actor = socket.assigns.current_user

    case transition_expense(expense, String.to_existing_atom(action), actor) do
      {:ok, updated_expense} ->
        {:noreply,
         socket
         |> assign(:expense, load_expense!(updated_expense.id, actor))
         |> put_flash(:info, "Expense updated")}

      {:error, error} ->
        {:noreply, put_flash(socket, :error, "Could not update expense: #{inspect(error)}")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.page class="pb-8">
      <.page_header eyebrow="Finance">
        Expense
        <:subtitle>
          <span class="inline-flex items-center gap-2">
            <.status_badge status={@expense.status_variant}>
              {format_atom(@expense.status)}
            </.status_badge>
            <span class="text-base-content/40">/</span>
            <span>{format_date(@expense.incurred_on)}</span>
          </span>
        </:subtitle>
        <:actions>
          <.button navigate={~p"/finance/expenses"}>
            Back
          </.button>
          <.button :if={@expense.project} navigate={~p"/execution/projects/#{@expense.project}"}>
            Project
          </.button>
          <.button
            :if={@expense.work_order}
            navigate={~p"/execution/work-orders/#{@expense.work_order}"}
          >
            Work Order
          </.button>
          <.button navigate={~p"/finance/expenses/#{@expense}/edit"}>
            Edit
          </.button>
        </:actions>
      </.page_header>

      <.section
        title="Expense Actions"
        description="Advance non-labor costs explicitly so approvals, billing, and contract-consumption logic can trust the record."
      >
        <div class="flex flex-wrap gap-3">
          <.button
            :for={action <- expense_actions(@expense)}
            phx-click="transition"
            phx-value-action={action.action}
            variant={action.variant}
          >
            <.icon name={action.icon} class="size-4" /> {action.label}
          </.button>
        </div>
      </.section>

      <div class="grid gap-6 lg:grid-cols-2">
        <.section title="Expense Snapshot">
          <div class="grid gap-5 sm:grid-cols-2">
            <.property_item label="Incurred On" value={format_date(@expense.incurred_on)} />
            <.property_item label="Category" value={format_atom(@expense.category)} />
            <.property_item label="Amount" value={format_amount(@expense.amount)} />
            <.property_item label="Vendor" value={@expense.vendor || "-"} />
            <.property_item
              label="Billable"
              value={if(@expense.billable, do: "Yes", else: "No")}
            />
            <.property_item
              label="Incurred By"
              value={display_team_member(@expense.incurred_by_team_member)}
            />
            <.property_item
              label="Approved By"
              value={display_team_member(@expense.approved_by_team_member)}
            />
            <.property_item label="Approved At" value={format_datetime(@expense.approved_at)} />
            <.property_item label="Billed At" value={format_datetime(@expense.billed_at)} />
            <.property_item
              label="Entitlement Usage"
              value={Integer.to_string(@expense.entitlement_usage_count || 0)}
            />
          </div>
        </.section>

        <.section title="Operational Context">
          <div class="grid gap-5 sm:grid-cols-2">
            <.property_item
              label="Organization"
              value={(@expense.organization && @expense.organization.name) || "-"}
            />
            <.property_item
              label="Agreement"
              value={(@expense.agreement && @expense.agreement.name) || "-"}
            />
            <.property_item
              label="Project"
              value={(@expense.project && @expense.project.name) || "-"}
            />
            <.property_item
              label="Work Order"
              value={(@expense.work_order && @expense.work_order.title) || "-"}
            />
            <.property_item label="Receipt URL" value={@expense.receipt_url || "-"} />
          </div>
        </.section>
      </div>

      <.section title="Description">
        <p class="whitespace-pre-wrap text-sm leading-6 text-base-content/70">
          {@expense.description}
        </p>
      </.section>

      <.section :if={@expense.notes} title="Notes">
        <p class="whitespace-pre-wrap text-sm leading-6 text-base-content/70">
          {@expense.notes}
        </p>
      </.section>
    </.page>
    """
  end

  attr :label, :string, required: true
  attr :value, :string, required: true

  defp property_item(assigns) do
    ~H"""
    <div class="space-y-1">
      <p class="text-xs font-semibold uppercase tracking-[0.2em] text-base-content/40">
        {@label}
      </p>
      <p class="text-sm font-medium text-base-content">{@value}</p>
    </div>
    """
  end

  defp load_expense!(id, actor) do
    case Finance.get_expense(
           id,
           actor: actor,
           load: [
             :status_variant,
             :entitlement_usage_count,
             incurred_by_team_member: [],
             approved_by_team_member: [],
             organization: [],
             agreement: [],
             project: [],
             work_order: []
           ]
         ) do
      {:ok, expense} -> expense
      {:error, error} -> raise "failed to load expense #{id}: #{inspect(error)}"
    end
  end

  defp expense_actions(%{status: :draft}) do
    [
      %{action: "submit", label: "Submit", icon: "hero-paper-airplane", variant: "primary"}
    ]
  end

  defp expense_actions(%{status: :submitted}) do
    [
      %{action: "approve", label: "Approve", icon: "hero-check-badge", variant: "primary"},
      %{action: "reject", label: "Reject", icon: "hero-x-circle", variant: nil}
    ]
  end

  defp expense_actions(%{status: :approved}) do
    [
      %{action: "mark_billed", label: "Mark Billed", icon: "hero-banknotes", variant: "primary"},
      %{action: "reopen", label: "Reopen", icon: "hero-arrow-path", variant: nil}
    ]
  end

  defp expense_actions(%{status: :rejected}) do
    [
      %{action: "reopen", label: "Reopen", icon: "hero-arrow-path", variant: "primary"}
    ]
  end

  defp expense_actions(_expense), do: []

  defp transition_expense(expense, :submit, actor),
    do: Finance.submit_expense(expense, actor: actor)

  defp transition_expense(expense, :approve, actor) do
    params =
      if actor do
        %{approved_by_team_member_id: current_team_member_id(actor)}
      else
        %{}
      end

    Finance.approve_expense(expense, params, actor: actor)
  end

  defp transition_expense(expense, :reject, actor),
    do: Finance.reject_expense(expense, actor: actor)

  defp transition_expense(expense, :mark_billed, actor),
    do: Finance.bill_expense(expense, actor: actor)

  defp transition_expense(expense, :reopen, actor),
    do: Finance.reopen_expense(expense, actor: actor)

  defp current_team_member_id(nil), do: nil

  defp current_team_member_id(actor) do
    case GnomeGarden.Operations.get_team_member_by_user(actor.id, actor: actor) do
      {:ok, team_member} -> team_member.id
      {:error, _error} -> nil
    end
  end
end
