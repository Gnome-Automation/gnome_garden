defmodule GnomeGardenWeb.Finance.CreditNoteLive.Index do
  use GnomeGardenWeb, :live_view

  import GnomeGardenWeb.Finance.Helpers, only: [format_atom: 1]

  alias GnomeGarden.Finance

  require Ash.Query

  @impl true
  def mount(_params, _session, socket) do
    credit_notes = load_credit_notes(socket.assigns.current_user, nil)

    {:ok,
     socket
     |> assign(:page_title, "Credit Notes")
     |> assign(:status_filter, nil)
     |> assign(:credit_notes, credit_notes)}
  end

  @impl true
  def handle_event("filter_status", %{"status" => status}, socket) do
    filter = if status == "", do: nil, else: String.to_existing_atom(status)
    credit_notes = load_credit_notes(socket.assigns.current_user, filter)
    {:noreply, socket |> assign(:status_filter, filter) |> assign(:credit_notes, credit_notes)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.page class="pb-8">
      <.page_header eyebrow="Finance">
        Credit Notes
        <:subtitle>All credit notes issued against voided invoices.</:subtitle>
      </.page_header>

      <div class="mb-4 flex items-center gap-3">
        <div class="grid grid-cols-1">
          <select
            phx-change="filter_status"
            name="status"
            class="col-start-1 row-start-1 appearance-none rounded-md bg-base-100 py-1.5 pr-8 pl-3 text-sm text-base-content outline-1 -outline-offset-1 outline-base-content/20 hover:bg-base-200 focus:outline-2 focus:-outline-offset-2 focus:outline-primary transition-colors cursor-pointer"
          >
            <option value="">All Statuses</option>
            <option value="draft" selected={@status_filter == :draft}>Draft</option>
            <option value="issued" selected={@status_filter == :issued}>Issued</option>
          </select>
          <svg class="pointer-events-none col-start-1 row-start-1 mr-2 size-4 self-center justify-self-end text-base-content/40" viewBox="0 0 16 16" fill="currentColor">
            <path fill-rule="evenodd" d="M4.22 6.22a.75.75 0 0 1 1.06 0L8 8.94l2.72-2.72a.75.75 0 1 1 1.06 1.06l-3.25 3.25a.75.75 0 0 1-1.06 0L4.22 7.28a.75.75 0 0 1 0-1.06Z" clip-rule="evenodd" />
          </svg>
        </div>
      </div>

      <.section>
        <div :if={Enum.empty?(@credit_notes)} class="px-5 py-8 text-sm text-zinc-400 italic text-center">
          No credit notes yet. Void an invoice to create one.
        </div>
        <table :if={not Enum.empty?(@credit_notes)} class="min-w-full divide-y divide-zinc-200 text-sm">
          <thead class="bg-zinc-50">
            <tr>
              <th class="px-5 py-3 text-left font-medium text-zinc-500">CN Number</th>
              <th class="px-5 py-3 text-left font-medium text-zinc-500">Invoice</th>
              <th class="px-5 py-3 text-left font-medium text-zinc-500">Client</th>
              <th class="px-5 py-3 text-right font-medium text-zinc-500">Total</th>
              <th class="px-5 py-3 text-left font-medium text-zinc-500">Status</th>
              <th class="px-5 py-3 text-left font-medium text-zinc-500">Issued</th>
            </tr>
          </thead>
          <tbody class="divide-y divide-zinc-200">
            <tr :for={cn <- @credit_notes}>
              <td class="px-5 py-3">
                <.link navigate={~p"/finance/credit-notes/#{cn.id}"} class="font-medium text-emerald-600 hover:underline">
                  {cn.credit_note_number}
                </.link>
              </td>
              <td class="px-5 py-3 text-zinc-600">
                <.link navigate={~p"/finance/invoices/#{cn.invoice_id}"} class="hover:underline">
                  {cn.invoice && cn.invoice.invoice_number}
                </.link>
              </td>
              <td class="px-5 py-3 text-zinc-600">
                {cn.organization && cn.organization.name}
              </td>
              <td class="px-5 py-3 text-right font-medium">
                {cn.currency_code} {format_amount(cn.total_amount)}
              </td>
              <td class="px-5 py-3">
                <.status_badge status={cn.status_variant}>{format_atom(cn.status)}</.status_badge>
              </td>
              <td class="px-5 py-3 text-zinc-600">{cn.issued_on || "—"}</td>
            </tr>
          </tbody>
        </table>
      </.section>
    </.page>
    """
  end

  defp load_credit_notes(actor, status_filter) do
    query =
      GnomeGarden.Finance.CreditNote
      |> Ash.Query.sort(inserted_at: :desc)
      |> Ash.Query.load([:status_variant, :invoice, :organization])
      |> then(fn q ->
        if status_filter, do: Ash.Query.filter(q, status == ^status_filter), else: q
      end)

    case Finance.list_credit_notes(query: query, actor: actor) do
      {:ok, cns} -> cns
      _ -> []
    end
  end

  defp format_amount(nil), do: "0.00"
  defp format_amount(d), do: Decimal.to_string(Decimal.round(d, 2), :normal)
end
