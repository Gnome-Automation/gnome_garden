defmodule GnomeGardenWeb.Finance.ApprovalQueueLive do
  use GnomeGardenWeb, :live_view

  import GnomeGardenWeb.Finance.Helpers

  alias GnomeGarden.Finance

  @impl true
  def mount(_params, _session, socket) do
    entries = load_submitted(socket.assigns.current_user)

    {:ok,
     socket
     |> assign(:page_title, "Approval Queue")
     |> assign(:count, length(entries))
     |> stream(:entries, entries)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.page class="pb-8">
      <.page_header eyebrow="Finance">
        Approval Queue
        <:subtitle>
          Submitted time entries waiting for manager approval before they can be invoiced.
        </:subtitle>
        <:actions>
          <.button navigate={~p"/finance/time-entries"}>
            <.icon name="hero-arrow-left" class="size-4" /> All Time Entries
          </.button>
        </:actions>
      </.page_header>

      <.section
        title={"Submitted Entries (#{@count})"}
        description="Approving an entry marks it ready for invoicing. Rejecting returns it to draft."
        compact
        body_class="p-0"
      >
        <div :if={@count == 0} class="p-6 sm:p-7">
          <.empty_state
            icon="hero-check-badge"
            title="No entries pending approval"
            description="All submitted time entries have been reviewed."
          />
        </div>

        <div :if={@count > 0} class="overflow-x-auto">
          <table class="min-w-full divide-y divide-zinc-200 text-sm dark:divide-white/10">
            <thead class="bg-zinc-50 dark:bg-white/[0.03]">
              <tr>
                <th class="px-5 py-3 text-left font-medium text-zinc-500 dark:text-zinc-400">
                  Entry
                </th>
                <th class="px-5 py-3 text-left font-medium text-zinc-500 dark:text-zinc-400">
                  Member
                </th>
                <th class="px-5 py-3 text-left font-medium text-zinc-500 dark:text-zinc-400">
                  Agreement
                </th>
                <th class="px-5 py-3 text-left font-medium text-zinc-500 dark:text-zinc-400">
                  Hours / Rate
                </th>
                <th class="px-5 py-3 text-left font-medium text-zinc-500 dark:text-zinc-400">
                  Actions
                </th>
              </tr>
            </thead>
            <tbody
              id="approval-entries"
              phx-update="stream"
              class="divide-y divide-zinc-200 dark:divide-white/10"
            >
              <tr :for={{dom_id, entry} <- @streams.entries} id={dom_id}>
                <td class="px-5 py-4 align-top">
                  <div class="space-y-1">
                    <.link
                      navigate={~p"/finance/time-entries/#{entry}"}
                      class="font-medium text-zinc-900 hover:text-emerald-600 dark:text-white"
                    >
                      {entry.description}
                    </.link>
                    <p class="text-sm text-zinc-500 dark:text-zinc-400">
                      {format_date(entry.work_date)}
                    </p>
                  </div>
                </td>
                <td class="px-5 py-4 align-top text-zinc-600 dark:text-zinc-300">
                  {display_email(entry.member_user)}
                </td>
                <td class="px-5 py-4 align-top text-zinc-600 dark:text-zinc-300">
                  {(entry.agreement && entry.agreement.name) || "-"}
                </td>
                <td class="px-5 py-4 align-top text-zinc-600 dark:text-zinc-300">
                  <div class="space-y-1">
                    <p>{format_minutes(entry.minutes)}</p>
                    <p class="text-xs text-zinc-400 dark:text-zinc-500">
                      {if entry.bill_rate, do: "$#{entry.bill_rate}/hr", else: "No rate"}
                    </p>
                  </div>
                </td>
                <td class="px-5 py-4 align-top">
                  <div class="flex gap-3">
                    <button
                      phx-click="approve"
                      phx-value-id={entry.id}
                      phx-disable-with="Approving..."
                      class="text-sm font-medium text-emerald-600 hover:text-emerald-700 dark:text-emerald-400"
                    >
                      Approve
                    </button>
                    <button
                      phx-click="reject"
                      phx-value-id={entry.id}
                      phx-disable-with="Rejecting..."
                      class="text-sm font-medium text-red-600 hover:text-red-700 dark:text-red-400"
                    >
                      Reject
                    </button>
                  </div>
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </.section>
    </.page>
    """
  end

  @impl true
  def handle_event("approve", %{"id" => id}, socket) do
    actor = socket.assigns.current_user

    with {:ok, entry} <- Finance.get_time_entry(id, actor: actor),
         {:ok, _updated} <- Finance.approve_time_entry(entry, actor: actor) do
      {:noreply,
       socket
       |> put_flash(:info, "Entry approved")
       |> stream_delete(:entries, entry)
       |> assign(:count, socket.assigns.count - 1)}
    else
      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Could not approve: #{inspect(reason)}")}
    end
  end

  @impl true
  def handle_event("reject", %{"id" => id}, socket) do
    actor = socket.assigns.current_user

    with {:ok, entry} <- Finance.get_time_entry(id, actor: actor),
         {:ok, _updated} <- Finance.reject_time_entry(entry, actor: actor) do
      {:noreply,
       socket
       |> put_flash(:info, "Entry rejected — returned to draft")
       |> stream_delete(:entries, entry)
       |> assign(:count, socket.assigns.count - 1)}
    else
      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Could not reject: #{inspect(reason)}")}
    end
  end

  defp load_submitted(actor) do
    case Finance.list_time_entries(
           actor: actor,
           query: [filter: [status: :submitted], sort: [work_date: :asc, inserted_at: :asc]],
           load: [:status_variant, organization: [], agreement: [], project: [], member_user: []]
         ) do
      {:ok, entries} -> entries
      {:error, error} -> raise "failed to load approval queue: #{inspect(error)}"
    end
  end
end
