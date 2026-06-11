defmodule GnomeGardenWeb.Finance.JournalEntryLive.Show do
  use GnomeGardenWeb, :live_view

  require Ash.Query

  alias GnomeGarden.Finance

  @impl true
  def mount(%{"id" => id} = params, _session, socket) do
    return_to = Map.get(params, "return_to", ~p"/finance/journal-entries")

    case Finance.get_journal_entry(id, authorize?: false, load: [lines: [:account]]) do
      {:ok, entry} ->
        {:ok,
         socket
         |> assign(:page_title, entry.entry_number)
         |> assign(:entry, entry)
         |> assign(:return_to, return_to)}

      {:error, _} ->
        {:ok,
         socket
         |> put_flash(:error, "Journal entry not found.")
         |> push_navigate(to: ~p"/finance/journal-entries")}
    end
  end

  @impl true
  def handle_event("post", _params, socket) do
    entry = socket.assigns.entry

    case Finance.post_journal_entry(entry, authorize?: false) do
      {:ok, updated} ->
        {:noreply,
         socket
         |> assign(:entry, %{updated | lines: entry.lines})
         |> put_flash(:info, "Journal entry posted.")}

      {:error, error} ->
        {:noreply, put_flash(socket, :error, format_post_error(error))}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.page class="pb-8">
      <.page_header eyebrow="Finance / Journal Entries">
        <%= @entry.entry_number %>
        <:subtitle><%= @entry.description %></:subtitle>
        <:actions>
          <%= if @entry.status == :draft do %>
            <.button phx-click="post" data-confirm="Post this entry? It cannot be edited after posting.">
              Post Entry
            </.button>
          <% end %>
          <.button navigate={@return_to}>
            Back
          </.button>
        </:actions>
      </.page_header>

      <div class="mb-6 grid grid-cols-2 gap-4 sm:grid-cols-4">
        <div>
          <p class="text-xs font-medium uppercase tracking-wide text-gray-500">Date</p>
          <p class="mt-1 text-sm text-gray-900 dark:text-white"><%= @entry.date %></p>
        </div>
        <div>
          <p class="text-xs font-medium uppercase tracking-wide text-gray-500">Type</p>
          <p class="mt-1 text-sm text-gray-900 dark:text-white"><%= format_type(@entry.entry_type) %></p>
        </div>
        <div>
          <p class="text-xs font-medium uppercase tracking-wide text-gray-500">Status</p>
          <p class="mt-1">
            <span class={status_class(@entry.status)}>
              <%= String.capitalize(to_string(@entry.status)) %>
            </span>
          </p>
        </div>
        <%= if @entry.reference_type do %>
          <div>
            <p class="text-xs font-medium uppercase tracking-wide text-gray-500">Reference</p>
            <p class="mt-1 text-sm font-mono text-gray-500">
              <%= @entry.reference_type %> / <%= @entry.reference_id %>
            </p>
          </div>
        <% end %>
      </div>

      <div class="overflow-hidden rounded-lg border border-gray-200 dark:border-white/10">
        <table class="min-w-full divide-y divide-gray-200 dark:divide-white/10">
          <thead class="bg-gray-50 dark:bg-white/5">
            <tr>
              <th class="px-4 py-3 text-left text-xs font-semibold uppercase tracking-wide text-gray-500">Account</th>
              <th class="px-4 py-3 text-left text-xs font-semibold uppercase tracking-wide text-gray-500">Description</th>
              <th class="px-4 py-3 text-right text-xs font-semibold uppercase tracking-wide text-gray-500">Debit</th>
              <th class="px-4 py-3 text-right text-xs font-semibold uppercase tracking-wide text-gray-500">Credit</th>
            </tr>
          </thead>
          <tbody class="divide-y divide-gray-100 bg-white dark:divide-white/5 dark:bg-transparent">
            <%= for line <- @entry.lines do %>
              <tr>
                <td class="px-4 py-3 text-sm font-mono text-gray-900 dark:text-white">
                  <%= line.account.number %> — <%= line.account.name %>
                </td>
                <td class="px-4 py-3 text-sm text-gray-500"><%= line.description %></td>
                <td class="px-4 py-3 text-right text-sm font-mono text-gray-900 dark:text-white">
                  <%= if line.debit, do: format_amount(line.debit), else: "" %>
                </td>
                <td class="px-4 py-3 text-right text-sm font-mono text-gray-900 dark:text-white">
                  <%= if line.credit, do: format_amount(line.credit), else: "" %>
                </td>
              </tr>
            <% end %>
          </tbody>
          <tfoot class="bg-gray-50 dark:bg-white/5">
            <tr>
              <td colspan="2" class="px-4 py-3 text-sm font-semibold text-gray-900 dark:text-white text-right">Totals</td>
              <td class="px-4 py-3 text-right text-sm font-mono font-semibold text-gray-900 dark:text-white">
                <%= format_amount(total_debits(@entry.lines)) %>
              </td>
              <td class="px-4 py-3 text-right text-sm font-mono font-semibold text-gray-900 dark:text-white">
                <%= format_amount(total_credits(@entry.lines)) %>
              </td>
            </tr>
          </tfoot>
        </table>
      </div>
    </.page>
    """
  end

  defp total_debits(lines) do
    lines
    |> Enum.map(& &1.debit)
    |> Enum.reject(&is_nil/1)
    |> Enum.reduce(Decimal.new("0"), &Decimal.add/2)
  end

  defp total_credits(lines) do
    lines
    |> Enum.map(& &1.credit)
    |> Enum.reject(&is_nil/1)
    |> Enum.reduce(Decimal.new("0"), &Decimal.add/2)
  end

  defp format_amount(nil), do: ""

  defp format_amount(d) do
    "$#{Decimal.round(d, 2)}"
  end

  defp format_type(:manual), do: "Manual"
  defp format_type(:invoice_issued), do: "Invoice Issued"
  defp format_type(:payment_received), do: "Payment Received"
  defp format_type(:credit_note_issued), do: "Credit Note Issued"
  defp format_type(:invoice_voided), do: "Invoice Voided"
  defp format_type(:invoice_written_off), do: "Written Off"
  defp format_type(:expense_approved), do: "Expense Approved"
  defp format_type(t), do: to_string(t)

  defp status_class(:posted),
    do: "inline-flex rounded-full bg-emerald-50 px-2 py-0.5 text-xs font-medium text-emerald-700"

  defp status_class(_),
    do: "inline-flex rounded-full bg-yellow-50 px-2 py-0.5 text-xs font-medium text-yellow-700"

  defp format_post_error(%Ash.Error.Invalid{errors: [first | _]}), do: first.message
  defp format_post_error(e), do: inspect(e)
end
