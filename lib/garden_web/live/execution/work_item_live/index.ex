defmodule GnomeGardenWeb.Execution.WorkItemLive.Index do
  use GnomeGardenWeb, :live_view
  use Cinder.UrlSync

  import GnomeGardenWeb.Execution.Helpers

  alias GnomeGarden.Execution

  @impl true
  def mount(_params, _session, socket) do
    counts = load_counts(socket.assigns.current_user)

    {:ok,
     socket
     |> assign(:page_title, "Work Items")
     |> assign(:work_item_count, counts.total)
     |> assign(:open_count, counts.open)
     |> assign(:blocked_count, counts.blocked)
     |> assign(:due_soon_count, counts.due_soon)}
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
      <.page_header eyebrow="Execution">
        Work Items
        <:subtitle>
          Plan delivery through durable execution units instead of hiding actual work under project headers.
        </:subtitle>
        <:actions>
          <.button navigate={~p"/execution/projects"}>
            Projects
          </.button>
          <.button navigate={~p"/execution/work-items/new"} variant="primary">
            New Work Item
          </.button>
        </:actions>
      </.page_header>

      <div class="grid gap-4 md:grid-cols-4">
        <.stat_card
          title="Work Items"
          value={Integer.to_string(@work_item_count)}
          description="Phases, tasks, issues, milestones, and deliverables attached to project execution."
          icon="hero-queue-list"
        />
        <.stat_card
          title="Open"
          value={Integer.to_string(@open_count)}
          description="Items still flowing through backlog, ready, active, blocked, or review states."
          icon="hero-play"
          accent="sky"
        />
        <.stat_card
          title="Blocked"
          value={Integer.to_string(@blocked_count)}
          description="Execution work that needs attention before the project can move cleanly."
          icon="hero-no-symbol"
          accent="amber"
        />
        <.stat_card
          title="Due Soon"
          value={Integer.to_string(@due_soon_count)}
          description="Open items due within the next seven days and worth triaging now."
          icon="hero-calendar-days"
          accent="rose"
        />
      </div>

      <Cinder.collection
        id="work-items-table"
        resource={GnomeGarden.Execution.WorkItem}
        actor={@current_user}
        url_state={@url_state}
        theme={GnomeGardenWeb.CinderTheme}
        page_size={25}
        query_opts={[load: work_item_index_loads()]}
        click={fn row -> JS.navigate(~p"/execution/work-items/#{row}") end}
      >
        <:col :let={work_item} field="title" search sort label="Work Item">
          <div class="space-y-1">
            <div class="font-medium text-base-content">{work_item.title}</div>
            <p class="text-sm text-base-content/50">
              {work_item.code || "No code"} · {display_team_member(
                work_item.owner_team_member,
                "Unassigned"
              )}
            </p>
          </div>
        </:col>

        <:col :let={work_item} label="Project">
          {(work_item.project && work_item.project.name) || "-"}
        </:col>

        <:col :let={work_item} label="Shape">
          <div class="space-y-2">
            <.tag color={:zinc}>{format_atom(work_item.kind)}</.tag>
            <.tag color={:emerald}>{format_atom(work_item.discipline)}</.tag>
            <p class="text-xs text-base-content/40">
              {work_item.child_work_item_count || 0} children · {work_item.assignment_count || 0} assignments
            </p>
          </div>
        </:col>

        <:col :let={work_item} field="due_on" sort label="Scheduling">
          <div class="space-y-1">
            <p>Due {format_date(work_item.due_on)}</p>
            <p class="text-xs text-base-content/40">
              {format_minutes(work_item.estimate_minutes)}
            </p>
          </div>
        </:col>

        <:col :let={work_item} field="status" sort label="Status">
          <div class="space-y-2">
            <.status_badge status={work_item.status_variant}>
              {format_atom(work_item.status)}
            </.status_badge>
            <.status_badge status={work_item.priority_variant}>
              {format_atom(work_item.priority)}
            </.status_badge>
          </div>
        </:col>

        <:empty>
          <.empty_state
            icon="hero-queue-list"
            title="No work items yet"
            description="Add work items directly or create them from a project to make delivery planning explicit."
          >
            <:action>
              <.button navigate={~p"/execution/work-items/new"} variant="primary">
                Create Work Item
              </.button>
            </:action>
          </.empty_state>
        </:empty>
      </Cinder.collection>
    </.page>
    """
  end

  defp load_counts(actor) do
    case Execution.list_work_items(actor: actor) do
      {:ok, work_items} ->
        %{
          total: length(work_items),
          open:
            Enum.count(
              work_items,
              &(&1.status in [:backlog, :ready, :in_progress, :blocked, :review])
            ),
          blocked: Enum.count(work_items, &(&1.status == :blocked)),
          due_soon: Enum.count(work_items, &due_soon?/1)
        }

      {:error, _} ->
        %{total: 0, open: 0, blocked: 0, due_soon: 0}
    end
  end

  defp due_soon?(%{status: status, due_on: %Date{} = due_on})
       when status in [:backlog, :ready, :in_progress, :blocked, :review] do
    diff = Date.diff(due_on, Date.utc_today())
    diff >= 0 and diff <= 7
  end

  defp due_soon?(_work_item), do: false

  defp work_item_index_loads do
    [
      :status_variant,
      :priority_variant,
      :child_work_item_count,
      :assignment_count,
      owner_team_member: [],
      project: []
    ]
  end
end
