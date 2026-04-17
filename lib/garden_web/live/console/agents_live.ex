defmodule GnomeGardenWeb.Console.AgentsLive do
  use GnomeGardenWeb, :live_view

  alias GnomeGarden.Agents
  alias GnomeGarden.Agents.AgentTracker
  alias GnomeGarden.Agents.DefaultDeployments
  alias GnomeGarden.Agents.DeploymentRunner
  alias GnomeGarden.Agents.TemplateCatalog
  alias GnomeGarden.Agents.Templates
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
     |> assign(:runtime_count, 0)
     |> assign(:last_refreshed_at, nil)
     |> stream(:deployments, [], reset: true)
     |> stream(:recent_runs, [], reset: true)
     |> stream(:runtime_instances, [], reset: true)
     |> load_console()}
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
         |> put_flash(:info, "Started run #{short_id(run.id)}.")}

      {:error, error} ->
        {:noreply, put_flash(socket, :error, error_message(error))}
    end
  end

  def handle_event("pause_deployment", %{"deployment_id" => deployment_id}, socket) do
    case Agents.get_agent_deployment(deployment_id, actor: socket.assigns.current_user) do
      {:ok, deployment} ->
        case Ash.update(deployment, %{}, action: :pause, actor: socket.assigns.current_user) do
          {:ok, _deployment} ->
            {:noreply,
             socket
             |> load_console()
             |> put_flash(:info, "Deployment paused.")}

          {:error, error} ->
            {:noreply, put_flash(socket, :error, error_message(error))}
        end

      {:error, error} ->
        {:noreply, put_flash(socket, :error, error_message(error))}
    end
  end

  def handle_event("resume_deployment", %{"deployment_id" => deployment_id}, socket) do
    case Agents.get_agent_deployment(deployment_id, actor: socket.assigns.current_user) do
      {:ok, deployment} ->
        case Ash.update(deployment, %{}, action: :resume, actor: socket.assigns.current_user) do
          {:ok, _deployment} ->
            {:noreply,
             socket
             |> load_console()
             |> put_flash(:info, "Deployment resumed.")}

          {:error, error} ->
            {:noreply, put_flash(socket, :error, error_message(error))}
        end

      {:error, error} ->
        {:noreply, put_flash(socket, :error, error_message(error))}
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

  def handle_event("bootstrap_defaults", _params, socket) do
    result = DefaultDeployments.ensure_defaults()

    message =
      case result.created do
        [] -> "Default deployments already exist."
        created -> "Bootstrapped default deployments: #{Enum.join(created, ", ")}."
      end

    {:noreply,
     socket
     |> load_console()
     |> put_flash(:info, message)}
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
    <div class="space-y-8">
      <section class="grid gap-4 md:grid-cols-3">
        <div class="rounded-2xl border border-zinc-200 bg-white p-5 shadow-sm dark:border-zinc-800 dark:bg-zinc-900">
          <p class="text-sm font-medium text-zinc-500 dark:text-zinc-400">Deployments</p>
          <p class="mt-2 text-3xl font-semibold tracking-tight text-zinc-900 dark:text-white">
            {@deployment_count}
          </p>
          <p class="mt-2 text-sm text-zinc-600 dark:text-zinc-400">
            Configured agent instances with ownership, schedule, and scope.
          </p>
        </div>

        <div class="rounded-2xl border border-zinc-200 bg-white p-5 shadow-sm dark:border-zinc-800 dark:bg-zinc-900">
          <p class="text-sm font-medium text-zinc-500 dark:text-zinc-400">Active Runs</p>
          <p class="mt-2 text-3xl font-semibold tracking-tight text-zinc-900 dark:text-white">
            {@active_run_count}
          </p>
          <p class="mt-2 text-sm text-zinc-600 dark:text-zinc-400">
            Durable run records still pending or executing.
          </p>
        </div>

        <div class="rounded-2xl border border-zinc-200 bg-white p-5 shadow-sm dark:border-zinc-800 dark:bg-zinc-900">
          <p class="text-sm font-medium text-zinc-500 dark:text-zinc-400">Live Runtime</p>
          <p class="mt-2 text-3xl font-semibold tracking-tight text-zinc-900 dark:text-white">
            {@runtime_count}
          </p>
          <p class="mt-2 text-sm text-zinc-600 dark:text-zinc-400">
            Running Jido instances on this node, keyed by `AgentRun`.
          </p>
        </div>
      </section>

      <section class="rounded-2xl border border-zinc-200 bg-white shadow-sm dark:border-zinc-800 dark:bg-zinc-900">
        <div class="flex items-center justify-between border-b border-zinc-200 px-5 py-4 dark:border-zinc-800">
          <div>
            <h2 class="text-lg font-semibold text-zinc-900 dark:text-white">Deployments</h2>
            <p class="text-sm text-zinc-600 dark:text-zinc-400">
              Launch, pause, and resume configured agent deployments.
            </p>
          </div>

          <div class="flex items-center gap-2">
            <button type="button" class="btn btn-sm" phx-click="bootstrap_defaults">
              Bootstrap Defaults
            </button>

            <.link navigate={~p"/console/agents/deployments/new"} class="btn btn-sm btn-primary gap-1">
              <.icon name="hero-plus" class="size-4" /> New Deployment
            </.link>
          </div>
        </div>

        <div class="overflow-x-auto">
          <table class="min-w-full divide-y divide-zinc-200 text-sm dark:divide-zinc-800">
            <thead class="bg-zinc-50 text-left dark:bg-zinc-950/50">
              <tr>
                <th class="px-5 py-3 font-medium text-zinc-500 dark:text-zinc-400">Deployment</th>
                <th class="px-5 py-3 font-medium text-zinc-500 dark:text-zinc-400">Template</th>
                <th class="px-5 py-3 font-medium text-zinc-500 dark:text-zinc-400">Visibility</th>
                <th class="px-5 py-3 font-medium text-zinc-500 dark:text-zinc-400">Owner</th>
                <th class="px-5 py-3 font-medium text-zinc-500 dark:text-zinc-400">Runs</th>
                <th class="px-5 py-3 font-medium text-zinc-500 dark:text-zinc-400">Last Run</th>
                <th class="px-5 py-3 font-medium text-zinc-500 dark:text-zinc-400">State</th>
                <th class="px-5 py-3 font-medium text-zinc-500 dark:text-zinc-400">Actions</th>
              </tr>
            </thead>
            <tbody id="agent-deployments" phx-update="stream" class="divide-y divide-zinc-200 dark:divide-zinc-800">
              <tr class="hidden only:table-row">
                <td colspan="8" class="px-5 py-8 text-center text-sm text-zinc-500 dark:text-zinc-400">
                  No deployments yet. Create one from the deployment form to start running configured agents.
                </td>
              </tr>

              <tr :for={{row_id, deployment} <- @streams.deployments} id={row_id}>
                <td class="px-5 py-4">
                  <div class="font-medium text-zinc-900 dark:text-white">{deployment.name}</div>
                  <div :if={deployment.description} class="mt-1 max-w-md text-xs text-zinc-500 dark:text-zinc-400">
                    {deployment.description}
                  </div>
                </td>
                <td class="px-5 py-4 text-zinc-700 dark:text-zinc-300">
                  {deployment.agent && deployment.agent.name}
                </td>
                <td class="px-5 py-4">
                  <span class={visibility_badge(deployment.visibility)}>{format_atom(deployment.visibility)}</span>
                </td>
                <td class="px-5 py-4 text-zinc-700 dark:text-zinc-300">
                  {owner_label(deployment)}
                </td>
                <td class="px-5 py-4 text-zinc-700 dark:text-zinc-300">
                  <span class="font-medium">{deployment.run_count || 0}</span>
                  <span class="text-zinc-500 dark:text-zinc-400">
                    ({deployment.active_run_count || 0} active)
                  </span>
                </td>
                <td class="px-5 py-4 text-zinc-700 dark:text-zinc-300">
                  {format_datetime(deployment.last_run_at)}
                </td>
                <td class="px-5 py-4">
                  <div class="flex items-center gap-2">
                    <span class={enabled_badge(deployment.enabled)}>
                      {if(deployment.enabled, do: "enabled", else: "paused")}
                    </span>
                    <span :if={deployment.last_run_state} class={run_state_badge(deployment.last_run_state)}>
                      {format_atom(deployment.last_run_state)}
                    </span>
                  </div>
                </td>
                <td class="px-5 py-4">
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

                    <.link navigate={~p"/console/agents/deployments/#{deployment.id}/edit"} class="btn btn-sm">
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
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </section>

      <section class="grid gap-8 xl:grid-cols-[1.4fr_1fr]">
        <div class="rounded-2xl border border-zinc-200 bg-white shadow-sm dark:border-zinc-800 dark:bg-zinc-900">
          <div class="border-b border-zinc-200 px-5 py-4 dark:border-zinc-800">
            <h2 class="text-lg font-semibold text-zinc-900 dark:text-white">Recent Runs</h2>
            <p class="text-sm text-zinc-600 dark:text-zinc-400">
              Deployment-centric run history with quick links into live details.
            </p>
          </div>

          <div class="overflow-x-auto">
            <table class="min-w-full divide-y divide-zinc-200 text-sm dark:divide-zinc-800">
              <thead class="bg-zinc-50 text-left dark:bg-zinc-950/50">
                <tr>
                  <th class="px-5 py-3 font-medium text-zinc-500 dark:text-zinc-400">Task</th>
                  <th class="px-5 py-3 font-medium text-zinc-500 dark:text-zinc-400">Deployment</th>
                  <th class="px-5 py-3 font-medium text-zinc-500 dark:text-zinc-400">Requested By</th>
                  <th class="px-5 py-3 font-medium text-zinc-500 dark:text-zinc-400">Started</th>
                  <th class="px-5 py-3 font-medium text-zinc-500 dark:text-zinc-400">State</th>
                  <th class="px-5 py-3 font-medium text-zinc-500 dark:text-zinc-400">Outputs</th>
                  <th class="px-5 py-3 font-medium text-zinc-500 dark:text-zinc-400">Actions</th>
                </tr>
              </thead>
              <tbody id="agent-runs" phx-update="stream" class="divide-y divide-zinc-200 dark:divide-zinc-800">
                <tr class="hidden only:table-row">
                  <td colspan="7" class="px-5 py-8 text-center text-sm text-zinc-500 dark:text-zinc-400">
                    No AgentRun records yet.
                  </td>
                </tr>

                <tr :for={{row_id, run} <- @streams.recent_runs} id={row_id}>
                  <td class="px-5 py-4">
                    <div class="font-medium text-zinc-900 dark:text-white">{run.task}</div>
                    <div :if={run.agent} class="mt-1 text-xs text-zinc-500 dark:text-zinc-400">
                      Template: {run.agent.name}
                    </div>
                  </td>
                  <td class="px-5 py-4 text-zinc-700 dark:text-zinc-300">
                    {run.deployment && run.deployment.name}
                  </td>
                  <td class="px-5 py-4 text-zinc-700 dark:text-zinc-300">
                    {requester_label(run)}
                  </td>
                  <td class="px-5 py-4 text-zinc-700 dark:text-zinc-300">
                    {format_datetime(run.started_at || run.inserted_at)}
                  </td>
                  <td class="px-5 py-4">
                    <div class="flex items-center gap-2">
                      <span class={run_state_badge(run.state)}>{format_atom(run.state)}</span>
                      <span :if={run.completed_at} class="text-xs text-zinc-500 dark:text-zinc-400">
                        done {format_datetime(run.completed_at)}
                      </span>
                    </div>
                  </td>
                  <td class="px-5 py-4 text-zinc-700 dark:text-zinc-300">
                    <div class="font-medium">{run.output_count || 0}</div>
                    <div :if={(run.output_count || 0) > 0} class="mt-1 text-xs text-zinc-500 dark:text-zinc-400">
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
        </div>

        <div class="space-y-8">
          <section class="rounded-2xl border border-zinc-200 bg-white shadow-sm dark:border-zinc-800 dark:bg-zinc-900">
            <div class="flex items-center justify-between border-b border-zinc-200 px-5 py-4 dark:border-zinc-800">
              <div>
                <h2 class="text-lg font-semibold text-zinc-900 dark:text-white">Runtime Cache</h2>
                <p class="text-sm text-zinc-600 dark:text-zinc-400">
                  `AgentTracker` is live cache only. Durable history lives in `AgentRun`.
                </p>
              </div>

              <span class="text-xs text-zinc-500 dark:text-zinc-400">
                Refreshed {format_datetime(@last_refreshed_at)}
              </span>
            </div>

            <div id="runtime-instances" phx-update="stream" class="divide-y divide-zinc-200 dark:divide-zinc-800">
              <div class="hidden only:block px-5 py-8 text-center text-sm text-zinc-500 dark:text-zinc-400">
                No active runtime instances on this node.
              </div>

              <div
                :for={{row_id, runtime} <- @streams.runtime_instances}
                id={row_id}
                class="px-5 py-4"
              >
                <div class="flex items-start justify-between gap-4">
                  <div>
                    <p class="font-medium text-zinc-900 dark:text-white">{runtime.id}</p>
                    <p class="mt-1 text-sm text-zinc-600 dark:text-zinc-400">
                      Template {runtime.template || "unknown"}<span :if={runtime.task}> · {runtime.task}</span>
                    </p>
                  </div>

                  <div class="flex items-center gap-2">
                    <span class={tracker_status_badge(runtime.status)}>{format_atom(runtime.status)}</span>
                    <.link
                      :if={runtime.detail_href}
                      navigate={runtime.detail_href}
                      class="text-xs font-medium text-emerald-600 hover:text-emerald-500 dark:text-emerald-400 dark:hover:text-emerald-300"
                    >
                      View run
                    </.link>
                  </div>
                </div>

                <div class="mt-3 grid grid-cols-3 gap-3 text-xs text-zinc-500 dark:text-zinc-400">
                  <div>
                    <p class="uppercase tracking-wide">Tokens</p>
                    <p class="mt-1 text-sm font-medium text-zinc-900 dark:text-white">{runtime.tokens}</p>
                  </div>
                  <div>
                    <p class="uppercase tracking-wide">Tool Calls</p>
                    <p class="mt-1 text-sm font-medium text-zinc-900 dark:text-white">{runtime.tool_calls}</p>
                  </div>
                  <div>
                    <p class="uppercase tracking-wide">Last Tool</p>
                    <p class="mt-1 truncate text-sm font-medium text-zinc-900 dark:text-white">
                      {runtime.last_tool || "-"}
                    </p>
                  </div>
                </div>
              </div>
            </div>
          </section>

          <section class="rounded-2xl border border-zinc-200 bg-white shadow-sm dark:border-zinc-800 dark:bg-zinc-900">
            <div class="border-b border-zinc-200 px-5 py-4 dark:border-zinc-800">
              <h2 class="text-lg font-semibold text-zinc-900 dark:text-white">Template Registry</h2>
              <p class="text-sm text-zinc-600 dark:text-zinc-400">
                Worker types currently registered in `GnomeGarden.Agents.Templates`.
              </p>
            </div>

            <div class="divide-y divide-zinc-200 dark:divide-zinc-800">
              <div :for={template <- @templates} class="px-5 py-4">
                <div class="flex items-center justify-between gap-4">
                  <div>
                    <p class="font-medium text-zinc-900 dark:text-white">{template.name}</p>
                    <p class="mt-1 text-sm text-zinc-600 dark:text-zinc-400">{template.description}</p>
                  </div>

                  <span class="badge badge-ghost badge-sm">{template.model}</span>
                </div>
              </div>
            </div>
          </section>
        </div>
      </section>

      <.modal
        :if={@deployment_pending_delete}
        id="delete-deployment-modal"
        on_cancel={JS.push("cancel_delete_deployment")}
      >
        <:title>Delete Deployment?</:title>

        <div class="space-y-4">
          <div>
            <p class="font-medium text-zinc-900 dark:text-white">{@deployment_pending_delete.name}</p>
            <p class="mt-1 text-sm text-zinc-600 dark:text-zinc-400">
              Template {(@deployment_pending_delete.agent && @deployment_pending_delete.agent.name) || "-"}
            </p>
          </div>

          <div class="rounded-xl bg-red-50 px-4 py-3 text-sm text-red-700 dark:bg-red-500/10 dark:text-red-300">
            This permanently removes the deployment and all of its run history.
          </div>

          <div class="text-sm text-zinc-600 dark:text-zinc-400">
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
    </div>
    """
  end

  defp load_console(socket) do
    deployments = Agents.list_console_agent_deployments!()
    active_runs = Agents.list_active_agent_runs!()
    recent_runs = Agents.list_recent_agent_runs!(@recent_run_limit)
    runtime_instances = runtime_instances()

    socket
    |> assign(:deployment_count, length(deployments))
    |> assign(:active_run_count, length(active_runs))
    |> assign(:runtime_count, length(runtime_instances))
    |> assign(:last_refreshed_at, DateTime.utc_now())
    |> stream(:deployments, deployments, reset: true)
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

  defp requester_label(%{requested_by_user: %{email: email}}), do: email
  defp requester_label(_run), do: "System"

  defp output_breakdown(run) do
    [
      run.procurement_source_output_count && run.procurement_source_output_count > 0 &&
        "#{run.procurement_source_output_count} sources",
      run.bid_output_count && run.bid_output_count > 0 && "#{run.bid_output_count} bids"
    ]
    |> Enum.reject(&(!&1))
    |> Enum.join(" · ")
  end

  defp owner_label(%{visibility: :system}), do: "System"
  defp owner_label(%{owner_user: %{email: email}}), do: email
  defp owner_label(_deployment), do: "Unassigned"

  defp ensure_deletable(%{active_run_count: count}) when is_integer(count) and count > 0 do
    {:error, "Cancel active runs before deleting this deployment."}
  end

  defp ensure_deletable(_deployment), do: :ok

  defp short_id(id), do: String.slice(id, 0, 8)

  defp error_message(%Ash.Error.Invalid{} = error), do: Ash.Error.to_error_class(error) |> inspect()
  defp error_message(error) when is_exception(error), do: Exception.message(error)
  defp error_message(error) when is_binary(error), do: error
  defp error_message(error), do: inspect(error)

  defp format_atom(nil), do: "-"
  defp format_atom(atom), do: atom |> to_string() |> String.replace("_", " ")

  defp format_datetime(nil), do: "-"
  defp format_datetime(datetime), do: Calendar.strftime(datetime, "%b %d, %H:%M")

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
