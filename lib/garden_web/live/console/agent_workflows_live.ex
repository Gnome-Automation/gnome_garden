defmodule GnomeGardenWeb.Console.AgentWorkflowsLive do
  use GnomeGardenWeb, :live_view

  alias GnomeGarden.Agents
  alias GnomeGarden.Agents.WorkflowRunners.ProcurementSourceInspection

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Agent Workflows")
     |> assign(:workflow_counts, empty_workflow_counts())
     |> stream(:workflows, [], reset: true)
     |> load_workflows()}
  end

  @impl true
  def handle_event("ensure_procurement_inspection_workflow", _params, socket) do
    case ProcurementSourceInspection.ensure_definition(actor: socket.assigns.current_user) do
      {:ok, _workflow} ->
        {:noreply,
         socket
         |> load_workflows()
         |> put_flash(:info, "Procurement inspection workflow is published.")}

      {:error, error} ->
        {:noreply, put_flash(socket, :error, error_message(error))}
    end
  end

  def handle_event("transition_workflow", %{"id" => id, "transition" => transition}, socket) do
    actor = socket.assigns.current_user

    with {:ok, workflow} <- Agents.get_agent_workflow_definition(id, actor: actor),
         {:ok, transitioned} <- transition_workflow(workflow, transition, actor) do
      {:noreply,
       socket
       |> load_workflows()
       |> put_flash(
         :info,
         "#{transition_label(transitioned.status)} workflow #{workflow_label(transitioned)}."
       )}
    else
      {:error, error} ->
        {:noreply, put_flash(socket, :error, error_message(error))}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.page class="pb-8">
      <.page_header eyebrow="Console">
        Agent Workflows
        <:subtitle>
          Govern versioned AshLua workflow definitions, risk level, and allowed Ash action/tool surfaces.
        </:subtitle>
        <:actions>
          <.link navigate={~p"/console/agents/evals"} class="btn btn-sm">
            Evaluations
          </.link>
          <button
            type="button"
            class="btn btn-sm btn-primary"
            phx-click="ensure_procurement_inspection_workflow"
          >
            Ensure Inspection Workflow
          </button>
        </:actions>
      </.page_header>

      <div class="grid gap-2 sm:grid-cols-2 xl:grid-cols-5">
        <.stat_card
          title="Definitions"
          value={to_string(@workflow_counts.total)}
          description="All workflow definition versions."
          icon="hero-command-line"
          accent="sky"
        />
        <.stat_card
          title="Published"
          value={to_string(@workflow_counts.published)}
          description="Versions available to runners."
          icon="hero-check-circle"
          accent="emerald"
        />
        <.stat_card
          title="Drafts"
          value={to_string(@workflow_counts.draft + @workflow_counts.validated)}
          description="Draft or validated versions not yet published."
          icon="hero-pencil-square"
          accent="amber"
        />
        <.stat_card
          title="Disabled"
          value={to_string(@workflow_counts.disabled)}
          description="Previously published versions held from execution."
          icon="hero-pause-circle"
          accent="amber"
        />
        <.stat_card
          title="High Risk"
          value={to_string(@workflow_counts.high_risk)}
          description="High or critical risk definitions."
          icon="hero-exclamation-triangle"
          accent={if @workflow_counts.high_risk > 0, do: "rose", else: "emerald"}
        />
      </div>

      <.section
        title="Workflow Definitions"
        description="Inspect allowed domains, actions, tools, schemas, and lifecycle status before workflows are used by runners."
        compact
      >
        <div id="agent-workflows" phx-update="stream" class="divide-y divide-base-content/10">
          <div
            id="agent-workflows-empty"
            class="hidden only:block px-4 py-8 text-center text-sm text-base-content/50"
          >
            No workflow definitions yet.
          </div>

          <article
            :for={{row_id, workflow} <- @streams.workflows}
            id={row_id}
            class="grid gap-4 px-4 py-4 xl:grid-cols-[minmax(0,1fr)_auto] xl:items-start"
          >
            <div class="min-w-0 space-y-3">
              <div class="flex flex-wrap items-center gap-2">
                <h3 class="font-semibold text-base-content">{workflow.name}</h3>
                <span class="badge badge-ghost badge-sm">{workflow.key} v{workflow.version}</span>
                <span class={workflow_status_badge(workflow.status)}>
                  {format_atom(workflow.status)}
                </span>
                <span class={risk_badge(workflow.risk_level)}>
                  {format_atom(workflow.risk_level)}
                </span>
              </div>

              <p :if={workflow.description} class="text-sm leading-5 text-base-content/60">
                {workflow.description}
              </p>

              <div class="grid gap-3 text-xs leading-5 text-base-content/60 lg:grid-cols-3">
                <div>
                  <p class="font-semibold text-base-content/70">Allowed Domains</p>
                  <p>{list_label(workflow.allowed_domains)}</p>
                </div>
                <div>
                  <p class="font-semibold text-base-content/70">Allowed Tools</p>
                  <p>{list_label(workflow.allowed_tools)}</p>
                </div>
                <div>
                  <p class="font-semibold text-base-content/70">Allowed Actions</p>
                  <p>{list_label(workflow.allowed_actions)}</p>
                </div>
              </div>

              <div class="grid gap-3 text-xs leading-5 text-base-content/60 lg:grid-cols-3">
                <p>
                  <span class="font-semibold text-base-content/70">Input:</span> {map_label(
                    workflow.input_schema
                  )}
                </p>
                <p>
                  <span class="font-semibold text-base-content/70">Output:</span> {map_label(
                    workflow.output_schema
                  )}
                </p>
                <p>
                  <span class="font-semibold text-base-content/70">Updated:</span> {format_datetime(
                    workflow.updated_at
                  )}
                </p>
              </div>
            </div>

            <div class="flex flex-wrap gap-2 xl:max-w-64 xl:justify-end">
              <button
                :if={workflow.status == :draft}
                type="button"
                class="btn btn-sm"
                phx-click="transition_workflow"
                phx-value-id={workflow.id}
                phx-value-transition="validate"
              >
                Validate
              </button>
              <button
                :if={workflow.status == :validated}
                type="button"
                class="btn btn-sm btn-primary"
                phx-click="transition_workflow"
                phx-value-id={workflow.id}
                phx-value-transition="publish"
              >
                Publish
              </button>
              <button
                :if={workflow.status == :published}
                type="button"
                class="btn btn-sm"
                phx-click="transition_workflow"
                phx-value-id={workflow.id}
                phx-value-transition="disable"
              >
                Disable
              </button>
              <button
                :if={workflow.status in [:draft, :validated, :disabled]}
                type="button"
                class="btn btn-sm text-red-600 hover:bg-red-50 dark:text-red-300 dark:hover:bg-red-500/10"
                phx-click="transition_workflow"
                phx-value-id={workflow.id}
                phx-value-transition="archive"
              >
                Archive
              </button>
            </div>
          </article>
        </div>
      </.section>
    </.page>
    """
  end

  defp load_workflows(socket) do
    workflows = list_workflows()

    socket
    |> assign(:workflow_counts, workflow_counts(workflows))
    |> stream(:workflows, workflows, reset: true)
  end

  defp list_workflows do
    case Agents.list_agent_workflow_definitions(query: [load: [:status_variant]]) do
      {:ok, workflows} ->
        Enum.sort_by(workflows, &{&1.key, -1 * (&1.version || 0)})

      {:error, _error} ->
        []
    end
  end

  defp workflow_counts(workflows) do
    %{
      total: length(workflows),
      draft: Enum.count(workflows, &(&1.status == :draft)),
      validated: Enum.count(workflows, &(&1.status == :validated)),
      published: Enum.count(workflows, &(&1.status == :published)),
      disabled: Enum.count(workflows, &(&1.status == :disabled)),
      high_risk: Enum.count(workflows, &(&1.risk_level in [:high, :critical]))
    }
  end

  defp empty_workflow_counts do
    %{total: 0, draft: 0, validated: 0, published: 0, disabled: 0, high_risk: 0}
  end

  defp transition_workflow(workflow, "validate", actor),
    do: Agents.validate_agent_workflow_definition(workflow, actor: actor)

  defp transition_workflow(workflow, "publish", actor),
    do: Agents.publish_agent_workflow_definition(workflow, actor: actor)

  defp transition_workflow(workflow, "disable", actor),
    do: Agents.disable_agent_workflow_definition(workflow, actor: actor)

  defp transition_workflow(workflow, "archive", actor),
    do: Agents.archive_agent_workflow_definition(workflow, actor: actor)

  defp transition_workflow(_workflow, transition, _actor),
    do: {:error, "Unsupported workflow transition #{transition}."}

  defp transition_label(:validated), do: "Validated"
  defp transition_label(:published), do: "Published"
  defp transition_label(:disabled), do: "Disabled"
  defp transition_label(:archived), do: "Archived"
  defp transition_label(status), do: format_atom(status)

  defp workflow_label(workflow), do: "#{workflow.key} v#{workflow.version}"

  defp workflow_status_badge(:draft), do: "badge badge-ghost badge-sm"
  defp workflow_status_badge(:validated), do: "badge badge-info badge-sm"
  defp workflow_status_badge(:published), do: "badge badge-success badge-sm"
  defp workflow_status_badge(:disabled), do: "badge badge-warning badge-sm"
  defp workflow_status_badge(:archived), do: "badge badge-ghost badge-sm"
  defp workflow_status_badge(_status), do: "badge badge-ghost badge-sm"

  defp risk_badge(:low), do: "badge badge-success badge-sm"
  defp risk_badge(:medium), do: "badge badge-info badge-sm"
  defp risk_badge(:high), do: "badge badge-warning badge-sm"
  defp risk_badge(:critical), do: "badge badge-error badge-sm"
  defp risk_badge(_risk), do: "badge badge-ghost badge-sm"

  defp list_label(nil), do: "-"
  defp list_label([]), do: "-"
  defp list_label(values) when is_list(values), do: Enum.join(values, ", ")
  defp list_label(value), do: to_string(value)

  defp map_label(nil), do: "-"
  defp map_label(map) when map == %{}, do: "-"

  defp map_label(map) when is_map(map) do
    map
    |> Enum.sort_by(fn {key, _value} -> to_string(key) end)
    |> Enum.take(4)
    |> Enum.map(fn {key, value} -> "#{key}: #{scalar_label(value)}" end)
    |> Enum.join(" · ")
  end

  defp scalar_label(value) when is_map(value), do: "#{map_size(value)} fields"
  defp scalar_label(values) when is_list(values), do: "#{length(values)} items"
  defp scalar_label(value) when is_atom(value), do: format_atom(value)
  defp scalar_label(value), do: to_string(value)

  defp format_atom(nil), do: "-"
  defp format_atom(value), do: value |> to_string() |> String.replace("_", " ")

  defp format_datetime(nil), do: "-"
  defp format_datetime(datetime), do: Calendar.strftime(datetime, "%b %d, %H:%M")

  defp error_message(error) when is_binary(error), do: error

  defp error_message(%{__struct__: _} = error) do
    Exception.message(error)
  rescue
    Protocol.UndefinedError -> inspect(error)
  end

  defp error_message(error), do: inspect(error)
end
