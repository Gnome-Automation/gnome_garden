defmodule GnomeGardenWeb.Finance.InvoiceLive.Show do
  use GnomeGardenWeb, :live_view

  import GnomeGardenWeb.Finance.Helpers

  require Logger

  alias GnomeGarden.Finance
  alias GnomeGarden.Mailer
  alias GnomeGarden.Mailer.InvoiceEmail

  @impl true
  def mount(%{"id" => id} = params, _session, socket) do
    invoice = load_invoice!(id, socket.assigns.current_user)

    {:ok,
     socket
     |> assign(:page_title, invoice.invoice_number || "Invoice")
     |> assign(:invoice, invoice)
     |> assign(:return_to, params["return_to"] || ~p"/finance/invoices")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.page class="pb-8">
      <.page_header eyebrow="Finance">
        {@invoice.invoice_number || "Draft Invoice"}
        <:subtitle>
          <span class="inline-flex items-center gap-2">
            <.status_badge status={@invoice.status_variant}>
              {format_atom(@invoice.status)}
            </.status_badge>
            <span class="text-base-content/40">/</span>
            <span>
              {(@invoice.organization && @invoice.organization.name) || "No organization linked"}
            </span>
          </span>
        </:subtitle>
        <:actions>
          <.button navigate={@return_to}>
            Back
          </.button>
          <.button
            :if={@invoice.status in [:issued, :partial, :paid]}
            phx-click="resend"
            title="Re-send the invoice email to the billing contact"
          >
            <.icon name="hero-paper-airplane" class="size-4" /> Resend
          </.button>
          <span :if={@invoice.status in [:issued, :partial, :paid]}>
            <a
              href={~p"/finance/invoices/#{@invoice}/export?format=csv"}
              title="Download a CSV spreadsheet of this invoice"
              class="inline-flex items-center gap-2 rounded-lg border border-zinc-300 bg-white px-3 py-2 text-sm font-semibold text-zinc-900 hover:bg-zinc-50 dark:border-white/10 dark:bg-white/5 dark:text-white dark:hover:bg-white/10"
            >
              <.icon name="hero-arrow-down-tray" class="size-4" /> Export CSV
            </a>
          </span>
          <span :if={@invoice.status in [:issued, :partial, :paid]}>
            <a
              href={~p"/finance/invoices/#{@invoice}/export?format=pdf"}
              target="_blank"
              title="Download a print-ready PDF of this invoice"
              class="inline-flex items-center gap-2 rounded-lg border border-zinc-300 bg-white px-3 py-2 text-sm font-semibold text-zinc-900 hover:bg-zinc-50 dark:border-white/10 dark:bg-white/5 dark:text-white dark:hover:bg-white/10"
            >
              <.icon name="hero-arrow-down-tray" class="size-4" /> Export PDF
            </a>
          </span>
          <.button navigate={~p"/finance/payment-applications/new?invoice_id=#{@invoice.id}"} title="Record a payment received against this invoice">
            Apply Payment
          </.button>
          <.button navigate={~p"/finance/invoices/#{@invoice}/edit"}>
            Edit
          </.button>
        </:actions>
      </.page_header>

      <.section
        title="Invoice Status"
        description={invoice_status_description(@invoice)}
      >
        <div class="flex flex-wrap gap-3">
          <.button
            :if={@invoice.status == :draft}
            navigate={~p"/finance/invoices/#{@invoice}/review"}
            variant="primary"
            title="Review line items, set a due date, and send the invoice to the client"
          >
            <.icon name="hero-paper-airplane" class="size-4" /> Review & Issue
          </.button>
          <.button
            :for={action <- invoice_actions(@invoice)}
            phx-click="transition"
            phx-value-action={action.action}
            variant={action.variant}
            title={action.title}
          >
            <.icon name={action.icon} class="size-4" /> {action.label}
          </.button>
        </div>
      </.section>

      <div class="grid gap-6 lg:grid-cols-2">
        <.section title="Invoice Snapshot">
          <div class="grid gap-5 sm:grid-cols-2">
            <.property_item label="Currency" value={@invoice.currency_code || "-"} />
            <.property_item label="Issued On" value={format_date(@invoice.issued_on)} />
            <.property_item label="Due On" value={format_date(@invoice.due_on)} />
            <.property_item label="Paid On" value={format_date(@invoice.paid_on)} />
            <.property_item label="Subtotal" value={format_amount(@invoice.subtotal)} />
            <.property_item label="Tax" value={format_amount(@invoice.tax_total)} />
          </div>
        </.section>

        <.section title="Operational Context">
          <div class="grid gap-5 sm:grid-cols-2">
            <.property_item
              label="Agreement"
              value={(@invoice.agreement && @invoice.agreement.name) || "-"}
            />
            <.property_item
              label="Project"
              value={(@invoice.project && @invoice.project.name) || "-"}
            />
            <.property_item
              label="Work Order"
              value={(@invoice.work_order && @invoice.work_order.title) || "-"}
            />
            <.property_item label="Lines" value={Integer.to_string(@invoice.line_count || 0)} />
            <.property_item
              label="Payment Applications"
              value={Integer.to_string(@invoice.payment_application_count || 0)}
            />
            <.property_item label="Applied" value={format_amount(@invoice.applied_amount)} />
          </div>
        </.section>
      </div>

      <.section title="Amounts">
        <div class="grid gap-5 sm:grid-cols-3">
          <.property_item label="Total" value={format_amount(@invoice.total_amount)} />
          <.property_item label="Balance" value={format_amount(@invoice.balance_amount)} />
          <.property_item label="Line Total" value={format_amount(@invoice.line_total_amount)} />
        </div>
      </.section>

      <.section :if={@invoice.notes} title="Notes">
        <p class="whitespace-pre-wrap text-sm leading-6 text-base-content/70">
          {@invoice.notes}
        </p>
      </.section>

      <.section
        title="Invoice Lines"
        description="Trace every invoice back to the operational source rows that generated it."
      >
        <div :if={Enum.empty?(@invoice.invoice_lines || [])}>
          <.empty_state
            icon="hero-list-bullet"
            title="No invoice lines yet"
            description="Draft invoices from agreement sources, or add manual invoice lines as needed."
          />
        </div>

        <div :if={!Enum.empty?(@invoice.invoice_lines || [])} class="space-y-3">
          <div
            :for={line <- @invoice.invoice_lines}
            class="flex items-start justify-between rounded-2xl border border-zinc-200 bg-zinc-50/70 px-4 py-4 dark:border-white/10 dark:bg-white/[0.03]"
          >
            <div class="space-y-1">
              <p class="font-medium text-base-content">
                {line.line_number}. {line.description}
              </p>
              <p class="text-sm text-base-content/50">
                {format_atom(line.line_kind)} · Qty {Decimal.to_string(line.quantity)}
              </p>
            </div>
            <div class="text-right text-sm text-base-content/70">
              <p>{format_amount(line.line_total)}</p>
              <p class="text-xs text-base-content/40">
                {format_amount(line.unit_price)} each
              </p>
            </div>
          </div>
        </div>
      </.section>

      <.section
        title="Payment Applications"
        description="Applications show how received money has been allocated against this invoice."
      >
        <div :if={Enum.empty?(@invoice.payment_applications || [])}>
          <.empty_state
            icon="hero-link"
            title="No payment applications yet"
            description="Create payment applications when receipts are allocated against this invoice."
          >
            <:action>
              <.button navigate={~p"/finance/payment-applications/new?invoice_id=#{@invoice.id}"}>
                Create Payment Application
              </.button>
            </:action>
          </.empty_state>
        </div>

        <div :if={!Enum.empty?(@invoice.payment_applications || [])} class="space-y-3">
          <.link
            :for={application <- @invoice.payment_applications}
            navigate={~p"/finance/payment-applications/#{application}?return_to=#{~p"/finance/invoices/#{@invoice}"}"}
            class="flex items-center justify-between rounded-2xl border border-zinc-200 bg-zinc-50/70 px-4 py-4 transition hover:border-emerald-300 hover:bg-white dark:border-white/10 dark:bg-white/[0.03] dark:hover:border-emerald-400/40"
          >
            <div class="space-y-1">
              <p class="font-medium text-base-content">
                {(application.payment && application.payment.payment_number) || "Payment"}
              </p>
              <p class="text-sm text-base-content/50">
                Applied {format_date(application.applied_on)}
              </p>
            </div>
            <p class="text-sm font-medium text-base-content">
              {format_amount(application.amount)}
            </p>
          </.link>
        </div>
      </.section>

      <%!-- Credit Note card — only shown for void invoices --%>
      <.section :if={@invoice.status == :void} title="Credit Note">
        <div class="px-5 py-4">
          <%= if @invoice.credit_note do %>
            <p class="text-sm text-zinc-600 mb-3">
              Credit note <strong>{@invoice.credit_note.credit_note_number}</strong>
              has been created
              (<.status_badge status={@invoice.credit_note.status_variant}>
                {format_atom(@invoice.credit_note.status)}
              </.status_badge>).
            </p>
            <.button navigate={~p"/finance/credit-notes/#{@invoice.credit_note.id}"}>
              View Credit Note
            </.button>
          <% else %>
            <p class="text-sm text-zinc-400 italic mb-3">
              No credit note has been created yet. Create one to give the client a reconcilable document.
            </p>
            <.button phx-click="create_credit_note" variant="primary" title="Generate a credit note to offset or cancel this invoice — used when issuing a refund or correcting a billing error">
              Create Credit Note
            </.button>
          <% end %>
        </div>
      </.section>
    </.page>
    """
  end

  @impl true
  def handle_event("resend", _params, socket) do
    actor = socket.assigns.current_user
    invoice = socket.assigns.invoice

    case Finance.get_invoice(invoice.id, actor: actor, load: [:invoice_lines, :organization]) do
      {:ok, loaded} ->
        mercury_info = Application.get_env(:gnome_garden, :mercury_payment_info, [])

        case loaded |> InvoiceEmail.build(mercury_info) |> Mailer.deliver() do
          {:ok, _} ->
            {:noreply, put_flash(socket, :info, "Invoice resent to #{InvoiceEmail.find_billing_email(loaded.organization || %{}) || "billing@gnomeautomation.io"}")}

          {:error, reason} ->
            Logger.warning("Invoice resend failed", reason: inspect(reason))
            {:noreply, put_flash(socket, :error, "Email delivery failed — please try again.")}
        end

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not load invoice for resend.")}
    end
  end

  def handle_event("transition", %{"action" => action}, socket) do
    invoice = socket.assigns.invoice

    case transition_invoice(invoice, String.to_existing_atom(action), socket.assigns.current_user) do
      {:ok, updated_invoice} ->
        {:noreply,
         socket
         |> assign(:invoice, load_invoice!(updated_invoice.id, socket.assigns.current_user))
         |> put_flash(:info, "Invoice updated")}

      {:error, error} ->
        {:noreply, put_flash(socket, :error, "Could not update invoice: #{inspect(error)}")}
    end
  end

  @impl true
  def handle_event("create_credit_note", _params, socket) do
    invoice = socket.assigns.invoice
    actor = socket.assigns.current_user

    n = Finance.next_sequence_value("credit_notes")
    cn_number = Finance.format_credit_note_number(n)

    with {:ok, credit_note} <-
           Finance.create_credit_note(
             %{
               credit_note_number: cn_number,
               invoice_id: invoice.id,
               organization_id: invoice.organization_id,
               total_amount: Decimal.negate(invoice.total_amount || Decimal.new("0")),
               currency_code: invoice.currency_code || "USD"
             },
             actor: actor
           ),
         {:ok, _} <- create_credit_note_lines(credit_note, invoice.invoice_lines, actor) do
      {:noreply,
       socket
       |> push_navigate(to: ~p"/finance/credit-notes/#{credit_note.id}")}
    else
      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Could not create credit note: #{inspect(reason)}")}
    end
  end

  defp create_credit_note_lines(credit_note, invoice_lines, actor) do
    invoice_lines
    |> Enum.with_index(1)
    |> Enum.reduce_while({:ok, []}, fn {line, position}, {:ok, acc} ->
      attrs = %{
        credit_note_id: credit_note.id,
        position: position,
        description: line.description || "",
        quantity: line.quantity,
        unit_price: line.unit_price && Decimal.negate(line.unit_price),
        line_total: Decimal.negate(line.line_total || Decimal.new("0"))
      }

      case Finance.create_credit_note_line(attrs, actor: actor) do
        {:ok, cn_line} -> {:cont, {:ok, [cn_line | acc]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
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

  defp load_invoice!(id, actor) do
    case Finance.get_invoice(
           id,
           actor: actor,
           load: [
             :status_variant,
             :line_count,
             :payment_application_count,
             :line_total_amount,
             :applied_amount,
             credit_note: [:status_variant],
             organization: [],
             agreement: [],
             project: [],
             work_order: [],
             invoice_lines: [],
             payment_applications: [payment: []]
           ]
         ) do
      {:ok, invoice} -> invoice
      {:error, error} -> raise "failed to load invoice #{id}: #{inspect(error)}"
    end
  end

  defp invoice_actions(%{status: :draft}) do
    [
      %{action: "void", label: "Void", icon: "hero-x-circle", variant: nil, title: "Cancel this invoice — it will be removed from receivables"}
    ]
  end

  defp invoice_actions(%{status: :issued}) do
    [
      %{action: "mark_paid", label: "Mark Paid", icon: "hero-check-badge", variant: "primary", title: "Manually mark this invoice as paid without recording a specific payment"},
      %{action: "void", label: "Void", icon: "hero-x-circle", variant: nil, title: "Cancel this invoice — a credit note will be generated automatically"}
    ]
  end

  defp invoice_actions(%{status: :paid}) do
    [
      %{action: "reopen", label: "Reopen", icon: "hero-arrow-path", variant: "primary", title: "Move this invoice back to draft so it can be re-issued"}
    ]
  end

  defp invoice_actions(%{status: :void}) do
    [
      %{action: "reopen", label: "Reopen", icon: "hero-arrow-path", variant: "primary", title: "Move this invoice back to draft so it can be re-issued"}
    ]
  end

  defp invoice_actions(_invoice), do: []

  defp invoice_status_description(%{status: :draft}),
    do: "Draft — review the line items, then issue it to send to the customer."

  defp invoice_status_description(%{status: :issued}),
    do: "Issued — the invoice has been sent. Mark it paid once payment is received, or void it if it was sent in error."

  defp invoice_status_description(%{status: :paid}),
    do: "Paid — payment received. No further action needed."

  defp invoice_status_description(%{status: :void}),
    do: "Void — this invoice was cancelled. It will not appear in receivables."

  defp invoice_status_description(_), do: "Manage this invoice's billing status below."

  defp transition_invoice(invoice, :issue, actor),
    do: Finance.issue_invoice(invoice, actor: actor)

  defp transition_invoice(invoice, :mark_paid, actor),
    do: Finance.pay_invoice(invoice, actor: actor)

  defp transition_invoice(invoice, :void, actor),
    do: Finance.void_invoice(invoice, actor: actor)

  defp transition_invoice(invoice, :reopen, actor),
    do: Finance.reopen_invoice(invoice, actor: actor)
end
