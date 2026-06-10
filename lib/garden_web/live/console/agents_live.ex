defmodule GnomeGardenWeb.Console.AgentsLive do
  use GnomeGardenWeb, :live_view
  use Cinder.UrlSync

  import Cinder.Refresh

  alias GnomeGarden.Agents
  alias GnomeGarden.Agents.AgentEvalRunner
  alias GnomeGarden.Agents.AgentEvalSweepHealth
  alias GnomeGarden.Agents.AgentTracker
  alias GnomeGarden.Agents.DeploymentRunner
  alias GnomeGarden.Agents.TemplateCatalog
  alias GnomeGarden.Agents.Templates
  alias GnomeGarden.Operations
  alias GnomeGarden.Procurement
  alias Phoenix.LiveView.JS

  @recent_run_limit 12
  @refresh_interval_ms 3_000

  @impl true
  def mount(_params, _session, socket) do
    _ = TemplateCatalog.sync_templates()

    if connected?(socket) do
      :timer.send_interval(@refresh_interval_ms, :refresh_console)
    end

    {:ok,
     socket
     |> assign(:page_title, "Agents Console")
     |> assign(:templates, template_cards())
     |> assign(:deployment_pending_delete, nil)
     |> assign(:deployment_count, 0)
     |> assign(:active_run_count, 0)
     |> assign(:scheduled_deployment_count, 0)
     |> assign(:manual_deployment_count, 0)
     |> assign(:attention_deployment_count, 0)
     |> assign(:agent_health, empty_agent_health())
     |> assign(:runtime_count, 0)
     |> assign(:last_refreshed_at, nil)
     |> stream(:recent_runs, [], reset: true)
     |> stream(:runtime_instances, [], reset: true)
     |> load_console()}
  end

  @impl true
  def handle_params(params, uri, socket) do
    socket = Cinder.UrlSync.handle_params(params, uri, socket)
    {:noreply, socket}
  end

  @impl true
  def handle_info(:refresh_console, socket) do
    {:noreply, load_console(socket)}
  end

  @impl true
  def handle_event("run_now", %{"deployment_id" => deployment_id}, socket) do
    case DeploymentRunner.launch_manual_run(deployment_id, actor: socket.assigns.current_user) do
      {:ok, run} ->
        {:noreply,
         socket
         |> load_console()
         |> refresh_table("agent-deployments-table")
         |> put_flash(:info, "Started run #{short_id(run.id)}.")}

      {:error, error} ->
        {:noreply, put_flash(socket, :error, error_message(error))}
    end
  end

  def handle_event("pause_deployment", %{"deployment_id" => deployment_id}, socket) do
    with {:ok, deployment} <-
           Agents.get_agent_deployment(deployment_id, actor: socket.assigns.current_user),
         {:ok, _deployment} <-
           Agents.pause_agent_deployment(deployment, actor: socket.assigns.current_user) do
      {:noreply,
       socket
       |> load_console()
       |> refresh_table("agent-deployments-table")
       |> put_flash(:info, "Deployment paused.")}
    else
      {:error, error} -> {:noreply, put_flash(socket, :error, error_message(error))}
    end
  end

  def handle_event("resume_deployment", %{"deployment_id" => deployment_id}, socket) do
    with {:ok, deployment} <-
           Agents.get_agent_deployment(deployment_id, actor: socket.assigns.current_user),
         {:ok, _deployment} <-
           Agents.resume_agent_deployment(deployment, actor: socket.assigns.current_user) do
      {:noreply,
       socket
       |> load_console()
       |> refresh_table("agent-deployments-table")
       |> put_flash(:info, "Deployment resumed.")}
    else
      {:error, error} -> {:noreply, put_flash(socket, :error, error_message(error))}
    end
  end

  def handle_event("cancel_run", %{"run_id" => run_id}, socket) do
    case DeploymentRunner.cancel_run(run_id, actor: socket.assigns.current_user) do
      {:ok, _run} ->
        {:noreply,
         socket
         |> load_console()
         |> put_flash(:info, "Run cancelled.")}

      {:error, error} ->
        {:noreply, put_flash(socket, :error, error_message(error))}
    end
  end

  def handle_event("confirm_delete_deployment", %{"deployment_id" => deployment_id}, socket) do
    case Agents.get_agent_deployment(deployment_id, load: [:agent, :run_count, :active_run_count]) do
      {:ok, deployment} ->
        {:noreply, assign(socket, :deployment_pending_delete, deployment)}

      {:error, error} ->
        {:noreply, put_flash(socket, :error, error_message(error))}
    end
  end

  def handle_event("cancel_delete_deployment", _params, socket) do
    {:noreply, assign(socket, :deployment_pending_delete, nil)}
  end

  def handle_event("delete_deployment", %{"deployment_id" => deployment_id}, socket) do
    with {:ok, deployment} <-
           Agents.get_agent_deployment(deployment_id, load: [:run_count, :active_run_count]),
         :ok <- ensure_deletable(deployment),
         :ok <- Agents.delete_agent_deployment(deployment, actor: socket.assigns.current_user) do
      {:noreply,
       socket
       |> assign(:deployment_pending_delete, nil)
       |> load_console()
       |> refresh_table("agent-deployments-table")
       |> put_flash(:info, "Deployment deleted.")}
    else
      {:error, error} ->
        {:noreply,
         socket
         |> assign(:deployment_pending_delete, nil)
         |> put_flash(:error, error_message(error))}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.page class="pb-8">
      <.page_header eyebrow="Console">
        Agents Console
        <:subtitle>
          Orchestrate templates, deployments, durable runs, and runtime cache from one operational workspace.
        </:subtitle>
        <:actions>
          <.link navigate={~p"/console/agents/deployments/new"} class="btn btn-sm btn-primary gap-1">
            New Deployment
          </.link>
        </:actions>
      </.page_header>

      <div class="grid gap-4 sm:grid-cols-2 xl:grid-cols-4">
        <.stat_card
          title="Running Now"
          value={to_string(@active_run_count)}
          description="Runs currently pending or executing. Use Recent Runs to view or cancel them."
          icon="hero-bolt"
          accent="sky"
        />
        <.stat_card
          title="Scheduled"
          value={to_string(@scheduled_deployment_count)}
          description="Enabled deployments that run automatically from the Run Mode column."
          icon="hero-calendar-days"
          accent="emerald"
        />
        <.stat_card
          title="Manual"
          value={to_string(@manual_deployment_count)}
          description="Deployments that only run from Run now or another workflow."
          icon="hero-cursor-arrow-rays"
          accent="amber"
        />
        <.stat_card
          title="Needs Attention"
          value={to_string(@attention_deployment_count)}
          description="Enabled deployments whose last run failed."
          icon="hero-exclamation-triangle"
          accent="rose"
        />
      </div>

      <.section
        title="Agent Operating Health"
        description="Governance and execution signals across workflows, memory, learning, credentials, and recent failures."
      >
        <div class="grid gap-2 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-7">
          <.stat_card
            title="Failed Runs"
            value={to_string(@agent_health.failed_runs)}
            description="Recent failed AgentRun records."
            icon="hero-exclamation-triangle"
            accent="rose"
          />
          <.stat_card
            title="Memory Review"
            value={to_string(@agent_health.pending_memory)}
            description="Pending memory blocks and entries."
            icon="hero-archive-box"
            accent="amber"
          />
          <.stat_card
            title="Learning Review"
            value={to_string(@agent_health.pending_learning)}
            description="Pending learning recommendations."
            icon="hero-light-bulb"
            accent="amber"
          />
          <.stat_card
            title="Eval Coverage"
            value={eval_coverage_value(@agent_health)}
            description={eval_coverage_description(@agent_health)}
            icon="hero-clipboard-document-check"
            accent={eval_health_accent(@agent_health)}
          />
          <.stat_card
            title="Eval Sweeps"
            value={sweep_health_value(@agent_health.sweep_health)}
            description={sweep_health_description(@agent_health.sweep_health)}
            icon="hero-arrow-path"
            accent={sweep_health_accent(@agent_health.sweep_health)}
          />
          <.stat_card
            title="Workflows"
            value={to_string(@agent_health.published_workflows)}
            description="Published workflow definitions."
            icon="hero-command-line"
            accent="sky"
          />
          <.stat_card
            title="Credentials"
            value={to_string(@agent_health.credential_blockers)}
            description="Approved sources blocked by login."
            icon="hero-key"
            accent="rose"
          />
        </div>

        <div class="mt-3 flex flex-wrap gap-2">
          <.link navigate={~p"/console/agents/attention"} class="btn btn-sm btn-primary">
            Agent Attention
          </.link>
          <.link navigate={~p"/operations/review"} class="btn btn-sm">
            Review Queue
          </.link>
          <.link navigate={~p"/console/agents/evals"} class="btn btn-sm">
            Evaluations
          </.link>
          <.link navigate={~p"/console/agents/workflows"} class="btn btn-sm">
            Workflows
          </.link>
          <.link navigate={~p"/acquisition/sources?bucket=credentials_needed"} class="btn btn-sm">
            Credential Blockers
          </.link>
        </div>
      </.section>

      <section class="rounded-2xl border border-zinc-200 bg-white shadow-sm dark:border-zinc-800 dark:bg-zinc-900">
        <div class="border-b border-zinc-200 px-5 py-4 dark:border-zinc-800">
          <div>
            <h2 class="text-lg font-semibold text-base-content">Deployments</h2>
            <p class="text-sm text-base-content/60">
              {@deployment_count} configured. Click a row to edit schedule and scope.
            </p>
          </div>
        </div>

        <Cinder.collection
          id="agent-deployments-table"
          resource={GnomeGarden.Agents.AgentDeployment}
          action={:console}
          actor={@current_user}
          url_state={@url_state}
          theme={GnomeGardenWeb.CinderTheme}
          page_size={25}
          click={
            fn deployment -> JS.navigate(~p"/console/agents/deployments/#{deployment.id}/edit") end
          }
        >
          <:col
            :let={deployment}
            field="name"
            search
            sort
            label="Deployment"
            class="min-w-72 max-w-md whitespace-normal"
          >
            <div class="font-medium text-base-content">{deployment.name}</div>
            <div
              :if={deployment.description}
              class="mt-1 text-xs leading-5 break-words text-base-content/50"
            >
              {deployment.description}
            </div>
          </:col>
          <:col :let={deployment} label="Template">
            {deployment.agent && deployment.agent.name}
          </:col>
          <:col :let={deployment} field="visibility" sort label="Visibility">
            <span class={visibility_badge(deployment.visibility)}>
              {format_atom(deployment.visibility)}
            </span>
          </:col>
          <:col :let={deployment} label="Owner">
            {owner_label(deployment)}
          </:col>
          <:col :let={deployment} label="Runs">
            <span class="font-medium">{deployment.run_count || 0}</span>
            <span class="text-base-content/50">
              ({deployment.active_run_count || 0} active)
            </span>
          </:col>
          <:col :let={deployment} label="Last Run">
            {format_datetime(deployment.last_run_at)}
          </:col>
          <:col :let={deployment} field="schedule" sort label="Run Mode">
            <div class="space-y-1.5">
              <span class={schedule_badge(deployment.schedule)}>
                {schedule_mode_label(deployment.schedule)}
              </span>
              <div class="text-xs leading-5 text-base-content/60">
                {schedule_label(deployment.schedule)}
              </div>
              <div
                :if={scheduled?(deployment.schedule)}
                class="text-xs font-medium leading-5 text-base-content/80"
              >
                Next: {next_schedule_label(deployment.schedule)}
              </div>
            </div>
          </:col>
          <:col :let={deployment} field="enabled" sort label="State">
            <div class="flex items-center gap-2">
              <span class={enabled_badge(deployment.enabled)}>
                {if(deployment.enabled, do: "enabled", else: "paused")}
              </span>
              <span
                :if={deployment.last_run_state}
                class={run_state_badge(deployment.last_run_state)}
              >
                {format_atom(deployment.last_run_state)}
              </span>
            </div>
          </:col>
          <:col :let={deployment} label="Actions">
            <div class="flex flex-wrap gap-2">
              <button
                :if={deployment.enabled}
                type="button"
                class="btn btn-sm btn-primary"
                phx-click="run_now"
                phx-value-deployment_id={deployment.id}
              >
                Run now
              </button>

              <button
                :if={deployment.enabled}
                type="button"
                class="btn btn-sm"
                phx-click="pause_deployment"
                phx-value-deployment_id={deployment.id}
              >
                Pause
              </button>

              <button
                :if={!deployment.enabled}
                type="button"
                class="btn btn-sm"
                phx-click="resume_deployment"
                phx-value-deployment_id={deployment.id}
              >
                Resume
              </button>

              <.link
                navigate={~p"/console/agents/deployments/#{deployment.id}/edit"}
                class="btn btn-sm"
              >
                Edit
              </.link>

              <button
                type="button"
                class="btn btn-sm text-red-600 hover:bg-red-50 dark:text-red-300 dark:hover:bg-red-500/10"
                phx-click="confirm_delete_deployment"
                phx-value-deployment_id={deployment.id}
              >
                Delete
              </button>
            </div>
          </:col>

          <:empty>
            <div class="px-5 py-8 text-center text-sm text-base-content/50">
              No deployments yet. Create one from the deployment form to start running configured agents.
            </div>
          </:empty>
        </Cinder.collection>
      </section>

      <section class="rounded-2xl border border-zinc-200 bg-white shadow-sm dark:border-zinc-800 dark:bg-zinc-900">
        <div class="border-b border-zinc-200 px-5 py-4 dark:border-zinc-800">
          <h2 class="text-lg font-semibold text-base-content">Recent Runs</h2>
          <p class="text-sm text-base-content/60">
            Compact run history. Open a run for full prompt, output, and failure diagnostics.
          </p>
        </div>

        <div class="overflow-x-auto">
          <table class="min-w-full divide-y divide-zinc-200 text-sm dark:divide-zinc-800">
            <thead class="bg-zinc-50 text-left dark:bg-zinc-950/50">
              <tr>
                <th class="px-5 py-3 font-medium text-base-content/50">Deployment</th>
                <th class="px-5 py-3 font-medium text-base-content/50">Run</th>
                <th class="px-5 py-3 font-medium text-base-content/50">Requested By</th>
                <th class="px-5 py-3 font-medium text-base-content/50">Started</th>
                <th class="px-5 py-3 font-medium text-base-content/50">State</th>
                <th class="px-5 py-3 font-medium text-base-content/50">Outputs</th>
                <th class="px-5 py-3 font-medium text-base-content/50">Actions</th>
              </tr>
            </thead>
            <tbody
              id="agent-runs"
              phx-update="stream"
              class="divide-y divide-zinc-200 dark:divide-zinc-800"
            >
              <tr id="agent-runs-empty" class="hidden only:table-row">
                <td
                  colspan="7"
                  class="px-5 py-8 text-center text-sm text-base-content/50"
                >
                  No AgentRun records yet.
                </td>
              </tr>

              <tr :for={{row_id, run} <- @streams.recent_runs} id={row_id}>
                <td class="px-5 py-4 text-base-content/80">
                  <div class="font-medium text-base-content">
                    {(run.deployment && run.deployment.name) || "Unassigned"}
                  </div>
                  <div :if={run.agent} class="mt-1 text-xs text-base-content/50">
                    {run.agent.name}
                  </div>
                </td>
                <td class="max-w-md whitespace-normal px-5 py-4">
                  <div class="flex flex-wrap items-center gap-2">
                    <span class="badge badge-ghost badge-sm">{format_atom(run.run_kind)}</span>
                    <span class="font-medium text-base-content">#{short_id(run.id)}</span>
                  </div>
                  <div class="mt-1 text-xs leading-5 break-words text-base-content/55">
                    {task_preview(run.task)}
                  </div>
                </td>
                <td class="px-5 py-4 text-base-content/80">
                  {requester_label(run)}
                </td>
                <td class="px-5 py-4 text-base-content/80">
                  {format_datetime(run.started_at || run.inserted_at)}
                </td>
                <td class="px-5 py-4">
                  <div class="flex items-center gap-2">
                    <span class={run_state_badge(run.state)}>{format_atom(run.state)}</span>
                    <span :if={run.completed_at} class="text-xs text-base-content/50">
                      done {format_datetime(run.completed_at)}
                    </span>
                  </div>
                </td>
                <td class="px-5 py-4 text-base-content/80">
                  <div class="font-medium">{run.output_count || 0}</div>
                  <div
                    :if={(run.output_count || 0) > 0}
                    class="mt-1 text-xs text-base-content/50"
                  >
                    {output_breakdown(run)}
                  </div>
                </td>
                <td class="px-5 py-4">
                  <div class="flex flex-wrap gap-2">
                    <.link navigate={~p"/console/agents/runs/#{run.id}"} class="btn btn-sm">
                      View
                    </.link>

                    <button
                      :if={run.state in [:pending, :running]}
                      type="button"
                      class="btn btn-sm"
                      phx-click="cancel_run"
                      phx-value-run_id={run.id}
                    >
                      Cancel
                    </button>
                  </div>
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </section>

      <details class="rounded-2xl border border-zinc-200 bg-white shadow-sm dark:border-zinc-800 dark:bg-zinc-900">
        <summary class="flex cursor-pointer items-center justify-between gap-4 px-5 py-4">
          <div>
            <h2 class="text-lg font-semibold text-base-content">Diagnostics</h2>
            <p class="text-sm text-base-content/60">
              Runtime cache and template registry for debugging agent infrastructure.
            </p>
          </div>
          <span class="text-xs text-base-content/50">
            Refreshed {format_datetime(@last_refreshed_at)}
          </span>
        </summary>

        <div class="grid gap-8 border-t border-zinc-200 p-5 dark:border-zinc-800 xl:grid-cols-[1fr_1fr]">
          <section class="rounded-xl border border-zinc-200 dark:border-zinc-800">
            <div class="border-b border-zinc-200 px-5 py-4 dark:border-zinc-800">
              <h3 class="text-base font-semibold text-base-content">Runtime Cache</h3>
              <p class="text-sm text-base-content/60">
                Live `AgentTracker` entries on this node.
              </p>
            </div>

            <div
              id="runtime-instances"
              phx-update="stream"
              class="divide-y divide-zinc-200 dark:divide-zinc-800"
            >
              <div
                id="runtime-instances-empty"
                class="hidden only:block px-5 py-8 text-center text-sm text-base-content/50"
              >
                No active runtime instances on this node.
              </div>

              <div
                :for={{row_id, runtime} <- @streams.runtime_instances}
                id={row_id}
                class="px-5 py-4"
              >
                <div class="flex items-start justify-between gap-4">
                  <div>
                    <p class="font-medium text-base-content">{runtime.id}</p>
                    <p class="mt-1 text-sm text-base-content/60">
                      Template {runtime.template || "unknown"}<span :if={runtime.task}> · {task_preview(runtime.task)}</span>
                    </p>
                  </div>

                  <div class="flex items-center gap-2">
                    <span class={tracker_status_badge(runtime.status)}>
                      {format_atom(runtime.status)}
                    </span>
                    <.link
                      :if={runtime.detail_href}
                      navigate={runtime.detail_href}
                      class="text-xs font-medium text-emerald-600 hover:text-primary dark:hover:text-emerald-300"
                    >
                      View run
                    </.link>
                  </div>
                </div>

                <div class="mt-3 grid grid-cols-3 gap-3 text-xs text-base-content/50">
                  <div>
                    <p class="uppercase tracking-wide">Tokens</p>
                    <p class="mt-1 text-sm font-medium text-base-content">
                      {runtime.tokens}
                    </p>
                  </div>
                  <div>
                    <p class="uppercase tracking-wide">Tool Calls</p>
                    <p class="mt-1 text-sm font-medium text-base-content">
                      {runtime.tool_calls}
                    </p>
                  </div>
                  <div>
                    <p class="uppercase tracking-wide">Last Tool</p>
                    <p class="mt-1 truncate text-sm font-medium text-base-content">
                      {runtime.last_tool || "-"}
                    </p>
                  </div>
                </div>
              </div>
            </div>
          </section>

          <section class="rounded-xl border border-zinc-200 dark:border-zinc-800">
            <div class="border-b border-zinc-200 px-5 py-4 dark:border-zinc-800">
              <h3 class="text-base font-semibold text-base-content">Template Registry</h3>
              <p class="text-sm text-base-content/60">
                Worker types registered in `GnomeGarden.Agents.Templates`.
              </p>
            </div>

            <div class="divide-y divide-zinc-200 dark:divide-zinc-800">
              <div :for={template <- @templates} class="px-5 py-4">
                <div class="flex items-center justify-between gap-4">
                  <div>
                    <p class="font-medium text-base-content">{template.name}</p>
                    <p class="mt-1 text-sm text-base-content/60">
                      {template.description}
                    </p>
                  </div>

                  <span class="badge badge-ghost badge-sm">{template.model}</span>
                </div>
              </div>
            </div>
          </section>
        </div>
      </details>

      <.modal
        :if={@deployment_pending_delete}
        id="delete-deployment-modal"
        on_cancel={JS.push("cancel_delete_deployment")}
      >
        <:title>Delete Deployment?</:title>

        <div class="space-y-4">
          <div>
            <p class="font-medium text-base-content">{@deployment_pending_delete.name}</p>
            <p class="mt-1 text-sm text-base-content/60">
              Template {(@deployment_pending_delete.agent && @deployment_pending_delete.agent.name) ||
                "-"}
            </p>
          </div>

          <div class="rounded-xl bg-red-50 px-4 py-3 text-sm text-red-700 dark:bg-red-500/10 dark:text-red-300">
            This permanently removes the deployment and all of its run history.
          </div>

          <div class="text-sm text-base-content/60">
            Existing runs: {@deployment_pending_delete.run_count || 0}
          </div>

          <div
            :if={(@deployment_pending_delete.active_run_count || 0) > 0}
            class="rounded-xl bg-amber-50 px-4 py-3 text-sm text-amber-700 dark:bg-amber-500/10 dark:text-amber-300"
          >
            This deployment has active runs. Cancel them before deleting.
          </div>
        </div>

        <:actions>
          <.button type="button" phx-click="cancel_delete_deployment">Cancel</.button>
          <button
            type="button"
            class="rounded-md bg-red-600 px-3 py-2 text-sm font-semibold text-white shadow-xs hover:bg-red-500 disabled:cursor-not-allowed disabled:opacity-50"
            phx-click="delete_deployment"
            phx-value-deployment_id={@deployment_pending_delete.id}
            disabled={(@deployment_pending_delete.active_run_count || 0) > 0}
          >
            Delete Deployment
          </button>
        </:actions>
      </.modal>
    </.page>
    """
  end

  defp load_console(socket) do
    deployments = Agents.list_console_agent_deployments!()
    deployment_count = length(deployments)
    scheduled_deployment_count = Enum.count(deployments, &scheduled_deployment?/1)
    manual_deployment_count = Enum.count(deployments, &manual_deployment?/1)
    attention_deployment_count = Enum.count(deployments, &attention_deployment?/1)
    active_runs = Agents.list_active_agent_runs!()
    recent_runs = Agents.list_recent_agent_runs!(@recent_run_limit)
    runtime_instances = runtime_instances()
    agent_health = load_agent_health()

    socket
    |> assign(:deployment_count, deployment_count)
    |> assign(:active_run_count, length(active_runs))
    |> assign(:scheduled_deployment_count, scheduled_deployment_count)
    |> assign(:manual_deployment_count, manual_deployment_count)
    |> assign(:attention_deployment_count, attention_deployment_count)
    |> assign(:agent_health, agent_health)
    |> assign(:runtime_count, length(runtime_instances))
    |> assign(:last_refreshed_at, DateTime.utc_now())
    |> stream(:recent_runs, recent_runs, reset: true)
    |> stream(:runtime_instances, runtime_instances, reset: true)
  end

  defp runtime_instances do
    AgentTracker.list_agents()
    |> Enum.map(fn {id, entry} ->
      %{
        id: id,
        template: entry.template,
        task: entry.task,
        status: entry.status,
        tokens: entry.tokens,
        tool_calls: entry.tool_calls,
        last_tool: entry.last_tool,
        detail_href: runtime_detail_href(id)
      }
    end)
    |> Enum.filter(&(&1.status == :running))
  end

  defp load_agent_health do
    pending_memory =
      count_or_zero(&Operations.list_pending_memory_blocks/1) +
        count_or_zero(&Operations.list_pending_memory_entries/1)

    %{
      failed_runs: count_or_zero(fn opts -> Agents.list_recent_failed_agent_runs(10, opts) end),
      pending_memory: pending_memory,
      pending_learning: count_or_zero(&Operations.list_pending_learning_recommendations/1),
      eval_cases: eval_case_counts(),
      eval_runs: eval_run_counts(),
      sweep_health: sweep_health(),
      published_workflows: published_workflow_count(),
      credential_blockers:
        count_or_zero(&Procurement.list_credential_blocked_procurement_sources/1)
    }
  end

  defp empty_agent_health do
    %{
      failed_runs: 0,
      pending_memory: 0,
      pending_learning: 0,
      eval_cases: %{active: 0, runnable: 0},
      eval_runs: %{recent: 0, passed: 0, failed: 0, error: 0},
      sweep_health: empty_sweep_health(),
      published_workflows: 0,
      credential_blockers: 0
    }
  end

  defp sweep_health do
    case AgentEvalSweepHealth.summary() do
      {:ok, health} -> health
      {:error, _error} -> empty_sweep_health()
    end
  end

  defp empty_sweep_health do
    %{
      queued: 0,
      running: 0,
      latest: nil,
      next_scheduled_at: nil,
      status: :idle,
      stale?: false
    }
  end

  defp eval_run_counts do
    case Agents.list_recent_agent_eval_runs(20, query: [select: [:id, :status]]) do
      {:ok, runs} ->
        %{
          recent: length(runs),
          passed: Enum.count(runs, &(&1.status == :passed)),
          failed: Enum.count(runs, &(&1.status == :failed)),
          error: Enum.count(runs, &(&1.status == :error))
        }

      {:error, _error} ->
        %{recent: 0, passed: 0, failed: 0, error: 0}
    end
  end

  defp eval_case_counts do
    case Agents.list_active_agent_eval_cases(query: [select: [:id, :workflow_key, :input]]) do
      {:ok, cases} ->
        %{
          active: length(cases),
          runnable: Enum.count(cases, &AgentEvalRunner.runnable?/1)
        }

      {:error, _error} ->
        %{active: 0, runnable: 0}
    end
  end

  defp published_workflow_count do
    case Agents.list_agent_workflow_definitions(query: [select: [:id, :status]]) do
      {:ok, definitions} -> Enum.count(definitions, &(&1.status == :published))
      {:error, _error} -> 0
    end
  end

  defp count_or_zero(fun) do
    case fun.(query: [select: [:id]]) do
      {:ok, records} -> length(records)
      {:error, _error} -> 0
    end
  end

  defp eval_coverage_value(%{eval_cases: eval_cases}) do
    "#{Map.get(eval_cases, :runnable, 0)}/#{Map.get(eval_cases, :active, 0)}"
  end

  defp eval_coverage_description(%{eval_runs: eval_runs}) do
    failures = Map.get(eval_runs, :failed, 0) + Map.get(eval_runs, :error, 0)
    "Runnable active eval cases. Recent failures: #{failures}/#{Map.get(eval_runs, :recent, 0)}."
  end

  defp eval_health_accent(%{eval_cases: eval_cases, eval_runs: eval_runs}) do
    failures = Map.get(eval_runs, :failed, 0) + Map.get(eval_runs, :error, 0)
    active = Map.get(eval_cases, :active, 0)
    runnable = Map.get(eval_cases, :runnable, 0)

    cond do
      failures > 0 -> "rose"
      active > 0 and runnable == active -> "emerald"
      active > 0 -> "amber"
      true -> "sky"
    end
  end

  defp sweep_health_value(%{status: status}), do: format_atom(status)
  defp sweep_health_value(_health), do: "-"

  defp sweep_health_description(%{queued: queued, running: running, next_scheduled_at: next_at}) do
    "Queue #{queued}/#{running}. Next #{format_datetime(next_at)}."
  end

  defp sweep_health_description(_health), do: "Background eval sweep health."

  defp sweep_health_accent(%{status: :failed}), do: "rose"
  defp sweep_health_accent(%{status: :stale}), do: "amber"
  defp sweep_health_accent(%{status: :running}), do: "amber"
  defp sweep_health_accent(%{status: :queued}), do: "amber"
  defp sweep_health_accent(%{status: :healthy}), do: "emerald"
  defp sweep_health_accent(_health), do: "zinc"

  defp runtime_detail_href(runtime_id) do
    case Ecto.UUID.cast(runtime_id) do
      {:ok, run_id} -> ~p"/console/agents/runs/#{run_id}"
      :error -> nil
    end
  end

  defp template_cards do
    Templates.list()
    |> Enum.sort_by(fn {name, _config} -> name end)
    |> Enum.map(fn {name, config} ->
      %{
        name: name,
        description: config.description,
        model: config.model |> to_string() |> String.upcase()
      }
    end)
  end

  defp requester_label(%{requested_by_team_member: %{display_name: display_name}}),
    do: display_name

  defp requester_label(%{requested_by_user: %{email: email}}), do: email
  defp requester_label(_run), do: "System"

  defp output_breakdown(run) do
    [
      run.procurement_source_output_count && run.procurement_source_output_count > 0 &&
        "#{run.procurement_source_output_count} sources",
      run.bid_output_count && run.bid_output_count > 0 && "#{run.bid_output_count} bids",
      run.discovery_finding_output_count &&
        run.discovery_finding_output_count > 0 &&
        "#{run.discovery_finding_output_count} discovery findings"
    ]
    |> Enum.reject(&(!&1))
    |> Enum.join(" · ")
  end

  defp task_preview(nil), do: "-"

  defp task_preview(task) when is_binary(task) do
    cond do
      String.contains?(task, "DISCOVERY PROGRAM:") ->
        discovery_program_preview(task)

      String.starts_with?(task, "COMPANY PROFILE") ->
        "Commercial discovery run"

      String.starts_with?(task, "Run the BidScanner deployment") ->
        "Scheduled bid scanner sweep"

      String.starts_with?(task, "Run a procurement source scan") ->
        task |> compact_text() |> truncate_text(120)

      true ->
        task |> compact_text() |> truncate_text(110)
    end
  end

  defp task_preview(task), do: task |> inspect() |> task_preview()

  defp discovery_program_preview(task) do
    case Regex.run(~r/DISCOVERY PROGRAM:\s*([^\n]+)/, task) do
      [_, name] -> "Discovery program: #{String.trim(name)}"
      _ -> "Commercial discovery run"
    end
  end

  defp compact_text(text), do: text |> String.replace(~r/\s+/, " ") |> String.trim()

  defp truncate_text(text, limit) do
    if String.length(text) > limit do
      String.slice(text, 0, limit) <> "..."
    else
      text
    end
  end

  defp owner_label(%{visibility: :system}), do: "System"
  defp owner_label(%{owner_team_member: %{display_name: display_name}}), do: display_name
  defp owner_label(_deployment), do: "Unassigned"

  defp ensure_deletable(%{active_run_count: count}) when is_integer(count) and count > 0 do
    {:error, "Cancel active runs before deleting this deployment."}
  end

  defp ensure_deletable(_deployment), do: :ok

  defp short_id(id), do: String.slice(id, 0, 8)

  defp error_message(%Ash.Error.Invalid{} = error),
    do: Ash.Error.to_error_class(error) |> inspect()

  defp error_message(error) when is_exception(error), do: Exception.message(error)
  defp error_message(error) when is_binary(error), do: error
  defp error_message(error), do: inspect(error)

  defp format_atom(nil), do: "-"
  defp format_atom(atom), do: atom |> to_string() |> String.replace("_", " ")

  defp format_datetime(nil), do: "-"
  defp format_datetime(datetime), do: Calendar.strftime(datetime, "%b %d, %H:%M")

  defp scheduled_deployment?(%{enabled: true, schedule: schedule}), do: scheduled?(schedule)
  defp scheduled_deployment?(_deployment), do: false

  defp manual_deployment?(deployment), do: !scheduled_deployment?(deployment)

  defp attention_deployment?(%{enabled: true, last_run_state: :failed}), do: true
  defp attention_deployment?(_deployment), do: false

  defp scheduled?(schedule) when is_binary(schedule), do: String.trim(schedule) != ""
  defp scheduled?(_schedule), do: false

  defp schedule_badge(schedule) do
    if scheduled?(schedule), do: "badge badge-info badge-sm", else: "badge badge-ghost badge-sm"
  end

  defp schedule_mode_label(schedule) do
    if scheduled?(schedule), do: "Automatic", else: "Manual"
  end

  defp schedule_label(nil), do: "Run now only"
  defp schedule_label(""), do: "Run now only"
  defp schedule_label("0 14 * * 1,3,5"), do: "Mon, Wed, Fri at 14:00 UTC"
  defp schedule_label("0 16 * * 2"), do: "Tuesday at 16:00 UTC"
  defp schedule_label("0 15 * * 2,5"), do: "Tue, Fri at 15:00 UTC"
  defp schedule_label(schedule), do: "Cron: #{schedule}"

  defp next_schedule_label(schedule) do
    with schedule when is_binary(schedule) <- schedule,
         {:ok, expression} <- Oban.Plugins.Cron.parse(schedule),
         %DateTime{} = next_at <- Oban.Cron.Expression.next_at(expression, DateTime.utc_now()) do
      Calendar.strftime(next_at, "%b %d, %H:%M UTC")
    else
      :unknown -> "unknown"
      _ -> "invalid schedule"
    end
  end

  defp visibility_badge(:private), do: "badge badge-ghost badge-sm"
  defp visibility_badge(:shared), do: "badge badge-info badge-sm"
  defp visibility_badge(:system), do: "badge badge-secondary badge-sm"
  defp visibility_badge(_visibility), do: "badge badge-ghost badge-sm"

  defp enabled_badge(true), do: "badge badge-success badge-sm"
  defp enabled_badge(false), do: "badge badge-warning badge-sm"

  defp run_state_badge(:pending), do: "badge badge-ghost badge-sm"
  defp run_state_badge(:running), do: "badge badge-info badge-sm"
  defp run_state_badge(:completed), do: "badge badge-success badge-sm"
  defp run_state_badge(:failed), do: "badge badge-error badge-sm"
  defp run_state_badge(:cancelled), do: "badge badge-warning badge-sm"
  defp run_state_badge(:done), do: "badge badge-success badge-sm"
  defp run_state_badge(_state), do: "badge badge-ghost badge-sm"

  defp tracker_status_badge(:running), do: "badge badge-info badge-sm"
  defp tracker_status_badge(:done), do: "badge badge-success badge-sm"
  defp tracker_status_badge(:error), do: "badge badge-error badge-sm"
  defp tracker_status_badge(:cancelled), do: "badge badge-warning badge-sm"
  defp tracker_status_badge(status), do: run_state_badge(status)
end
