defmodule GnomeGardenWeb.Finance.BankRuleLive.Index do
  use GnomeGardenWeb, :live_view

  import GnomeGardenWeb.Finance.Helpers

  alias GnomeGarden.Banking
  alias GnomeGarden.Banking.BankRule
  alias Phoenix.LiveView.JS

  @direction_options [
    {"Both", :both},
    {"Money in", :credit},
    {"Money out", :debit}
  ]

  @amount_operator_options [
    {"No amount condition", ""},
    {"Less than", :lt},
    {"Greater than", :gt},
    {"Less than or equal", :lte},
    {"Greater than or equal", :gte},
    {"Equal to", :eq}
  ]

  @match_behavior_options [
    {"Do not match", :none},
    {"Suggest a match", :suggest},
    {"Auto-accept exact match", :auto_accept_when_exact}
  ]

  @review_status_options [
    {"Needs review", :needs_review},
    {"Auto matched", :auto_matched},
    {"Reviewed", :reviewed},
    {"Ignored", :ignored}
  ]

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Bank Rules")
     |> assign(:rule, nil)
     |> assign(:rule_modal?, false)
     |> assign(:direction_options, @direction_options)
     |> assign(:amount_operator_options, @amount_operator_options)
     |> assign(:category_options, bank_transaction_category_options())
     |> assign(:match_behavior_options, @match_behavior_options)
     |> assign(:review_status_options, @review_status_options)
     |> assign(:form, nil)
     |> load_rules()}
  end

  @impl true
  def handle_event("new_rule", _params, socket) do
    {:noreply,
     socket
     |> assign(:rule, nil)
     |> assign(:rule_modal?, true)
     |> assign_form()}
  end

  @impl true
  def handle_event("edit_rule", %{"id" => id}, socket) do
    rule = load_rule!(id, socket.assigns.current_user)

    {:noreply,
     socket
     |> assign(:rule, rule)
     |> assign(:rule_modal?, true)
     |> assign_form()}
  end

  @impl true
  def handle_event("close_rule_modal", _params, socket) do
    {:noreply, assign(socket, rule: nil, rule_modal?: false, form: nil)}
  end

  @impl true
  def handle_event("validate", %{"form" => params}, socket) do
    form = AshPhoenix.Form.validate(socket.assigns.form.source, params)
    {:noreply, assign(socket, form: to_form(form))}
  end

  @impl true
  def handle_event("save", %{"form" => params}, socket) do
    case AshPhoenix.Form.submit(socket.assigns.form.source, params: params) do
      {:ok, rule} ->
        action = if socket.assigns.rule, do: "updated", else: "created"

        {:noreply,
         socket
         |> put_flash(:info, "Bank rule #{action}.")
         |> assign(:rule, nil)
         |> assign(:rule_modal?, false)
         |> assign(:form, nil)
         |> load_rules()
         |> maybe_highlight_rule(rule)}

      {:error, form} ->
        {:noreply, assign(socket, form: to_form(form))}
    end
  end

  @impl true
  def handle_event("toggle_rule", %{"id" => id}, socket) do
    rule = load_rule!(id, socket.assigns.current_user)

    result =
      if rule.enabled do
        Banking.disable_bank_rule(rule, actor: socket.assigns.current_user)
      else
        Banking.enable_bank_rule(rule, actor: socket.assigns.current_user)
      end

    case result do
      {:ok, _rule} ->
        {:noreply, load_rules(socket)}

      {:error, error} ->
        {:noreply, put_flash(socket, :error, error_message(error))}
    end
  end

  @impl true
  def handle_event("delete_rule", %{"id" => id}, socket) do
    rule = load_rule!(id, socket.assigns.current_user)

    case Banking.delete_bank_rule(rule, actor: socket.assigns.current_user) do
      {:ok, _rule} ->
        {:noreply,
         socket
         |> put_flash(:info, "Bank rule deleted.")
         |> load_rules()}

      {:error, error} ->
        {:noreply, put_flash(socket, :error, error_message(error))}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.page class="pb-8">
      <.page_header eyebrow="Finance">
        Bank Rules
        <:subtitle>
          Maintain provider-neutral automation that categorizes new bank transactions before review.
        </:subtitle>
        <:actions>
          <.button navigate={~p"/finance/banking"}>
            <.icon name="hero-building-library" class="size-4" /> Banking
          </.button>
          <.button id="open-bank-rule-modal" phx-click="new_rule" variant="primary">
            <.icon name="hero-plus" class="size-4" /> New Rule
          </.button>
        </:actions>
      </.page_header>

      <div class="grid grid-cols-2 gap-2 sm:gap-3 lg:grid-cols-4">
        <.stat_card
          title="Rules"
          value={Integer.to_string(length(@rules))}
          description="Automation rules in priority order."
          icon="hero-funnel"
        />
        <.stat_card
          title="Enabled"
          value={Integer.to_string(@enabled_count)}
          description="Rules currently applied after sync."
          icon="hero-bolt"
          accent="sky"
        />
        <.stat_card
          title="Auto Review"
          value={Integer.to_string(@auto_review_count)}
          description="Rules that can mark transactions reviewed."
          icon="hero-check-circle"
          accent="amber"
        />
        <.stat_card
          title="Matching"
          value={Integer.to_string(@matching_count)}
          description="Rules that can suggest or accept matches."
          icon="hero-link"
          accent="rose"
        />
      </div>

      <.section
        title="Automation Rules"
        description="Rules run from lowest priority to highest. Keep them narrow enough that review outcomes remain explainable."
        compact
      >
        <div :if={@rules == []} class="p-3 sm:p-4">
          <.empty_state
            icon="hero-funnel"
            title="No bank rules yet"
            description="Add rules for repeatable bank activity such as customer ACH deposits, bank fees, interest, taxes, payroll, and internal transfers."
          >
            <:action>
              <.button phx-click="new_rule" variant="primary">New Rule</.button>
            </:action>
          </.empty_state>
        </div>

        <div :if={@rules != []} class="md:hidden">
          <div class="divide-y divide-base-content/10">
            <.rule_card :for={rule <- @rules} rule={rule} />
          </div>
        </div>

        <div :if={@rules != []} class="hidden md:block">
          <div class="overflow-x-auto">
            <table class="min-w-full divide-y divide-base-content/10 text-sm">
              <thead class="bg-base-200/60">
                <tr>
                  <th class="px-4 py-3 text-left text-xs font-semibold uppercase text-base-content/50">
                    Priority
                  </th>
                  <th class="px-4 py-3 text-left text-xs font-semibold uppercase text-base-content/50">
                    Rule
                  </th>
                  <th class="px-4 py-3 text-left text-xs font-semibold uppercase text-base-content/50">
                    Conditions
                  </th>
                  <th class="px-4 py-3 text-left text-xs font-semibold uppercase text-base-content/50">
                    Outcome
                  </th>
                  <th class="px-4 py-3 text-right text-xs font-semibold uppercase text-base-content/50">
                    Actions
                  </th>
                </tr>
              </thead>
              <tbody class="divide-y divide-base-content/10">
                <tr :for={rule <- @rules} id={"bank-rule-row-#{rule.id}"} class="bg-base-100">
                  <td class="px-4 py-4 align-top tabular-nums text-base-content/70">
                    {rule.priority}
                  </td>
                  <td class="px-4 py-4 align-top">
                    <div class="space-y-1">
                      <div class="flex items-center gap-2">
                        <p class="font-semibold text-base-content">{rule.name}</p>
                        <.status_badge status={if rule.enabled, do: :success, else: :default}>
                          {if rule.enabled, do: "Enabled", else: "Disabled"}
                        </.status_badge>
                      </div>
                      <p :if={rule.auto_note} class="max-w-md text-xs text-base-content/55">
                        {rule.auto_note}
                      </p>
                    </div>
                  </td>
                  <td class="px-4 py-4 align-top text-base-content/70">
                    <div class="space-y-1">
                      <p>{format_atom(rule.direction)}</p>
                      <p>{condition_summary(rule)}</p>
                      <p>{amount_condition_label(rule)}</p>
                    </div>
                  </td>
                  <td class="px-4 py-4 align-top text-base-content/70">
                    <div class="space-y-1">
                      <p>{format_atom(rule.category)}</p>
                      <p>{format_atom(rule.review_status_result)}</p>
                      <p>{format_atom(rule.match_behavior)}</p>
                    </div>
                  </td>
                  <td class="px-4 py-4 align-top">
                    <div class="flex justify-end gap-2">
                      <button
                        type="button"
                        phx-click="toggle_rule"
                        phx-value-id={rule.id}
                        class="rounded-md border border-base-content/10 px-2.5 py-1.5 text-xs font-semibold text-base-content/70 hover:bg-base-200"
                      >
                        {if rule.enabled, do: "Disable", else: "Enable"}
                      </button>
                      <button
                        type="button"
                        phx-click="edit_rule"
                        phx-value-id={rule.id}
                        class="rounded-md border border-base-content/10 px-2.5 py-1.5 text-xs font-semibold text-base-content/70 hover:bg-base-200"
                      >
                        Edit
                      </button>
                      <button
                        type="button"
                        phx-click="delete_rule"
                        phx-value-id={rule.id}
                        data-confirm="Delete this bank rule?"
                        class="rounded-md border border-error/30 px-2.5 py-1.5 text-xs font-semibold text-error hover:bg-error/10"
                      >
                        Delete
                      </button>
                    </div>
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
        </div>
      </.section>

      <.modal :if={@rule_modal?} id="bank-rule-modal" on_cancel={JS.push("close_rule_modal")}>
        <:title>{if @rule, do: "Edit Bank Rule", else: "New Bank Rule"}</:title>

        <.form
          for={@form}
          id="bank-rule-form"
          phx-change="validate"
          phx-submit="save"
          class="space-y-4"
        >
          <div class="grid gap-4 sm:grid-cols-2">
            <div class="sm:col-span-2">
              <.input field={@form[:name]} label="Rule name" placeholder="Customer ACH deposits" />
            </div>
            <.input field={@form[:enabled]} type="checkbox" label="Enabled" />
            <.input field={@form[:priority]} type="number" label="Priority" />
          </div>

          <div class="grid gap-4 sm:grid-cols-2">
            <.input
              field={@form[:direction]}
              type="select"
              label="Direction"
              options={@direction_options}
            />
            <.input
              field={@form[:category]}
              type="select"
              label="Category"
              options={@category_options}
            />
          </div>

          <div class="grid gap-4 sm:grid-cols-2">
            <.input
              field={@form[:counterparty_contains]}
              label="Counterparty contains"
              placeholder="ACME"
            />
            <.input
              field={@form[:description_contains]}
              label="Description contains"
              placeholder="ACH"
            />
          </div>

          <div class="grid gap-4 sm:grid-cols-2">
            <.input
              field={@form[:amount_operator]}
              type="select"
              label="Amount condition"
              options={@amount_operator_options}
            />
            <.input field={@form[:amount_value]} type="number" step="0.01" label="Amount value" />
          </div>

          <div class="grid gap-4 sm:grid-cols-2">
            <.input
              field={@form[:review_status_result]}
              type="select"
              label="Review result"
              options={@review_status_options}
            />
            <.input
              field={@form[:match_behavior]}
              type="select"
              label="Match behavior"
              options={@match_behavior_options}
            />
          </div>

          <.input
            field={@form[:auto_note]}
            type="textarea"
            label="Auto note"
            placeholder="Why this rule applied"
          />

          <div class="flex flex-col-reverse gap-2 sm:flex-row sm:justify-end">
            <.button type="button" phx-click="close_rule_modal">Cancel</.button>
            <.button type="submit" variant="primary" phx-disable-with="Saving...">
              {if @rule, do: "Save Changes", else: "Create Rule"}
            </.button>
          </div>
        </.form>
      </.modal>
    </.page>
    """
  end

  attr :rule, :map, required: true

  defp rule_card(assigns) do
    ~H"""
    <div id={"bank-rule-card-#{@rule.id}"} class="space-y-3 bg-base-100 p-3">
      <div class="flex items-start justify-between gap-3">
        <div class="min-w-0">
          <div class="flex flex-wrap items-center gap-2">
            <p class="text-sm font-semibold text-base-content">{@rule.name}</p>
            <.status_badge status={if @rule.enabled, do: :success, else: :default}>
              {if @rule.enabled, do: "Enabled", else: "Disabled"}
            </.status_badge>
          </div>
          <p class="mt-1 text-xs text-base-content/50">
            Priority {@rule.priority} · {format_atom(@rule.direction)}
          </p>
        </div>
        <p class="shrink-0 text-sm font-medium text-base-content">
          {format_atom(@rule.category)}
        </p>
      </div>

      <div class="grid grid-cols-1 gap-2 text-xs text-base-content/65">
        <p>{condition_summary(@rule)}</p>
        <p>{amount_condition_label(@rule)}</p>
        <p>{format_atom(@rule.review_status_result)} · {format_atom(@rule.match_behavior)}</p>
        <p :if={@rule.auto_note} class="line-clamp-2">{@rule.auto_note}</p>
      </div>

      <div class="flex gap-2">
        <button
          type="button"
          phx-click="toggle_rule"
          phx-value-id={@rule.id}
          class="flex-1 rounded-md border border-base-content/10 px-2.5 py-2 text-xs font-semibold text-base-content/70 hover:bg-base-200"
        >
          {if @rule.enabled, do: "Disable", else: "Enable"}
        </button>
        <button
          type="button"
          phx-click="edit_rule"
          phx-value-id={@rule.id}
          class="flex-1 rounded-md border border-base-content/10 px-2.5 py-2 text-xs font-semibold text-base-content/70 hover:bg-base-200"
        >
          Edit
        </button>
        <button
          type="button"
          phx-click="delete_rule"
          phx-value-id={@rule.id}
          data-confirm="Delete this bank rule?"
          class="rounded-md border border-error/30 px-2.5 py-2 text-xs font-semibold text-error hover:bg-error/10"
          aria-label="Delete bank rule"
        >
          <.icon name="hero-trash" class="size-4" />
        </button>
      </div>
    </div>
    """
  end

  defp load_rules(socket) do
    case Banking.list_bank_rules(actor: socket.assigns.current_user) do
      {:ok, rules} ->
        socket
        |> assign(:rules, rules)
        |> assign(:enabled_count, Enum.count(rules, & &1.enabled))
        |> assign(:auto_review_count, Enum.count(rules, &(&1.review_status_result == :reviewed)))
        |> assign(:matching_count, Enum.count(rules, &(&1.match_behavior != :none)))

      {:error, error} ->
        raise "failed to load bank rules: #{inspect(error)}"
    end
  end

  defp load_rule!(id, actor) do
    case Banking.get_bank_rule(id, actor: actor) do
      {:ok, rule} -> rule
      {:error, error} -> raise "failed to load bank rule #{id}: #{inspect(error)}"
    end
  end

  defp assign_form(%{assigns: %{rule: rule, current_user: actor}} = socket) do
    form =
      if rule do
        AshPhoenix.Form.for_update(rule, :update, actor: actor, domain: Finance)
      else
        AshPhoenix.Form.for_create(BankRule, :create,
          actor: actor,
          domain: Finance,
          params: %{
            "enabled" => true,
            "priority" => next_rule_priority(socket.assigns.rules),
            "direction" => :both,
            "category" => :unknown,
            "review_status_result" => :needs_review,
            "match_behavior" => :none
          }
        )
      end

    assign(socket, :form, to_form(form))
  end

  defp next_rule_priority([]), do: 10

  defp next_rule_priority(rules) do
    rules
    |> Enum.map(&(&1.priority || 0))
    |> Enum.max()
    |> Kernel.+(10)
  end

  defp condition_summary(rule) do
    [
      maybe_condition("Counterparty", rule.counterparty_contains),
      maybe_condition("Description", rule.description_contains)
    ]
    |> Enum.reject(&is_nil/1)
    |> case do
      [] -> "Any counterparty or description"
      conditions -> Enum.join(conditions, " · ")
    end
  end

  defp maybe_condition(_label, nil), do: nil
  defp maybe_condition(_label, ""), do: nil
  defp maybe_condition(label, value), do: "#{label} contains #{value}"

  defp amount_condition_label(%{amount_operator: nil}), do: "Any amount"

  defp amount_condition_label(%{amount_operator: operator, amount_value: nil}),
    do: format_atom(operator)

  defp amount_condition_label(%{amount_operator: operator, amount_value: value}) do
    "#{amount_operator_label(operator)} #{Decimal.to_string(value)}"
  end

  defp amount_operator_label(:lt), do: "<"
  defp amount_operator_label(:gt), do: ">"
  defp amount_operator_label(:lte), do: "<="
  defp amount_operator_label(:gte), do: ">="
  defp amount_operator_label(:eq), do: "="
  defp amount_operator_label(operator), do: format_atom(operator)

  defp maybe_highlight_rule(socket, _rule), do: socket

  defp error_message(error) do
    error
    |> Ash.Error.to_error_class()
    |> Exception.message()
  rescue
    _ -> "Could not update bank rule."
  end
end
