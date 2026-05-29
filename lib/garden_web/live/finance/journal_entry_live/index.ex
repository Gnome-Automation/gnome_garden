defmodule GnomeGardenWeb.Finance.JournalEntryLive.Index do
  use GnomeGardenWeb, :live_view

  require Ash.Query

  alias GnomeGarden.Finance
  alias GnomeGarden.Finance.JournalEntry

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Journal Entries")
     |> assign(:filter_status, "")
     |> assign(:filter_type, "")
     |> assign(:filter_from, "")
     |> assign(:filter_to, "")
     |> assign(:entries, load_entries(%{}))}
  end

  @impl true
  def handle_event("filter", params, socket) do
    filters = %{
      status: params["status"],
      type: params["type"],
      from: params["from"],
      to: params["to"]
    }

    {:noreply,
     socket
     |> assign(:filter_status, params["status"] || "")
     |> assign(:filter_type, params["type"] || "")
     |> assign(:filter_from, params["from"] || "")
     |> assign(:filter_to, params["to"] || "")
     |> assign(:entries, load_entries(filters))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.page class="pb-8">
      <.page_header eyebrow="Finance">
        Journal Entries
        <:subtitle>All double-entry journal entries — auto-posted and manual.</:subtitle>
        <:actions>
          <.button navigate={~p"/finance/journal-entries/new"}>
            New Manual Entry
          </.button>
        </:actions>
      </.page_header>

      <form phx-change="filter" class="mb-6 flex flex-wrap gap-3">
        <input type="date" name="from" value={@filter_from}
          placeholder="From"
          class="rounded-md bg-white px-3 py-1.5 text-sm text-gray-900 outline-1 -outline-offset-1 outline-gray-300 focus:outline-2 focus:-outline-offset-2 focus:outline-emerald-600 dark:bg-white/5 dark:text-white dark:outline-white/10" />
        <input type="date" name="to" value={@filter_to}
          placeholder="To"
          class="rounded-md bg-white px-3 py-1.5 text-sm text-gray-900 outline-1 -outline-offset-1 outline-gray-300 focus:outline-2 focus:-outline-offset-2 focus:outline-emerald-600 dark:bg-white/5 dark:text-white dark:outline-white/10" />
        <select name="type"
          class="rounded-md bg-white px-3 py-1.5 text-sm text-gray-900 outline-1 -outline-offset-1 outline-gray-300 focus:outline-2 focus:-outline-offset-2 focus:outline-emerald-600 dark:bg-white/5 dark:text-white dark:outline-white/10">
          <option value="">All Types</option>
          <option value="manual" selected={@filter_type == "manual"}>Manual</option>
          <option value="invoice_issued" selected={@filter_type == "invoice_issued"}>Invoice Issued</option>
          <option value="payment_received" selected={@filter_type == "payment_received"}>Payment Received</option>
          <option value="credit_note_issued" selected={@filter_type == "credit_note_issued"}>Credit Note Issued</option>
          <option value="invoice_voided" selected={@filter_type == "invoice_voided"}>Invoice Voided</option>
          <option value="invoice_written_off" selected={@filter_type == "invoice_written_off"}>Written Off</option>
          <option value="expense_approved" selected={@filter_type == "expense_approved"}>Expense Approved</option>
        </select>
        <select name="status"
          class="rounded-md bg-white px-3 py-1.5 text-sm text-gray-900 outline-1 -outline-offset-1 outline-gray-300 focus:outline-2 focus:-outline-offset-2 focus:outline-emerald-600 dark:bg-white/5 dark:text-white dark:outline-white/10">
          <option value="">All Statuses</option>
          <option value="draft" selected={@filter_status == "draft"}>Draft</option>
          <option value="posted" selected={@filter_status == "posted"}>Posted</option>
        </select>
      </form>

      <div class="overflow-hidden rounded-lg border border-gray-200 dark:border-white/10">
        <table class="min-w-full divide-y divide-gray-200 dark:divide-white/10">
          <thead class="bg-gray-50 dark:bg-white/5">
            <tr>
              <th class="px-4 py-3 text-left text-xs font-semibold uppercase tracking-wide text-gray-500">Entry #</th>
              <th class="px-4 py-3 text-left text-xs font-semibold uppercase tracking-wide text-gray-500">Date</th>
              <th class="px-4 py-3 text-left text-xs font-semibold uppercase tracking-wide text-gray-500">Description</th>
              <th class="px-4 py-3 text-left text-xs font-semibold uppercase tracking-wide text-gray-500">Type</th>
              <th class="px-4 py-3 text-left text-xs font-semibold uppercase tracking-wide text-gray-500">Status</th>
            </tr>
          </thead>
          <tbody class="divide-y divide-gray-100 bg-white dark:divide-white/5 dark:bg-transparent">
            <%= if @entries == [] do %>
              <tr>
                <td colspan="5" class="px-4 py-8 text-center text-sm text-gray-400">No journal entries found.</td>
              </tr>
            <% end %>
            <%= for entry <- @entries do %>
              <tr class="cursor-pointer hover:bg-gray-50 dark:hover:bg-white/5"
                phx-click={JS.navigate(~p"/finance/journal-entries/#{entry.id}")}>
                <td class="px-4 py-3 text-sm font-mono text-gray-900 dark:text-white"><%= entry.entry_number %></td>
                <td class="px-4 py-3 text-sm text-gray-500"><%= entry.date %></td>
                <td class="px-4 py-3 text-sm text-gray-900 dark:text-white"><%= entry.description %></td>
                <td class="px-4 py-3 text-sm text-gray-500"><%= format_type(entry.entry_type) %></td>
                <td class="px-4 py-3 text-sm">
                  <span class={status_class(entry.status)}>
                    <%= String.capitalize(to_string(entry.status)) %>
                  </span>
                </td>
              </tr>
            <% end %>
          </tbody>
        </table>
      </div>
    </.page>
    """
  end

  defp load_entries(filters) do
    JournalEntry
    |> Ash.Query.sort(date: :desc, inserted_at: :desc)
    |> maybe_filter_status(filters[:status])
    |> maybe_filter_type(filters[:type])
    |> maybe_filter_from(filters[:from])
    |> maybe_filter_to(filters[:to])
    |> Ash.read!(domain: Finance, authorize?: false)
  end

  defp maybe_filter_status(q, nil), do: q
  defp maybe_filter_status(q, ""), do: q

  defp maybe_filter_status(q, status) do
    atom = String.to_existing_atom(status)
    Ash.Query.filter(q, status == ^atom)
  end

  defp maybe_filter_type(q, nil), do: q
  defp maybe_filter_type(q, ""), do: q

  defp maybe_filter_type(q, type) do
    atom = String.to_existing_atom(type)
    Ash.Query.filter(q, entry_type == ^atom)
  end

  defp maybe_filter_from(q, nil), do: q
  defp maybe_filter_from(q, ""), do: q

  defp maybe_filter_from(q, from_str) do
    case Date.from_iso8601(from_str) do
      {:ok, date} -> Ash.Query.filter(q, date >= ^date)
      _ -> q
    end
  end

  defp maybe_filter_to(q, nil), do: q
  defp maybe_filter_to(q, ""), do: q

  defp maybe_filter_to(q, to_str) do
    case Date.from_iso8601(to_str) do
      {:ok, date} -> Ash.Query.filter(q, date <= ^date)
      _ -> q
    end
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
end
