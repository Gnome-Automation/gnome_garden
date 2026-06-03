defmodule GnomeGardenWeb.Finance.BankRuleLive.Form do
  use GnomeGardenWeb, :live_view

  alias GnomeGarden.Mercury
  alias GnomeGarden.Mercury.BankRule

  @impl true
  def mount(params, _session, socket) do
    rule = if id = params["id"], do: load_rule!(id)

    {:ok,
     socket
     |> assign(:page_title, if(rule, do: "Edit Bank Rule", else: "New Bank Rule"))
     |> assign(:rule, rule)
     |> assign_form()}
  end

  @impl true
  def handle_event("validate", %{"bank_rule" => params}, socket) do
    form = AshPhoenix.Form.validate(socket.assigns.form, params)
    {:noreply, assign(socket, form: to_form(form))}
  end

  @impl true
  def handle_event("save", %{"bank_rule" => params}, socket) do
    case AshPhoenix.Form.submit(socket.assigns.form, params: params) do
      {:ok, _rule} ->
        {:noreply,
         socket
         |> put_flash(:info, "Bank rule #{if socket.assigns.rule, do: "updated", else: "created"}")
         |> push_navigate(to: ~p"/finance/bank-rules")}

      {:error, form} ->
        {:noreply,
         socket
         |> put_flash(:error, "Please fix the errors below.")
         |> assign(form: to_form(form))}
    end
  end

  defp assign_form(%{assigns: %{rule: rule}} = socket) do
    form =
      if rule do
        AshPhoenix.Form.for_update(rule, :update, actor: nil, domain: Mercury)
      else
        AshPhoenix.Form.for_create(BankRule, :create, actor: nil, domain: Mercury)
      end

    assign(socket, :form, to_form(form))
  end

  defp load_rule!(id) do
    case Mercury.get_bank_rule(id, authorize?: false) do
      {:ok, rule} -> rule
      {:error, error} -> raise "failed to load bank rule #{id}: #{inspect(error)}"
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.page class="pb-8">
      <.page_header eyebrow="Finance">
        {@page_title}
        <:actions>
          <.button navigate={~p"/finance/bank-rules"}>Cancel</.button>
        </:actions>
      </.page_header>

      <.section>
        <.form
          for={@form}
          id="bank-rule-form"
          phx-change="validate"
          phx-submit="save"
          class="space-y-6 px-5 py-5"
        >
          <div>
            <.input field={@form[:name]} label="Name" required placeholder="e.g. Stripe Fees" />
          </div>

          <div>
            <.input
              field={@form[:priority]}
              type="number"
              label="Priority"
            />
            <p class="mt-1.5 text-xs text-base-content/50">
              Lower number runs first. Use the ↑↓ buttons on the list to reorder.
            </p>
          </div>

          <div>
            <.input
              field={@form[:direction]}
              type="select"
              label="Direction"
              prompt="Select direction"
              options={[{"Both", "both"}, {"Money In", "money_in"}, {"Money Out", "money_out"}]}
              required
            />
          </div>

          <div>
            <.input
              field={@form[:counterparty_contains]}
              label="Counterparty contains"
              placeholder="e.g. STRIPE, AWS, GUSTO"
            />
            <p class="mt-1.5 text-xs text-base-content/50">
              Case-insensitive. Leave blank to match any counterparty.
            </p>
          </div>

          <div>
            <p class="block text-sm/6 font-medium text-gray-900 dark:text-white">
              Amount condition (optional)
            </p>
            <div class="flex gap-2 mt-2">
              <div class="flex-1">
                <.input
                  field={@form[:amount_operator]}
                  type="select"
                  label=""
                  prompt="No condition"
                  options={[
                    {"Less than", "lt"},
                    {"Greater than", "gt"},
                    {"Less than or equal", "lte"},
                    {"Greater than or equal", "gte"},
                    {"Equal to", "eq"}
                  ]}
                />
              </div>
              <div class="flex-1">
                <.input
                  field={@form[:amount_value]}
                  type="number"
                  label=""
                  step="0.01"
                  placeholder="Amount"
                />
              </div>
            </div>
          </div>

          <div>
            <.input
              field={@form[:reconciliation_category]}
              type="select"
              label="Category"
              prompt="Select category"
              options={[
                {"Bank Fee", "bank_fee"},
                {"Internal Transfer", "internal_transfer"},
                {"Misc Income", "misc_income"},
                {"Refund", "refund"},
                {"Interest Income", "interest_income"},
                {"Owner Draw", "owner_draw"},
                {"Other", "other"}
              ]}
              required
            />
          </div>

          <div>
            <.input
              field={@form[:auto_note]}
              label="Default note (optional)"
              placeholder="e.g. Monthly Stripe processing fee"
            />
          </div>

          <div class="flex gap-3">
            <.button type="submit" phx-disable-with="Saving...">
              {if @rule, do: "Update Rule", else: "Create Rule"}
            </.button>
            <.button navigate={~p"/finance/bank-rules"}>Cancel</.button>
          </div>
        </.form>
      </.section>
    </.page>
    """
  end
end
