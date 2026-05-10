defmodule GnomeGardenWeb.Execution.AssignmentLive.Index do
  use GnomeGardenWeb, :live_view
  use Cinder.UrlSync

  import GnomeGardenWeb.Execution.Helpers

  alias GnomeGarden.Execution

  @impl true
  def mount(_params, _session, socket) do
    counts = load_counts(socket.assigns.current_user)

    {:ok,
     socket
     |> assign(:page_title, "Assignments")
     |> assign(:assignment_count, counts.total)
     |> assign(:confirmed_count, counts.confirmed)
     |> assign(:in_progress_count, counts.in_progress)
     |> assign(:onsite_count, counts.onsite)}
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
        Assignments
        <:subtitle>
          Coordinate scheduled execution across project work, service dispatch, and hybrid delivery without losing ownership.
        </:subtitle>
        <:actions>
          <.button navigate={~p"/execution/work-items"}>
            Work Items
          </.button>
          <.button navigate={~p"/execution/assignments/new"} variant="primary">
            New Assignment
          </.button>
        </:actions>
      </.page_header>

      <div class="grid gap-4 md:grid-cols-4">
        <.stat_card
          title="Assignments"
          value={Integer.to_string(@assignment_count)}
          description="Scheduled work allocations across delivery, service, and coordination."
          icon="hero-calendar-days"
        />
        <.stat_card
          title="Confirmed"
          value={Integer.to_string(@confirmed_count)}
          description="Assignments that are staffed and ready to happen when scheduled."
          icon="hero-check-badge"
          accent="sky"
        />
        <.stat_card
          title="In Progress"
          value={Integer.to_string(@in_progress_count)}
          description="Assignments actively consuming execution capacity right now."
          icon="hero-play"
          accent="amber"
        />
        <.stat_card
          title="Onsite"
          value={Integer.to_string(@onsite_count)}
          description="Assignments that require field presence instead of fully remote execution."
          icon="hero-map-pin"
          accent="rose"
        />
      </div>

      <Cinder.collection
        id="assignments-table"
        resource={GnomeGarden.Execution.Assignment}
        actor={@current_user}
        url_state={@url_state}
        theme={GnomeGardenWeb.CinderTheme}
        page_size={25}
        query_opts={[load: assignment_index_loads()]}
        click={fn row -> JS.navigate(~p"/execution/assignments/#{row}") end}
      >
        <:col :let={assignment} field="title" search sort label="Assignment">
          <div class="space-y-1">
            <div class="font-medium text-base-content">{assignment.title}</div>
            <p class="text-sm text-base-content/50">
              {format_atom(assignment.assignment_type)} · {format_atom(assignment.location_mode)}
            </p>
          </div>
        </:col>

        <:col :let={assignment} label="Context">
          <div class="space-y-1">
            <p>{(assignment.project && assignment.project.name) || "-"}</p>
            <p class="text-xs text-base-content/40">
              {(assignment.work_item && assignment.work_item.title) ||
                (assignment.work_order && assignment.work_order.title) ||
                "No work item/work order"}
            </p>
          </div>
        </:col>

        <:col :let={assignment} label="Assignee">
          {display_team_member(assignment.assigned_team_member)}
        </:col>

        <:col :let={assignment} field="scheduled_start_at" sort label="Schedule">
          <div class="space-y-1">
            <p>{format_datetime(assignment.scheduled_start_at)}</p>
            <p class="text-xs text-base-content/40">
              {format_minutes(assignment.planned_minutes)}
            </p>
          </div>
        </:col>

        <:col :let={assignment} field="status" sort label="Status">
          <.status_badge status={assignment.status_variant}>
            {format_atom(assignment.status)}
          </.status_badge>
        </:col>

        <:empty>
          <.empty_state
            icon="hero-calendar-days"
            title="No assignments yet"
            description="Create assignments from work items or work orders when work needs a real owner and calendar slot."
          >
            <:action>
              <.button navigate={~p"/execution/assignments/new"} variant="primary">
                Create Assignment
              </.button>
            </:action>
          </.empty_state>
        </:empty>
      </Cinder.collection>
    </.page>
    """
  end

  defp load_counts(actor) do
    case Execution.list_assignments(actor: actor) do
      {:ok, assignments} ->
        %{
          total: length(assignments),
          confirmed: Enum.count(assignments, &(&1.status == :confirmed)),
          in_progress: Enum.count(assignments, &(&1.status == :in_progress)),
          onsite: Enum.count(assignments, &(&1.location_mode == :onsite))
        }

      {:error, _} ->
        %{total: 0, confirmed: 0, in_progress: 0, onsite: 0}
    end
  end

  defp assignment_index_loads do
    [
      :status_variant,
      assigned_team_member: [],
      project: [],
      work_item: [],
      work_order: []
    ]
  end
end
