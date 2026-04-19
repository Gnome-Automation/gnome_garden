defmodule GnomeGardenWeb.Execution.ProjectLive.Index do
  use GnomeGardenWeb, :live_view

  import GnomeGardenWeb.Execution.Helpers

  alias GnomeGarden.Execution

  @impl true
  def mount(_params, _session, socket) do
    projects = load_projects(socket.assigns.current_user)

    {:ok,
     socket
     |> assign(:page_title, "Projects")
     |> assign(:project_count, length(projects))
     |> assign(:active_count, Enum.count(projects, &(&1.status in [:ready, :active, :on_hold])))
     |> assign(:hybrid_count, Enum.count(projects, &(&1.delivery_mode == :hybrid)))
     |> assign(:budget_total, sum_amounts(projects, :budget_amount))
     |> stream(:projects, projects)}
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
          <.button navigate={~p"/commercial/agreements"}>
            <.icon name="hero-document-check" class="size-4" /> Agreements
          </.button>
          <.button navigate={~p"/execution/projects/new"} variant="primary">
            <.icon name="hero-plus" class="size-4" /> New Project
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

      <.section
        title="Delivery Portfolio"
        description="Projects should stay connected to agreements, accounts, and execution counts instead of becoming disconnected task boards."
        compact
        body_class="p-0"
      >
        <div :if={@project_count == 0} class="p-6 sm:p-7">
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
        </div>

        <div :if={@project_count > 0} class="overflow-x-auto">
          <table class="min-w-full divide-y divide-zinc-200 text-sm dark:divide-white/10">
            <thead class="bg-zinc-50 dark:bg-white/[0.03]">
              <tr>
                <th class="px-5 py-3 text-left font-medium text-zinc-500 dark:text-zinc-400">
                  Project
                </th>
                <th class="px-5 py-3 text-left font-medium text-zinc-500 dark:text-zinc-400">
                  Organization
                </th>
                <th class="px-5 py-3 text-left font-medium text-zinc-500 dark:text-zinc-400">
                  Scope
                </th>
                <th class="px-5 py-3 text-left font-medium text-zinc-500 dark:text-zinc-400">
                  Counts
                </th>
                <th class="px-5 py-3 text-left font-medium text-zinc-500 dark:text-zinc-400">
                  Status
                </th>
              </tr>
            </thead>
            <tbody
              id="projects"
              phx-update="stream"
              class="divide-y divide-zinc-200 dark:divide-white/10"
            >
              <tr :for={{dom_id, project} <- @streams.projects} id={dom_id}>
                <td class="px-5 py-4 align-top">
                  <div class="space-y-1">
                    <.link
                      navigate={~p"/execution/projects/#{project}"}
                      class="font-medium text-zinc-900 hover:text-emerald-600 dark:text-white"
                    >
                      {project.name}
                    </.link>
                    <p class="text-sm text-zinc-500 dark:text-zinc-400">
                      {project.code || "No code"} · {format_date(project.target_end_on)}
                    </p>
                  </div>
                </td>
                <td class="px-5 py-4 align-top text-zinc-600 dark:text-zinc-300">
                  {(project.organization && project.organization.name) || "-"}
                </td>
                <td class="px-5 py-4 align-top text-zinc-600 dark:text-zinc-300">
                  <div class="space-y-2">
                    <.tag color={:zinc}>{format_atom(project.project_type)}</.tag>
                    <.tag color={:emerald}>{format_atom(project.delivery_mode)}</.tag>
                    <.status_badge status={project.priority_variant}>
                      {format_atom(project.priority)}
                    </.status_badge>
                  </div>
                </td>
                <td class="px-5 py-4 align-top text-zinc-600 dark:text-zinc-300">
                  <div class="space-y-1">
                    <p>{project.work_item_count || 0} work items</p>
                    <p class="text-xs text-zinc-400 dark:text-zinc-500">
                      {project.work_order_count || 0} work orders · {project.assignment_count || 0} assignments
                    </p>
                  </div>
                </td>
                <td class="px-5 py-4 align-top">
                  <.status_badge status={project.status_variant}>
                    {format_atom(project.status)}
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

  defp load_projects(actor) do
    case Execution.list_projects(
           actor: actor,
           query: [sort: [target_end_on: :asc, inserted_at: :desc]],
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
         ) do
      {:ok, projects} -> projects
      {:error, error} -> raise "failed to load projects: #{inspect(error)}"
    end
  end
end
