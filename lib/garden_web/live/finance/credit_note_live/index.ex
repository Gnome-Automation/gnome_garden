defmodule GnomeGardenWeb.Finance.CreditNoteLive.Index do
  use GnomeGardenWeb, :live_view

  alias GnomeGarden.Finance

  require Ash.Query

  @impl true
  def mount(_params, _session, socket) do
    credit_notes = load_credit_notes(socket.assigns.current_user)

    {:ok,
     socket
     |> assign(:page_title, "Credit Notes")
     |> assign(:credit_notes, credit_notes)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.page class="pb-8">
      <.page_header eyebrow="Finance">
        Credit Notes
        <:subtitle>All credit notes issued against voided invoices.</:subtitle>
      </.page_header>

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
                <.status_badge status={cn.status_variant}>{cn.status}</.status_badge>
              </td>
              <td class="px-5 py-3 text-zinc-600">{cn.issued_on || "—"}</td>
            </tr>
          </tbody>
        </table>
      </.section>
    </.page>
    """
  end

  defp load_credit_notes(actor) do
    query =
      GnomeGarden.Finance.CreditNote
      |> Ash.Query.sort(inserted_at: :desc)
      |> Ash.Query.load([:status_variant, :invoice, :organization])

    case Finance.list_credit_notes(query: query, actor: actor, authorize?: false) do
      {:ok, cns} -> cns
      _ -> []
    end
  end

  defp format_amount(nil), do: "0.00"
  defp format_amount(d), do: Decimal.to_string(Decimal.round(d, 2), :normal)
end
