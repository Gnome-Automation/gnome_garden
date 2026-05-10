defmodule GnomeGardenWeb.Finance.TimeEntryLive.Index do
  use GnomeGardenWeb, :live_view
  use Cinder.UrlSync

  import GnomeGardenWeb.Finance.Helpers

  alias GnomeGarden.Finance

  @impl true
  def mount(_params, _session, socket) do
    counts = load_counts(socket.assigns.current_user)

    {:ok,
     socket
     |> assign(:page_title, "Time Entries")
     |> assign(:time_entry_count, counts.total)
     |> assign(:submitted_count, counts.submitted)
     |> assign(:approved_count, counts.approved)
     |> assign(:billable_minutes, counts.billable_minutes)}
  end

  @impl true
  def handle_params(params, uri, socket) do
    socket = Cinder.UrlSync.handle_params(params, uri, socket)
    {:noreply, socket}
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
            Assignments
          </.button>
          <.button navigate={~p"/finance/time-entries/new"} variant="primary">
            New Time Entry
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

      <Cinder.collection
        id="time-entries-table"
        resource={GnomeGarden.Finance.TimeEntry}
        actor={@current_user}
        url_state={@url_state}
        theme={GnomeGardenWeb.CinderTheme}
        page_size={25}
        query_opts={[load: time_entry_index_loads()]}
        click={fn row -> JS.navigate(~p"/finance/time-entries/#{row}") end}
      >
        <:col :let={time_entry} field="description" search sort label="Entry">
          <div class="space-y-1">
            <div class="font-medium text-base-content">{time_entry.description}</div>
            <p class="text-sm text-base-content/50">
              {format_date(time_entry.work_date)}
            </p>
          </div>
        </:col>

        <:col :let={time_entry} label="Context">
          <div class="space-y-1">
            <p>{(time_entry.organization && time_entry.organization.name) || "-"}</p>
            <p class="text-xs text-base-content/40">
              {(time_entry.project && time_entry.project.name) ||
                (time_entry.work_order && time_entry.work_order.title) ||
                "No project/work order"}
            </p>
          </div>
        </:col>

        <:col :let={time_entry} label="Member">
          {display_team_member(time_entry.member_team_member)}
        </:col>

        <:col :let={time_entry} field="minutes" sort label="Amounts">
          <div class="space-y-1">
            <p>{format_minutes(time_entry.minutes)}</p>
            <p class="text-xs text-base-content/40">
              {if(time_entry.billable, do: "Billable", else: "Non-billable")}
            </p>
          </div>
        </:col>

        <:col :let={time_entry} field="status" sort label="Status">
          <.status_badge status={time_entry.status_variant}>
            {format_atom(time_entry.status)}
          </.status_badge>
        </:col>

        <:empty>
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
        </:empty>
      </Cinder.collection>
    </.page>
    """
  end

  defp load_counts(actor) do
    case Finance.list_time_entries(actor: actor) do
      {:ok, entries} ->
        %{
          total: length(entries),
          submitted: Enum.count(entries, &(&1.status == :submitted)),
          approved: Enum.count(entries, &(&1.status == :approved)),
          billable_minutes:
            Enum.reduce(entries, 0, fn entry, total ->
              if entry.billable, do: total + (entry.minutes || 0), else: total
            end)
        }

      {:error, _} ->
        %{total: 0, submitted: 0, approved: 0, billable_minutes: 0}
    end
  end

  defp time_entry_index_loads,
    do: [:status_variant, organization: [], project: [], work_order: [], member_team_member: []]
end
