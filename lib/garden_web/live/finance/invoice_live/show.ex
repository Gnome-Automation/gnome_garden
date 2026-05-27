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
     |> assign(:show_line_form, false)
     |> assign(:line_form, empty_line_form())
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
              target="_blank"
              rel="external"
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
          <.button navigate={~p"/finance/payment-applications/new?invoice_id=#{@invoice.id}&return_to=#{~p"/finance/invoices/#{@invoice}"}"} title="Record a payment received against this invoice">
            Record Payment
          </.button>
          <.button navigate={~p"/finance/invoices/#{@invoice}/edit?return_to=#{~p"/finance/invoices/#{@invoice}"}"}>
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
          <.property_item
            label="Tax Rate"
            value={if @invoice.tax_rate && Decimal.positive?(@invoice.tax_rate), do: "#{Decimal.to_string(@invoice.tax_rate)}%", else: "None"}
          />
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
        <div :if={@show_line_form} class="mb-4 rounded-2xl border border-zinc-200 bg-zinc-50/70 p-4 dark:border-white/10 dark:bg-white/[0.03]">
          <form phx-submit="save_line" class="grid gap-4 sm:grid-cols-6">
            <div class="sm:col-span-3">
              <label class="block text-xs font-semibold uppercase tracking-[0.2em] text-base-content/40 mb-1">Description</label>
              <input
                type="text"
                name="line[description]"
                value={@line_form.description}
                required
                placeholder="Service description"
                class="w-full rounded-md bg-white px-3 py-1.5 text-base text-gray-900 outline-1 -outline-offset-1 outline-gray-300 placeholder:text-gray-400 focus:outline-2 focus:-outline-offset-2 focus:outline-emerald-600 sm:text-sm/6 dark:bg-white/5 dark:text-white dark:outline-white/10 dark:placeholder:text-gray-500 dark:focus:outline-emerald-500"
              />
            </div>
            <div class="sm:col-span-1">
              <label class="block text-xs font-semibold uppercase tracking-[0.2em] text-base-content/40 mb-1">Kind</label>
              <select
                name="line[line_kind]"
                class="w-full appearance-none rounded-md bg-white px-3 py-1.5 text-base text-gray-900 outline-1 -outline-offset-1 outline-gray-300 focus:outline-2 focus:-outline-offset-2 focus:outline-emerald-600 sm:text-sm/6 dark:bg-white/5 dark:text-white dark:outline-white/10 dark:focus:outline-emerald-500"
              >
                <option value="service">Service</option>
                <option value="labor">Labor</option>
                <option value="expense">Expense</option>
                <option value="material">Material</option>
                <option value="adjustment">Adjustment</option>
                <option value="other">Other</option>
              </select>
            </div>
            <div class="sm:col-span-1">
              <label class="block text-xs font-semibold uppercase tracking-[0.2em] text-base-content/40 mb-1">Qty</label>
              <input
                type="number"
                name="line[quantity]"
                value={@line_form.quantity}
                step="0.01"
                min="0.01"
                required
                class="w-full rounded-md bg-white px-3 py-1.5 text-base text-gray-900 outline-1 -outline-offset-1 outline-gray-300 placeholder:text-gray-400 focus:outline-2 focus:-outline-offset-2 focus:outline-emerald-600 sm:text-sm/6 dark:bg-white/5 dark:text-white dark:outline-white/10 dark:focus:outline-emerald-500"
              />
            </div>
            <div class="sm:col-span-1">
              <label class="block text-xs font-semibold uppercase tracking-[0.2em] text-base-content/40 mb-1">Unit Price</label>
              <input
                type="number"
                name="line[unit_price]"
                value={@line_form.unit_price}
                step="0.01"
                min="0"
                required
                class="w-full rounded-md bg-white px-3 py-1.5 text-base text-gray-900 outline-1 -outline-offset-1 outline-gray-300 placeholder:text-gray-400 focus:outline-2 focus:-outline-offset-2 focus:outline-emerald-600 sm:text-sm/6 dark:bg-white/5 dark:text-white dark:outline-white/10 dark:focus:outline-emerald-500"
              />
            </div>
            <div class="sm:col-span-6 flex justify-end gap-3">
              <.button type="button" phx-click="toggle_line_form">Cancel</.button>
              <.button type="submit" variant="primary">Add Line</.button>
            </div>
          </form>
        </div>

        <div :if={Enum.empty?(@invoice.invoice_lines || []) and not @show_line_form}>
          <.empty_state
            icon="hero-list-bullet"
            title="No invoice lines yet"
            description="Draft invoices from agreement sources, or add manual invoice lines as needed."
          >
            <:action :if={@invoice.status not in [:paid, :void]}>
              <.button phx-click="toggle_line_form">Add Line</.button>
            </:action>
          </.empty_state>
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
            <div class="flex items-start gap-4">
              <div class="text-right text-sm text-base-content/70">
                <p>{format_amount(line.line_total)}</p>
                <p class="text-xs text-base-content/40">
                  {format_amount(line.unit_price)} each
                </p>
              </div>
              <button
                :if={@invoice.status not in [:paid, :void]}
                phx-click="delete_line"
                phx-value-line_id={line.id}
                data-confirm="Remove this line?"
                class="text-base-content/30 hover:text-red-500 transition-colors"
                title="Remove line"
              >
                <.icon name="hero-x-mark" class="size-4" />
              </button>
            </div>
          </div>
          <div :if={@invoice.status not in [:paid, :void] and not @show_line_form} class="flex justify-center pt-2">
            <.button phx-click="toggle_line_form">+ Add Line</.button>
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
            description="Record a payment when you receive money against this invoice."
          >
            <:action>
              <.button navigate={~p"/finance/payment-applications/new?invoice_id=#{@invoice.id}&return_to=#{~p"/finance/invoices/#{@invoice}"}"}>
                Record Payment
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
  def handle_event("toggle_line_form", _params, socket) do
    {:noreply, assign(socket, show_line_form: !socket.assigns.show_line_form, line_form: empty_line_form())}
  end

  @impl true
  def handle_event("save_line", %{"line" => params}, socket) do
    invoice = socket.assigns.invoice
    actor = socket.assigns.current_user

    quantity = Decimal.new(params["quantity"] || "1")
    unit_price = Decimal.new(params["unit_price"] || "0")
    line_total = Decimal.mult(quantity, unit_price)
    next_number = length(invoice.invoice_lines || []) + 1

    attrs = %{
      invoice_id: invoice.id,
      organization_id: invoice.organization_id,
      description: params["description"],
      line_kind: String.to_existing_atom(params["line_kind"] || "other"),
      quantity: quantity,
      unit_price: unit_price,
      line_total: line_total,
      line_number: next_number
    }

    case Finance.create_invoice_line(attrs, actor: actor) do
      {:ok, _line} ->
        updated_invoice = load_invoice!(invoice.id, actor)
        totals = compute_invoice_totals(updated_invoice)

        case Finance.update_invoice(updated_invoice, totals, actor: actor) do
          {:ok, _} ->
            {:noreply,
             socket
             |> assign(:invoice, load_invoice!(invoice.id, actor))
             |> assign(:show_line_form, false)
             |> assign(:line_form, empty_line_form())
             |> put_flash(:info, "Line added")}

          {:error, reason} ->
            {:noreply, put_flash(socket, :error, "Line created but could not update invoice totals: #{inspect(reason)}")}
        end

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Could not add line: #{inspect(reason)}")}
    end
  end

  @impl true
  def handle_event("delete_line", %{"line_id" => line_id}, socket) do
    invoice = socket.assigns.invoice
    actor = socket.assigns.current_user

    case Finance.get_invoice_line(line_id, actor: actor) do
      {:ok, line} ->
        case Finance.destroy_invoice_line(line, actor: actor) do
          :ok ->
            updated_invoice = load_invoice!(invoice.id, actor)
            totals = compute_invoice_totals(updated_invoice)

            Finance.update_invoice(updated_invoice, totals, actor: actor)

            {:noreply,
             socket
             |> assign(:invoice, load_invoice!(invoice.id, actor))
             |> put_flash(:info, "Line removed")}

          {:error, reason} ->
            {:noreply, put_flash(socket, :error, "Could not remove line: #{inspect(reason)}")}
        end

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Line not found")}
    end
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

  defp empty_line_form, do: %{description: "", quantity: "1", unit_price: ""}

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

  defp compute_invoice_totals(invoice) do
    # line_total_amount is the Ash aggregate (sum of all line totals).
    # We use it as the authoritative subtotal rather than the stored :subtotal
    # attribute, because it reflects the current state of lines after add/remove.
    subtotal = invoice.line_total_amount || Decimal.new("0")
    tax_rate = invoice.tax_rate || Decimal.new("0")
    tax_total = Decimal.mult(subtotal, Decimal.div(tax_rate, Decimal.new("100")))
    total_amount = Decimal.add(subtotal, tax_total)
    applied = invoice.applied_amount || Decimal.new("0")
    balance_amount = Decimal.sub(total_amount, applied)

    %{
      subtotal: subtotal,
      tax_total: tax_total,
      total_amount: total_amount,
      balance_amount: balance_amount
    }
  end
end
