defmodule GnomeGardenWeb.Finance.TimeEntryLive.Index do
  use GnomeGardenWeb, :live_view

  import GnomeGardenWeb.Finance.Helpers

  alias GnomeGarden.Finance

  @impl true
  def mount(_params, _session, socket) do
    time_entries = load_time_entries(socket.assigns.current_user)

    {:ok,
     socket
     |> assign(:page_title, "Time Entries")
     |> assign(:time_entry_count, length(time_entries))
     |> assign(:submitted_count, Enum.count(time_entries, &(&1.status == :submitted)))
     |> assign(:approved_count, Enum.count(time_entries, &(&1.status == :approved)))
     |> assign(
       :billable_minutes,
       Enum.reduce(time_entries, 0, fn entry, total ->
         if entry.billable, do: total + (entry.minutes || 0), else: total
       end)
     )
     |> stream(:time_entries, time_entries)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.page class="pb-8">
      <.page_header eyebrow="Finance">
        Time Entries
        <:subtitle>
          Labor records that bridge execution work into approvals, entitlement usage, and invoice drafting.
        </:subtitle>
        <:actions>
          <.button navigate={~p"/execution/assignments"}>
            <.icon name="hero-calendar-days" class="size-4" /> Assignments
          </.button>
          <.button navigate={~p"/finance/time-entries/new"} variant="primary">
            <.icon name="hero-plus" class="size-4" /> New Time Entry
          </.button>
        </:actions>
      </.page_header>

      <div class="grid gap-4 md:grid-cols-4">
        <.stat_card
          title="Time Entries"
          value={Integer.to_string(@time_entry_count)}
          description="Operational labor rows captured against agreements, projects, work items, and work orders."
          icon="hero-clock"
        />
        <.stat_card
          title="Submitted"
          value={Integer.to_string(@submitted_count)}
          description="Entries waiting on explicit approval before they can affect billing or entitlements."
          icon="hero-paper-airplane"
          accent="amber"
        />
        <.stat_card
          title="Approved"
          value={Integer.to_string(@approved_count)}
          description="Entries cleared for billing, reporting, and contract-consumption automation."
          icon="hero-check-badge"
          accent="emerald"
        />
        <.stat_card
          title="Billable Minutes"
          value={Integer.to_string(@billable_minutes)}
          description="Billable labor volume currently represented by the register."
          icon="hero-banknotes"
          accent="sky"
        />
      </div>

      <.section
        title="Labor Register"
        description="Keep labor visible as first-class operational finance instead of burying it inside projects or invoices."
        compact
        body_class="p-0"
      >
        <div :if={@time_entry_count == 0} class="p-6 sm:p-7">
          <.empty_state
            icon="hero-clock"
            title="No time entries yet"
            description="Create time entries once execution work is happening so billing and entitlement usage have a durable source."
          >
            <:action>
              <.button navigate={~p"/finance/time-entries/new"} variant="primary">
                Create Time Entry
              </.button>
            </:action>
          </.empty_state>
        </div>

        <div :if={@time_entry_count > 0} class="overflow-x-auto">
          <table class="min-w-full divide-y divide-zinc-200 text-sm dark:divide-white/10">
            <thead class="bg-zinc-50 dark:bg-white/[0.03]">
              <tr>
                <th class="px-5 py-3 text-left font-medium text-zinc-500 dark:text-zinc-400">
                  Entry
                </th>
                <th class="px-5 py-3 text-left font-medium text-zinc-500 dark:text-zinc-400">
                  Context
                </th>
                <th class="px-5 py-3 text-left font-medium text-zinc-500 dark:text-zinc-400">
                  Member
                </th>
                <th class="px-5 py-3 text-left font-medium text-zinc-500 dark:text-zinc-400">
                  Amounts
                </th>
                <th class="px-5 py-3 text-left font-medium text-zinc-500 dark:text-zinc-400">
                  Status
                </th>
              </tr>
            </thead>
            <tbody
              id="time-entries"
              phx-update="stream"
              class="divide-y divide-zinc-200 dark:divide-white/10"
            >
              <tr :for={{dom_id, time_entry} <- @streams.time_entries} id={dom_id}>
                <td class="px-5 py-4 align-top">
                  <div class="space-y-1">
                    <.link
                      navigate={~p"/finance/time-entries/#{time_entry}"}
                      class="font-medium text-zinc-900 hover:text-emerald-600 dark:text-white"
                    >
                      {time_entry.description}
                    </.link>
                    <p class="text-sm text-zinc-500 dark:text-zinc-400">
                      {format_date(time_entry.work_date)}
                    </p>
                  </div>
                </td>
                <td class="px-5 py-4 align-top text-zinc-600 dark:text-zinc-300">
                  <div class="space-y-1">
                    <p>{(time_entry.organization && time_entry.organization.name) || "-"}</p>
                    <p class="text-xs text-zinc-400 dark:text-zinc-500">
                      {(time_entry.project && time_entry.project.name) ||
                        (time_entry.work_order && time_entry.work_order.title) ||
                        "No project/work order"}
                    </p>
                  </div>
                </td>
                <td class="px-5 py-4 align-top text-zinc-600 dark:text-zinc-300">
                  {display_email(time_entry.member_user)}
                </td>
                <td class="px-5 py-4 align-top text-zinc-600 dark:text-zinc-300">
                  <div class="space-y-1">
                    <p>{format_minutes(time_entry.minutes)}</p>
                    <p class="text-xs text-zinc-400 dark:text-zinc-500">
                      {if(time_entry.billable, do: "Billable", else: "Non-billable")}
                    </p>
                  </div>
                </td>
                <td class="px-5 py-4 align-top">
                  <.status_badge status={time_entry.status_variant}>
                    {format_atom(time_entry.status)}
                  </.status_badge>
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </.section>
    </.page>
    """
  end

  defp load_time_entries(actor) do
    user_loads = if actor, do: [member_user: []], else: []

    case Finance.list_time_entries(
           actor: actor,
           query: [sort: [work_date: :desc, inserted_at: :desc]],
           load: [:status_variant, organization: [], project: [], work_order: []] ++ user_loads
         ) do
      {:ok, time_entries} -> time_entries
      {:error, error} -> raise "failed to load time entries: #{inspect(error)}"
    end
  end
end
