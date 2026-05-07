defmodule GnomeGardenWeb.Finance.CreditNoteLive.Show do
  use GnomeGardenWeb, :live_view

  alias GnomeGarden.Finance
  alias GnomeGarden.Mailer
  alias GnomeGarden.Mailer.CreditNoteEmail

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    credit_note = load_credit_note!(id, socket.assigns.current_user)

    {:ok,
     socket
     |> assign(:page_title, credit_note.credit_note_number)
     |> assign(:credit_note, credit_note)}
  end

  @impl true
  def handle_event("issue_and_send", _params, socket) do
    cn = socket.assigns.credit_note
    actor = socket.assigns.current_user

    case Finance.issue_credit_note(cn, actor: actor) do
      {:ok, issued} ->
        loaded = load_credit_note!(issued.id, actor)

        result =
          loaded
          |> CreditNoteEmail.build()
          |> Mailer.deliver()

        flash =
          case result do
            {:ok, _} ->
              {:info,
               "Credit note #{cn.credit_note_number} issued and sent to #{recipient_email(loaded)}"}

            {:error, _} ->
              {:error,
               "Credit note issued but email delivery failed — please resend manually."}
          end

        {level, msg} = flash

        {:noreply,
         socket
         |> assign(:credit_note, loaded)
         |> put_flash(level, msg)}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Could not issue: #{inspect(reason)}")}
    end
  end

  @impl true
  def handle_event("save_reason", %{"reason" => reason}, socket) do
    case Finance.update_credit_note(socket.assigns.credit_note, %{reason: reason},
           actor: socket.assigns.current_user
         ) do
      {:ok, updated} ->
        {:noreply,
         socket
         |> assign(:credit_note, updated)
         |> put_flash(:info, "Reason saved")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not save reason")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.page class="pb-8">
      <.page_header eyebrow="Finance">
        {@credit_note.credit_note_number}
        <:subtitle>
          <span class="inline-flex items-center gap-2">
            <.status_badge status={@credit_note.status_variant}>
              {@credit_note.status}
            </.status_badge>
            <span class="text-zinc-400">/</span>
            <.link navigate={~p"/finance/invoices/#{@credit_note.invoice_id}"} class="hover:underline">
              Invoice {@credit_note.invoice && @credit_note.invoice.invoice_number}
            </.link>
          </span>
        </:subtitle>
        <:actions>
          <.button navigate={~p"/finance/credit-notes"}>
            <.icon name="hero-arrow-left" class="size-4" /> Back
          </.button>
          <.button
            :if={@credit_note.status == :draft}
            phx-click="issue_and_send"
            variant="primary"
          >
            <.icon name="hero-paper-airplane" class="size-4" /> Issue & Send
          </.button>
        </:actions>
      </.page_header>

      <div class="grid gap-6 lg:grid-cols-2">
        <.section title="Details">
          <div class="px-5 py-4 space-y-3 text-sm">
            <div>
              <p class="text-xs font-semibold uppercase tracking-widest text-zinc-400 mb-1">Client</p>
              <p>{@credit_note.organization && @credit_note.organization.name}</p>
            </div>
            <div>
              <p class="text-xs font-semibold uppercase tracking-widest text-zinc-400 mb-1">Total (Credit)</p>
              <p class="font-semibold text-red-600">{@credit_note.currency_code} {format_amount(@credit_note.total_amount)}</p>
            </div>
            <div :if={@credit_note.issued_on}>
              <p class="text-xs font-semibold uppercase tracking-widest text-zinc-400 mb-1">Issued On</p>
              <p>{@credit_note.issued_on}</p>
            </div>
          </div>
        </.section>

        <.section title="Reason">
          <div class="px-5 py-4">
            <form phx-submit="save_reason">
              <textarea
                name="reason"
                rows="3"
                placeholder="Optional — e.g. 'Duplicate invoice', 'Client dispute'"
                class="w-full border border-zinc-300 rounded px-3 py-2 text-sm"
                disabled={@credit_note.status != :draft}
              >{@credit_note.reason}</textarea>
              <button
                :if={@credit_note.status == :draft}
                type="submit"
                class="mt-2 text-sm text-emerald-600 hover:underline"
              >
                Save reason
              </button>
            </form>
          </div>
        </.section>
      </div>

      <.section title="Credit Note Lines" class="mt-6">
        <table class="min-w-full divide-y divide-zinc-200 text-sm">
          <thead class="bg-zinc-50">
            <tr>
              <th class="px-5 py-3 text-left font-medium text-zinc-500">Description</th>
              <th class="px-5 py-3 text-right font-medium text-zinc-500">Qty</th>
              <th class="px-5 py-3 text-right font-medium text-zinc-500">Unit Price</th>
              <th class="px-5 py-3 text-right font-medium text-zinc-500">Line Total</th>
            </tr>
          </thead>
          <tbody class="divide-y divide-zinc-200">
            <tr :for={line <- @credit_note.credit_note_lines}>
              <td class="px-5 py-3">{line.description}</td>
              <td class="px-5 py-3 text-right">{line.quantity}</td>
              <td class="px-5 py-3 text-right">{format_amount(line.unit_price)}</td>
              <td class="px-5 py-3 text-right text-red-600">{format_amount(line.line_total)}</td>
            </tr>
          </tbody>
          <tfoot>
            <tr class="bg-zinc-50">
              <td colspan="3" class="px-5 py-3 font-medium">Total</td>
              <td class="px-5 py-3 text-right font-semibold text-red-600">
                {@credit_note.currency_code} {format_amount(@credit_note.total_amount)}
              </td>
            </tr>
          </tfoot>
        </table>
      </.section>
    </.page>
    """
  end

  defp load_credit_note!(id, actor) do
    case Finance.get_credit_note(id,
           actor: actor,
           load: [
             :status_variant,
             :credit_note_lines,
             :invoice,
             organization: [:billing_contact]
           ]
         ) do
      {:ok, cn} -> cn
      {:error, err} -> raise "failed to load credit note #{id}: #{inspect(err)}"
    end
  end

  defp recipient_email(credit_note) do
    GnomeGarden.Mailer.InvoiceEmail.find_billing_email(credit_note.organization || %{}) ||
      "billing@gnomeautomation.io"
  end

  defp format_amount(nil), do: "0.00"
  defp format_amount(d), do: Decimal.to_string(Decimal.round(d, 2), :normal)
end
