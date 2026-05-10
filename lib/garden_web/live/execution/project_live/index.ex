defmodule GnomeGardenWeb.Execution.ProjectLive.Index do
  use GnomeGardenWeb, :live_view
  use Cinder.UrlSync

  import GnomeGardenWeb.Execution.Helpers

  alias GnomeGarden.Execution

  @impl true
  def mount(_params, _session, socket) do
    counts = load_counts(socket.assigns.current_user)

    {:ok,
     socket
     |> assign(:page_title, "Projects")
     |> assign(:project_count, counts.total)
     |> assign(:active_count, counts.active)
     |> assign(:hybrid_count, counts.hybrid)
     |> assign(:budget_total, counts.budget_total)}
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
        Projects
        <:subtitle>
          Delivery projects created from active agreements and tracked with explicit lifecycle states.
        </:subtitle>
        <:actions>
          <.button navigate={~p"/execution/work-items"}>
            Work Items
          </.button>
          <.button navigate={~p"/commercial/agreements"}>
            Agreements
          </.button>
          <.button navigate={~p"/execution/projects/new"} variant="primary">
            New Project
          </.button>
        </:actions>
      </.page_header>

      <div class="grid gap-4 md:grid-cols-4">
        <.stat_card
          title="Projects"
          value={Integer.to_string(@project_count)}
          description="Planned, active, and completed delivery efforts tracked in execution."
          icon="hero-wrench-screwdriver"
        />
        <.stat_card
          title="Active"
          value={Integer.to_string(@active_count)}
          description="Projects currently ready, active, or on hold in the delivery pipeline."
          icon="hero-check-badge"
          accent="sky"
        />
        <.stat_card
          title="Hybrid Delivery"
          value={Integer.to_string(@hybrid_count)}
          description="Projects spanning both physical and digital execution work."
          icon="hero-arrows-right-left"
          accent="amber"
        />
        <.stat_card
          title="Budgeted"
          value={format_amount(@budget_total)}
          description="Aggregate budget carried across the current project portfolio."
          icon="hero-banknotes"
          accent="rose"
        />
      </div>

      <Cinder.collection
        id="projects-table"
        resource={GnomeGarden.Execution.Project}
        actor={@current_user}
        url_state={@url_state}
        theme={GnomeGardenWeb.CinderTheme}
        page_size={25}
        query_opts={[
          load: [
            :status_variant,
            :priority_variant,
            :assignment_count,
            :work_item_count,
            :work_order_count,
            :material_usage_count,
            organization: [],
            agreement: []
          ]
        ]}
        click={fn row -> JS.navigate(~p"/execution/projects/#{row}") end}
      >
        <:col :let={project} field="name" search sort label="Project">
          <div class="space-y-1">
            <div class="font-medium text-base-content">{project.name}</div>
            <p class="text-sm text-base-content/50">
              {project.code || "No code"} · {format_date(project.target_end_on)}
            </p>
          </div>
        </:col>

        <:col :let={project} label="Organization">
          {(project.organization && project.organization.name) || "-"}
        </:col>

        <:col :let={project} label="Scope">
          <div class="space-y-2">
            <.tag color={:zinc}>{format_atom(project.project_type)}</.tag>
            <.tag color={:emerald}>{format_atom(project.delivery_mode)}</.tag>
            <.status_badge status={project.priority_variant}>
              {format_atom(project.priority)}
            </.status_badge>
          </div>
        </:col>

        <:col :let={project} label="Counts">
          <div class="space-y-1">
            <p>{project.work_item_count || 0} work items</p>
            <p class="text-xs text-base-content/40">
              {project.work_order_count || 0} work orders · {project.assignment_count || 0} assignments
            </p>
          </div>
        </:col>

        <:col :let={project} field="status" sort label="Status">
          <.status_badge status={project.status_variant}>
            {format_atom(project.status)}
          </.status_badge>
        </:col>

        <:empty>
          <.empty_state
            icon="hero-wrench-screwdriver"
            title="No projects yet"
            description="Create a project directly, or seed one from an active commercial agreement."
          >
            <:action>
              <.button navigate={~p"/execution/projects/new"} variant="primary">
                Create Project
              </.button>
            </:action>
          </.empty_state>
        </:empty>
      </Cinder.collection>
    </.page>
    """
  end

  defp load_counts(actor) do
    case Execution.list_projects(actor: actor) do
      {:ok, projects} ->
        %{
          total: length(projects),
          active: Enum.count(projects, &(&1.status in [:ready, :active, :on_hold])),
          hybrid: Enum.count(projects, &(&1.delivery_mode == :hybrid)),
          budget_total: sum_amounts(projects, :budget_amount)
        }

      {:error, _} ->
        %{total: 0, active: 0, hybrid: 0, budget_total: nil}
    end
  end
end
