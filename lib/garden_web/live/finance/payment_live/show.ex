defmodule GnomeGardenWeb.Finance.PaymentLive.Show do
  use GnomeGardenWeb, :live_view

  import GnomeGardenWeb.Finance.Helpers

  alias GnomeGarden.Finance

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    payment = load_payment!(id, socket.assigns.current_user)

    {:ok,
     socket
     |> assign(:page_title, payment.payment_number || "Payment")
     |> assign(:payment, payment)}
  end

  @impl true
  def handle_event("transition", %{"action" => action}, socket) do
    payment = socket.assigns.payment

    case transition_payment(payment, String.to_existing_atom(action), socket.assigns.current_user) do
      {:ok, updated_payment} ->
        {:noreply,
         socket
         |> assign(:payment, load_payment!(updated_payment.id, socket.assigns.current_user))
         |> put_flash(:info, "Payment updated")}

      {:error, error} ->
        {:noreply, put_flash(socket, :error, "Could not update payment: #{inspect(error)}")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.page class="pb-8">
      <.page_header eyebrow="Finance">
        {@payment.payment_number || "Payment"}
        <:subtitle>
          <span class="inline-flex items-center gap-2">
            <.status_badge status={@payment.status_variant}>
              {format_atom(@payment.status)}
            </.status_badge>
            <span class="text-zinc-400 dark:text-zinc-500">/</span>
            <span>
              {(@payment.organization && @payment.organization.name) || "No organization linked"}
            </span>
          </span>
        </:subtitle>
        <:actions>
          <.button navigate={~p"/finance/payments"}>
            <.icon name="hero-arrow-left" class="size-4" /> Back
          </.button>
          <.button navigate={~p"/finance/payment-applications/new?payment_id=#{@payment.id}"}>
            <.icon name="hero-link" class="size-4" /> Apply to Invoice
          </.button>
          <.button navigate={~p"/finance/payments/#{@payment}/edit"}>
            <.icon name="hero-pencil-square" class="size-4" /> Edit
          </.button>
        </:actions>
      </.page_header>

      <.section
        title="Payment Actions"
        description="Advance receipts explicitly so cash application history stays grounded in real events."
      >
        <div class="flex flex-wrap gap-3">
          <.button
            :for={action <- payment_actions(@payment)}
            phx-click="transition"
            phx-value-action={action.action}
            variant={action.variant}
          >
            <.icon name={action.icon} class="size-4" /> {action.label}
          </.button>
        </div>
      </.section>

      <div class="grid gap-6 lg:grid-cols-2">
        <.section title="Payment Snapshot">
          <div class="grid gap-5 sm:grid-cols-2">
            <.property_item label="Method" value={format_atom(@payment.payment_method)} />
            <.property_item label="Currency" value={@payment.currency_code || "-"} />
            <.property_item label="Received On" value={format_date(@payment.received_on)} />
            <.property_item label="Deposited On" value={format_date(@payment.deposited_on)} />
            <.property_item label="Reversed On" value={format_date(@payment.reversed_on)} />
            <.property_item label="Reference" value={@payment.reference || "-"} />
            <.property_item label="Amount" value={format_amount(@payment.amount)} />
            <.property_item label="Applied Amount" value={format_amount(@payment.applied_amount)} />
          </div>
        </.section>

        <.section title="Commercial Context">
          <div class="grid gap-5 sm:grid-cols-2">
            <.property_item
              label="Organization"
              value={(@payment.organization && @payment.organization.name) || "-"}
            />
            <.property_item
              label="Agreement"
              value={(@payment.agreement && @payment.agreement.name) || "-"}
            />
            <.property_item
              label="Applications"
              value={Integer.to_string(@payment.application_count || 0)}
            />
          </div>
        </.section>
      </div>

      <.section :if={@payment.notes} title="Notes">
        <p class="whitespace-pre-wrap text-sm leading-6 text-zinc-600 dark:text-zinc-300">
          {@payment.notes}
        </p>
      </.section>

      <.section
        title="Payment Applications"
        description="Applications show exactly which invoices this receipt has been allocated against."
      >
        <div :if={Enum.empty?(@payment.applications || [])}>
          <.empty_state
            icon="hero-link"
            title="No applications yet"
            description="Create payment applications to allocate this receipt across one or more invoices."
          >
            <:action>
              <.button navigate={~p"/finance/payment-applications/new?payment_id=#{@payment.id}"}>
                Create Payment Application
              </.button>
            </:action>
          </.empty_state>
        </div>

        <div :if={!Enum.empty?(@payment.applications || [])} class="space-y-3">
          <.link
            :for={application <- @payment.applications}
            navigate={~p"/finance/payment-applications/#{application}"}
            class="flex items-center justify-between rounded-2xl border border-zinc-200 bg-zinc-50/70 px-4 py-4 transition hover:border-emerald-300 hover:bg-white dark:border-white/10 dark:bg-white/[0.03] dark:hover:border-emerald-400/40"
          >
            <div class="space-y-1">
              <p class="font-medium text-zinc-900 dark:text-white">
                {(application.invoice && application.invoice.invoice_number) || "Invoice"}
              </p>
              <p class="text-sm text-zinc-500 dark:text-zinc-400">
                Applied {format_date(application.applied_on)}
              </p>
            </div>
            <p class="text-sm font-medium text-zinc-900 dark:text-white">
              {format_amount(application.amount)}
            </p>
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
      <p class="text-xs font-semibold uppercase tracking-[0.2em] text-zinc-400 dark:text-zinc-500">
        {@label}
      </p>
      <p class="text-sm font-medium text-zinc-900 dark:text-white">{@value}</p>
    </div>
    """
  end

  defp load_payment!(id, actor) do
    case Finance.get_payment(
           id,
           actor: actor,
           load: [
             :status_variant,
             :application_count,
             :applied_amount,
             organization: [],
             agreement: [],
             applications: [invoice: []]
           ]
         ) do
      {:ok, payment} -> payment
      {:error, error} -> raise "failed to load payment #{id}: #{inspect(error)}"
    end
  end

  defp payment_actions(%{status: :received}) do
    [
      %{action: "deposit", label: "Deposit", icon: "hero-banknotes", variant: "primary"},
      %{action: "reverse", label: "Reverse", icon: "hero-arrow-uturn-left", variant: nil}
    ]
  end

  defp payment_actions(%{status: :deposited}) do
    [
      %{action: "reverse", label: "Reverse", icon: "hero-arrow-uturn-left", variant: nil}
    ]
  end

  defp payment_actions(_payment), do: []

  defp transition_payment(payment, :deposit, actor),
    do: Finance.deposit_payment(payment, actor: actor)

  defp transition_payment(payment, :reverse, actor),
    do: Finance.reverse_payment(payment, actor: actor)
end
