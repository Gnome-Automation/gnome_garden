defmodule GnomeGardenWeb.Commercial.AgreementLive.Show do
  use GnomeGardenWeb, :live_view

  import GnomeGardenWeb.Commercial.Helpers

  alias GnomeGarden.Commercial
  alias GnomeGarden.Finance

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    actor = socket.assigns.current_user
    agreement = load_agreement!(id, actor)

    unbilled_expenses =
      case Finance.list_billable_expenses_for_agreement(agreement.id,
             actor: actor, authorize?: false) do
        {:ok, exps} -> exps
        _ -> []
      end

    {:ok,
     socket
     |> assign(:page_title, agreement.name)
     |> assign(:agreement, agreement)
     |> assign(:schedule_pct_total, compute_pct_total(agreement.payment_schedule_items))
     |> assign(:unbilled_expenses, unbilled_expenses)
     |> assign(:selected_expense_ids, MapSet.new())}
  end

  @impl true
  def handle_event("transition", %{"action" => action}, socket) do
    agreement = socket.assigns.agreement

    case transition_agreement(
           agreement,
           String.to_existing_atom(action),
           socket.assigns.current_user
         ) do
      {:ok, updated_agreement} ->
        {:noreply,
         socket
         |> assign(:agreement, load_agreement!(updated_agreement.id, socket.assigns.current_user))
         |> put_flash(:info, "Agreement updated")}

      {:error, error} ->
        {:noreply, put_flash(socket, :error, "Could not update agreement: #{inspect(error)}")}
    end
  end

  @impl true
  def handle_event("generate_invoice", _params, socket) do
    actor = socket.assigns.current_user
    agreement = socket.assigns.agreement
    selected_ids = MapSet.to_list(socket.assigns.selected_expense_ids)

    result =
      case agreement.billing_model do
        :fixed_fee ->
          Finance.create_invoices_from_fixed_fee_schedule(agreement.id, selected_ids)

        _ ->
          case Finance.draft_invoice_from_agreement_sources(agreement.id,
                 expense_ids: selected_ids,
                 actor: actor
               ) do
            {:ok, invoice} -> {:ok, [invoice]}
            error -> error
          end
      end

    case result do
      {:ok, invoices} ->
        count = length(List.wrap(invoices))

        {:noreply,
         socket
         |> put_flash(:info, "#{count} invoice(s) created")
         |> assign(:selected_expense_ids, MapSet.new())
         |> reload_unbilled_expenses()}

      {:error, %Ash.Error.Invalid{errors: errors}} ->
        if Enum.any?(errors, fn
             %{message: msg} when is_binary(msg) -> msg =~ "approved billable source records"
             _ -> false
           end) do
          {:noreply,
           put_flash(socket, :info, "No approved billable entries for this agreement yet.")}
        else
          {:noreply,
           put_flash(socket, :error, "Could not generate invoice: #{inspect(errors)}")}
        end

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Could not generate invoice: #{inspect(reason)}")}
    end
  end

  @impl true
  def handle_event("toggle_expense", %{"id" => id}, socket) do
    ids = socket.assigns.selected_expense_ids

    updated =
      if MapSet.member?(ids, id),
        do: MapSet.delete(ids, id),
        else: MapSet.put(ids, id)

    {:noreply, assign(socket, :selected_expense_ids, updated)}
  end

  @impl true
  def handle_event("add_schedule_item", %{"label" => label, "percentage" => pct, "due_days" => days}, socket) do
    agreement = socket.assigns.agreement
    next_position = length(agreement.payment_schedule_items) + 1

    attrs = %{
      agreement_id: agreement.id,
      position: next_position,
      label: label,
      percentage: Decimal.new(pct),
      due_days: String.to_integer(days)
    }

    case Finance.create_payment_schedule_item(attrs) do
      {:ok, _item} ->
        refreshed = reload_agreement(socket)
        {:noreply,
         socket
         |> assign(:agreement, refreshed)
         |> assign(:schedule_pct_total, compute_pct_total(refreshed.payment_schedule_items))
         |> put_flash(:info, "Item added")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Could not add item: #{inspect(reason)}")}
    end
  end

  @impl true
  def handle_event("delete_schedule_item", %{"id" => id}, socket) do
    case Finance.get_payment_schedule_item(id) do
      {:ok, item} ->
        Finance.delete_payment_schedule_item(item)
        refreshed = reload_agreement(socket)
        {:noreply,
         socket
         |> assign(:agreement, refreshed)
         |> assign(:schedule_pct_total, compute_pct_total(refreshed.payment_schedule_items))
         |> put_flash(:info, "Item removed")}

      _ ->
        {:noreply, put_flash(socket, :error, "Item not found")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.page class="pb-8">
      <.page_header eyebrow="Commercial">
        {@agreement.name}
        <:subtitle>
          <span class="inline-flex items-center gap-2">
            <.status_badge status={@agreement.status_variant}>
              {format_atom(@agreement.status)}
            </.status_badge>
            <span class="text-base-content/40">/</span>
            <span>{@agreement.reference_number || "No reference number"}</span>
          </span>
        </:subtitle>
        <:actions>
          <.button navigate={~p"/commercial/agreements"}>
            Back
          </.button>
          <.button navigate={~p"/commercial/change-orders/new?agreement_id=#{@agreement.id}"}>
            New Change Order
          </.button>
          <.button navigate={~p"/finance/invoices/new?agreement_id=#{@agreement.id}"}>
            Invoice Time &amp; Expenses
          </.button>
          <.button
            :if={@agreement.status == :active}
            phx-click="generate_invoice"
            phx-disable-with="Generating..."
            variant="primary"
          >
            <.icon name="hero-document-plus" class="size-4" /> Invoice Milestone
          </.button>
          <.button
            :if={can_create_project?(@agreement)}
            navigate={~p"/execution/projects/new?agreement_id=#{@agreement.id}"}
            variant="primary"
          >
            Create Project
          </.button>
          <.button navigate={~p"/commercial/agreements/#{@agreement}/edit"}>
            Edit
          </.button>
        </:actions>
      </.page_header>

      <.section
        title="Agreement Actions"
        description="Use explicit transitions so delivery and finance automation can trust the agreement lifecycle."
      >
        <div class="flex flex-wrap gap-3">
          <.button
            :for={action <- agreement_actions(@agreement)}
            phx-click="transition"
            phx-value-action={action.action}
            variant={action.variant}
          >
            <.icon name={action.icon} class="size-4" /> {action.label}
          </.button>
        </div>
      </.section>

      <div class="grid gap-6 lg:grid-cols-2">
        <.section title="Commercial Snapshot">
          <div class="grid gap-5 sm:grid-cols-2">
            <.property_item label="Agreement Type" value={format_atom(@agreement.agreement_type)} />
            <.property_item label="Billing Model" value={format_atom(@agreement.billing_model)} />
            <.property_item label="Contract Value" value={format_amount(@agreement.contract_value)} />
            <.property_item label="Start On" value={format_date(@agreement.start_on)} />
            <.property_item label="End On" value={format_date(@agreement.end_on)} />
            <.property_item
              label="Auto Renew"
              value={if(@agreement.auto_renew, do: "Yes", else: "No")}
            />
          </div>
        </.section>

        <.section title="Operational Context">
          <div class="grid gap-5 sm:grid-cols-2">
            <.property_item
              label="Organization"
              value={(@agreement.organization && @agreement.organization.name) || "-"}
            />
            <.property_item
              label="Proposal"
              value={(@agreement.proposal && @agreement.proposal.name) || "-"}
            />
            <.property_item
              label="Pursuit"
              value={(@agreement.pursuit && @agreement.pursuit.name) || "-"}
            />
            <.property_item label="Projects" value={Integer.to_string(@agreement.project_count || 0)} />
            <.property_item label="Invoices" value={Integer.to_string(@agreement.invoice_count || 0)} />
            <.property_item label="Payments" value={Integer.to_string(@agreement.payment_count || 0)} />
          </div>
        </.section>
      </div>

      <.section title="Finance Snapshot">
        <div class="grid gap-5 sm:grid-cols-3">
          <.property_item label="Invoiced" value={format_amount(@agreement.invoiced_amount)} />
          <.property_item label="Received" value={format_amount(@agreement.received_amount)} />
          <.property_item
            label="Open Work Orders"
            value={Integer.to_string(@agreement.open_work_order_count || 0)}
          />
        </div>
      </.section>

      <.section :if={@agreement.notes} title="Notes">
        <p class="whitespace-pre-wrap text-sm leading-6 text-base-content/70">
          {@agreement.notes}
        </p>
      </.section>

      <.section
        :if={@agreement.billing_model == :fixed_fee}
        title="Payment Schedule"
        description="Define installments as percentages of the contract value. Total must equal 100% before generating invoices."
      >
        <p class={[
          "text-sm font-medium mb-3",
          if(Decimal.equal?(@schedule_pct_total, Decimal.new("100")),
            do: "text-emerald-600",
            else: "text-amber-600"
          )
        ]}>
          Total: <%= @schedule_pct_total %>%
          <%= if not Decimal.equal?(@schedule_pct_total, Decimal.new("100")) do %>
            (must equal 100% before generating invoices)
          <% end %>
        </p>

        <table :if={length(@agreement.payment_schedule_items) > 0} class="min-w-full text-sm mb-4">
          <thead>
            <tr class="text-left text-zinc-500">
              <th class="pr-4 pb-2 font-medium">#</th>
              <th class="pr-4 pb-2 font-medium">Label</th>
              <th class="pr-4 pb-2 font-medium">%</th>
              <th class="pr-4 pb-2 font-medium">Due (days after issue)</th>
              <th class="pb-2"></th>
            </tr>
          </thead>
          <tbody>
            <tr :for={item <- @agreement.payment_schedule_items} class="border-t border-zinc-100">
              <td class="pr-4 py-2 text-zinc-500">{item.position}</td>
              <td class="pr-4 py-2">{item.label}</td>
              <td class="pr-4 py-2">{item.percentage}%</td>
              <td class="pr-4 py-2">{item.due_days} days</td>
              <td class="py-2">
                <button
                  phx-click="delete_schedule_item"
                  phx-value-id={item.id}
                  class="text-red-500 hover:text-red-700 text-xs"
                  data-confirm="Remove this installment?"
                >
                  Remove
                </button>
              </td>
            </tr>
          </tbody>
        </table>

        <form phx-submit="add_schedule_item" class="flex gap-3 items-end flex-wrap">
          <div>
            <label class="block text-xs text-zinc-500 mb-1">Label</label>
            <input type="text" name="label" placeholder="e.g. Deposit"
              class="border border-zinc-300 rounded px-2 py-1 text-sm w-32" required />
          </div>
          <div>
            <label class="block text-xs text-zinc-500 mb-1">Percentage</label>
            <input type="number" name="percentage" placeholder="25" min="1" max="100" step="0.01"
              class="border border-zinc-300 rounded px-2 py-1 text-sm w-24" required />
          </div>
          <div>
            <label class="block text-xs text-zinc-500 mb-1">Due (days)</label>
            <input type="number" name="due_days" value="30" min="0"
              class="border border-zinc-300 rounded px-2 py-1 text-sm w-20" required />
          </div>
          <button type="submit"
            class="bg-emerald-600 text-white text-sm px-3 py-1.5 rounded hover:bg-emerald-700">
            Add Item
          </button>
        </form>
      </.section>

      <.section
        title="Downstream Projects"
        description="Projects should be created from active agreements instead of bypassing the contract layer."
      >
        <div :if={Enum.empty?(@agreement.projects || [])}>
          <.empty_state
            icon="hero-wrench-screwdriver"
            title="No projects yet"
            description="Activate the agreement, then create the project that will deliver against it."
          />
        </div>

        <div :if={!Enum.empty?(@agreement.projects || [])} class="space-y-3">
          <.link
            :for={project <- @agreement.projects}
            navigate={~p"/execution/projects/#{project}"}
            class="flex items-center justify-between rounded-2xl border border-zinc-200 bg-zinc-50/70 px-4 py-4 transition hover:border-emerald-300 hover:bg-white dark:border-white/10 dark:bg-white/[0.03] dark:hover:border-emerald-400/40"
          >
            <div class="space-y-1">
              <p class="font-medium text-base-content">{project.name}</p>
              <p class="text-sm text-base-content/50">
                {project.code || "No project code"}
              </p>
            </div>
            <.status_badge status={project.status_variant}>
              {format_atom(project.status)}
            </.status_badge>
          </.link>
        </div>
      </.section>

      <.section
        title="Change Orders"
        description="Scope, price, or schedule changes should stay explicit and attached to the agreement they amend."
      >
        <div :if={Enum.empty?(@agreement.change_orders || [])}>
          <.empty_state
            icon="hero-arrow-path"
            title="No change orders yet"
            description="Create change orders here when awarded scope shifts after the original commercial commitment."
          >
            <:action>
              <.button navigate={~p"/commercial/change-orders/new?agreement_id=#{@agreement.id}"}>
                Create Change Order
              </.button>
            </:action>
          </.empty_state>
        </div>

        <div :if={!Enum.empty?(@agreement.change_orders || [])} class="space-y-3">
          <.link
            :for={change_order <- @agreement.change_orders}
            navigate={~p"/commercial/change-orders/#{change_order}"}
            class="flex items-center justify-between rounded-2xl border border-zinc-200 bg-zinc-50/70 px-4 py-4 transition hover:border-emerald-300 hover:bg-white dark:border-white/10 dark:bg-white/[0.03] dark:hover:border-emerald-400/40"
          >
            <div class="space-y-1">
              <p class="font-medium text-base-content">{change_order.title}</p>
              <p class="text-sm text-base-content/50">
                {change_order.change_order_number}
              </p>
            </div>
            <.status_badge status={change_order.status_variant}>
              {format_atom(change_order.status)}
            </.status_badge>
          </.link>
        </div>
      </.section>

      <.section
        title="Invoices"
        description="Operational invoices should remain visible at the agreement layer so billing stays tied to the commercial source."
      >
        <div :if={Enum.empty?(@agreement.invoices || [])}>
          <.empty_state
            icon="hero-receipt-percent"
            title="No invoices yet"
            description="Draft invoices from this agreement when approved billable work is ready to move into receivables."
          >
            <:action>
              <.button navigate={~p"/finance/invoices/new?agreement_id=#{@agreement.id}"}>
                Invoice Time &amp; Expenses
              </.button>
            </:action>
          </.empty_state>
        </div>

        <div :if={!Enum.empty?(@agreement.invoices || [])} class="space-y-3">
          <.link
            :for={invoice <- @agreement.invoices}
            navigate={~p"/finance/invoices/#{invoice}"}
            class="flex items-center justify-between rounded-2xl border border-zinc-200 bg-zinc-50/70 px-4 py-4 transition hover:border-emerald-300 hover:bg-white dark:border-white/10 dark:bg-white/[0.03] dark:hover:border-emerald-400/40"
          >
            <div class="space-y-1">
              <p class="font-medium text-base-content">
                {invoice.invoice_number || "Draft Invoice"}
              </p>
              <p class="text-sm text-base-content/50">
                Due {format_date(invoice.due_on)}
              </p>
            </div>
            <.status_badge status={invoice.status_variant}>
              {format_atom(invoice.status)}
            </.status_badge>
          </.link>
        </div>
      </.section>

      <.section :if={not Enum.empty?(@unbilled_expenses)} title="Unbilled Expenses">
        <table class="min-w-full divide-y divide-zinc-200 text-sm">
          <thead class="bg-zinc-50">
            <tr>
              <th class="px-5 py-3"></th>
              <th class="px-5 py-3 text-left font-medium text-zinc-500">Date</th>
              <th class="px-5 py-3 text-left font-medium text-zinc-500">Category</th>
              <th class="px-5 py-3 text-left font-medium text-zinc-500">Description</th>
              <th class="px-5 py-3 text-left font-medium text-zinc-500">Vendor</th>
              <th class="px-5 py-3 text-right font-medium text-zinc-500">Amount</th>
            </tr>
          </thead>
          <tbody class="divide-y divide-zinc-200">
            <tr :for={exp <- @unbilled_expenses}>
              <td class="px-5 py-3">
                <input
                  type="checkbox"
                  phx-click="toggle_expense"
                  phx-value-id={exp.id}
                  checked={MapSet.member?(@selected_expense_ids, to_string(exp.id))}
                />
              </td>
              <td class="px-5 py-3">{exp.incurred_on}</td>
              <td class="px-5 py-3">{format_atom(exp.category)}</td>
              <td class="px-5 py-3">{exp.description}</td>
              <td class="px-5 py-3 text-zinc-500">{exp.vendor || "—"}</td>
              <td class="px-5 py-3 text-right font-medium">{format_amount(exp.amount)}</td>
            </tr>
          </tbody>
        </table>
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

  defp load_agreement!(id, actor) do
    case Commercial.get_agreement(
           id,
           actor: actor,
           load: [
             :status_variant,
             :project_count,
             :invoice_count,
             :payment_count,
             :open_work_order_count,
             :invoiced_amount,
             :received_amount,
             :payment_schedule_items,
             organization: [],
             proposal: [],
             pursuit: [],
             projects: [:status_variant],
             change_orders: [:status_variant],
             invoices: [:status_variant]
           ]
         ) do
      {:ok, agreement} -> agreement
      {:error, error} -> raise "failed to load agreement #{id}: #{inspect(error)}"
    end
  end

  defp reload_agreement(socket) do
    agreement = socket.assigns.agreement
    load_agreement!(agreement.id, socket.assigns.current_user)
  end

  defp compute_pct_total(items) do
    Enum.reduce(items, Decimal.new("0"), fn item, acc ->
      Decimal.add(acc, item.percentage)
    end)
  end

  defp can_create_project?(agreement), do: agreement.status == :active

  defp agreement_actions(%{status: :draft}) do
    [
      %{
        action: "submit_for_signature",
        label: "Submit For Signature",
        icon: "hero-pencil-square",
        variant: nil
      },
      %{action: "activate", label: "Activate", icon: "hero-check-badge", variant: "primary"},
      %{action: "terminate", label: "Terminate", icon: "hero-x-circle", variant: nil}
    ]
  end

  defp agreement_actions(%{status: :pending_signature}) do
    [
      %{action: "activate", label: "Activate", icon: "hero-check-badge", variant: "primary"},
      %{action: "terminate", label: "Terminate", icon: "hero-x-circle", variant: nil}
    ]
  end

  defp agreement_actions(%{status: :active}) do
    [
      %{action: "suspend", label: "Suspend", icon: "hero-pause", variant: nil},
      %{action: "complete", label: "Complete", icon: "hero-check", variant: "primary"},
      %{action: "terminate", label: "Terminate", icon: "hero-x-circle", variant: nil}
    ]
  end

  defp agreement_actions(%{status: :suspended}) do
    [
      %{action: "reopen", label: "Reopen", icon: "hero-arrow-path", variant: "primary"},
      %{action: "complete", label: "Complete", icon: "hero-check", variant: nil},
      %{action: "terminate", label: "Terminate", icon: "hero-x-circle", variant: nil}
    ]
  end

  defp agreement_actions(%{status: :terminated}) do
    [
      %{action: "reopen", label: "Reopen", icon: "hero-arrow-path", variant: "primary"}
    ]
  end

  defp agreement_actions(_agreement), do: []

  defp transition_agreement(agreement, :submit_for_signature, actor),
    do: Commercial.submit_agreement(agreement, actor: actor)

  defp transition_agreement(agreement, :activate, actor),
    do: Commercial.activate_agreement(agreement, actor: actor)

  defp transition_agreement(agreement, :suspend, actor),
    do: Commercial.suspend_agreement(agreement, actor: actor)

  defp transition_agreement(agreement, :complete, actor),
    do: Commercial.complete_agreement(agreement, actor: actor)

  defp transition_agreement(agreement, :terminate, actor),
    do: Commercial.terminate_agreement(agreement, actor: actor)

  defp transition_agreement(agreement, :reopen, actor),
    do: Commercial.reopen_agreement(agreement, actor: actor)

  defp reload_unbilled_expenses(socket) do
    agreement = socket.assigns.agreement
    actor = socket.assigns.current_user

    unbilled_expenses =
      case Finance.list_billable_expenses_for_agreement(agreement.id,
             actor: actor, authorize?: false) do
        {:ok, exps} -> exps
        _ -> []
      end

    assign(socket, :unbilled_expenses, unbilled_expenses)
  end
end
