defmodule GnomeGardenWeb.Finance.BankRuleLive.Index do
  use GnomeGardenWeb, :live_view

  alias GnomeGarden.Mercury

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Bank Rules")
     |> assign(:rules, load_rules())}
  end

  @impl true
  def handle_event("reorder", %{"id" => id, "direction" => direction}, socket) do
    rule = Enum.find(socket.assigns.rules, &(&1.id == id))
    direction = String.to_existing_atom(direction)
    Mercury.reorder_bank_rule(rule, direction)
    {:noreply, assign(socket, :rules, load_rules())}
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    rule = Enum.find(socket.assigns.rules, &(&1.id == id))
    Mercury.delete_bank_rule(rule, authorize?: false)
    {:noreply, assign(socket, :rules, load_rules())}
  end

  defp load_rules do
    Mercury.list_bank_rules!(authorize?: false)
  end

  defp category_label(:bank_fee), do: "Bank Fee"
  defp category_label(:internal_transfer), do: "Internal Transfer"
  defp category_label(:misc_income), do: "Misc Income"
  defp category_label(:refund), do: "Refund"
  defp category_label(:interest_income), do: "Interest Income"
  defp category_label(:owner_draw), do: "Owner Draw"
  defp category_label(:other), do: "Other"

  defp direction_label(:money_in), do: "Money In"
  defp direction_label(:money_out), do: "Money Out"
  defp direction_label(:both), do: "Both"

  defp amount_condition_label(nil, _), do: "—"
  defp amount_condition_label(:lt, v), do: "< #{v}"
  defp amount_condition_label(:gt, v), do: "> #{v}"
  defp amount_condition_label(:lte, v), do: "≤ #{v}"
  defp amount_condition_label(:gte, v), do: "≥ #{v}"
  defp amount_condition_label(:eq, v), do: "= #{v}"

  @impl true
  def render(assigns) do
    ~H"""
    <.page class="pb-8">
      <.page_header eyebrow="Finance">
        Bank Rules
        <:subtitle>
          Auto-categorize Mercury transactions based on counterparty name, direction, and amount.
          Rules are evaluated in priority order — first match wins.
        </:subtitle>
        <:actions>
          <.button navigate={~p"/finance/bank-rules/new"} variant="primary">New Rule</.button>
        </:actions>
      </.page_header>

      <%= if Enum.empty?(@rules) do %>
        <.empty_state
          icon="hero-funnel"
          title="No bank rules yet"
          description="Create a rule to automatically categorize recurring transactions like bank fees, payroll, or AWS charges."
        >
          <:action>
            <.button navigate={~p"/finance/bank-rules/new"} variant="primary">New Rule</.button>
          </:action>
        </.empty_state>
      <% else %>
        <.section body_class="p-0">
          <div class="overflow-x-auto">
            <table class="min-w-full divide-y divide-zinc-200 text-sm dark:divide-white/10">
              <thead class="bg-zinc-50 dark:bg-white/[0.03]">
                <tr>
                  <th class="px-5 py-3 text-left font-medium text-zinc-500 dark:text-zinc-400">Priority</th>
                  <th class="px-5 py-3 text-left font-medium text-zinc-500 dark:text-zinc-400">Name</th>
                  <th class="px-5 py-3 text-left font-medium text-zinc-500 dark:text-zinc-400">Direction</th>
                  <th class="px-5 py-3 text-left font-medium text-zinc-500 dark:text-zinc-400">Counterparty contains</th>
                  <th class="px-5 py-3 text-left font-medium text-zinc-500 dark:text-zinc-400">Amount</th>
                  <th class="px-5 py-3 text-left font-medium text-zinc-500 dark:text-zinc-400">Category</th>
                  <th class="px-5 py-3"></th>
                </tr>
              </thead>
              <tbody class="divide-y divide-zinc-200 dark:divide-white/10">
                <tr :for={rule <- @rules}>
                  <td class="px-5 py-4 text-zinc-900 dark:text-white">{rule.priority}</td>
                  <td class="px-5 py-4 font-medium text-zinc-900 dark:text-white">{rule.name}</td>
                  <td class="px-5 py-4 text-zinc-700 dark:text-zinc-300">{direction_label(rule.direction)}</td>
                  <td class="px-5 py-4 font-mono text-xs text-zinc-600 dark:text-zinc-400">
                    {rule.counterparty_contains || "Any"}
                  </td>
                  <td class="px-5 py-4 text-zinc-600 dark:text-zinc-400">
                    {amount_condition_label(rule.amount_operator, rule.amount_value)}
                  </td>
                  <td class="px-5 py-4 text-zinc-700 dark:text-zinc-300">
                    {category_label(rule.reconciliation_category)}
                  </td>
                  <td class="px-5 py-4 text-right">
                    <div class="flex items-center justify-end gap-2">
                      <button
                        phx-click="reorder"
                        phx-value-id={rule.id}
                        phx-value-direction="up"
                        class="rounded border border-zinc-300 px-2 py-0.5 text-xs font-semibold text-zinc-700 hover:bg-zinc-50 dark:border-white/10 dark:text-zinc-300 dark:hover:bg-white/5 cursor-pointer transition-colors"
                      >
                        ↑
                      </button>
                      <button
                        phx-click="reorder"
                        phx-value-id={rule.id}
                        phx-value-direction="down"
                        class="rounded border border-zinc-300 px-2 py-0.5 text-xs font-semibold text-zinc-700 hover:bg-zinc-50 dark:border-white/10 dark:text-zinc-300 dark:hover:bg-white/5 cursor-pointer transition-colors"
                      >
                        ↓
                      </button>
                      <.button navigate={~p"/finance/bank-rules/#{rule.id}/edit"}>Edit</.button>
                      <button
                        phx-click="delete"
                        phx-value-id={rule.id}
                        data-confirm="Delete this rule?"
                        class="rounded-md border border-red-300 px-2.5 py-1 text-xs font-semibold text-red-600 hover:bg-red-50 dark:border-red-500/50 dark:text-red-400 dark:hover:bg-red-900/20 cursor-pointer transition-colors"
                      >
                        Delete
                      </button>
                    </div>
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
        </.section>
      <% end %>
    </.page>
    """
  end
end
