defmodule GnomeGardenWeb.Commercial.AgreementLive.Show do
  use GnomeGardenWeb, :live_view

  import GnomeGardenWeb.Commercial.Helpers

  alias GnomeGarden.Commercial

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    agreement = load_agreement!(id, socket.assigns.current_user)

    {:ok,
     socket
     |> assign(:page_title, agreement.name)
     |> assign(:agreement, agreement)}
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
            Draft Invoice
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
                Draft Invoice
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
end
