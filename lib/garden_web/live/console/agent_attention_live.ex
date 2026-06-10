defmodule GnomeGardenWeb.Console.AgentAttentionLive do
  use GnomeGardenWeb, :live_view

  alias GnomeGarden.Agents
  alias GnomeGarden.Operations

  @failed_run_limit 20
  @eval_run_limit 40
  @failure_trend_limit 100
  @refresh_interval_ms 5_000

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: :timer.send_interval(@refresh_interval_ms, :refresh_attention)

    {:ok,
     socket
     |> assign(:page_title, "Agent Attention")
     |> assign(:attention_counts, empty_counts())
     |> assign(:visible_counts, empty_counts())
     |> assign(:triage_filters, default_triage_filters())
     |> assign(:active_cluster, nil)
     |> assign(:failure_clusters, [])
     |> assign(:run_group_counts, [])
     |> assign(:eval_group_counts, [])
     |> assign(:run_tasks, %{})
     |> assign(:eval_tasks, %{})
     |> stream(:failed_runs, [], reset: true)
     |> stream(:eval_runs, [], reset: true)
     |> load_attention()}
  end

  @impl true
  def handle_info(:refresh_attention, socket) do
    {:noreply, load_attention(socket)}
  end

  @impl true
  def handle_event("filter_attention", %{"filters" => params}, socket) do
    {:noreply,
     socket
     |> assign(:triage_filters, normalize_filters(params))
     |> assign(:active_cluster, nil)
     |> load_attention()}
  end

  @impl true
  def handle_event("view_cluster", %{"cluster" => token}, socket) do
    {:noreply,
     socket
     |> assign(:active_cluster, token)
     |> load_attention()}
  end

  def handle_event("clear_cluster", _params, socket) do
    {:noreply,
     socket
     |> assign(:active_cluster, nil)
     |> load_attention()}
  end

  def handle_event("create_run_task", %{"id" => id}, socket) do
    with {:ok, run} <- fetch_agent_run(id),
         {:ok, task} <- create_agent_run_task(run, socket.assigns.current_user) do
      {:noreply,
       socket
       |> put_flash(:info, "Task created: #{task.title}")
       |> load_attention()}
    else
      {:existing, task} ->
        {:noreply,
         socket
         |> put_flash(:info, "Task already exists: #{task.title}")
         |> load_attention()}

      {:error, error} ->
        {:noreply, put_flash(socket, :error, task_error_message(error))}
    end
  end

  def handle_event("create_eval_task", %{"id" => id}, socket) do
    with {:ok, eval_run} <- fetch_eval_run(id),
         {:ok, task} <- create_eval_run_task(eval_run, socket.assigns.current_user) do
      {:noreply,
       socket
       |> put_flash(:info, "Task created: #{task.title}")
       |> load_attention()}
    else
      {:existing, task} ->
        {:noreply,
         socket
         |> put_flash(:info, "Task already exists: #{task.title}")
         |> load_attention()}

      {:error, error} ->
        {:noreply, put_flash(socket, :error, task_error_message(error))}
    end
  end

  def handle_event("create_cluster_tasks", %{"cluster" => token}, socket) do
    case Enum.find(socket.assigns.failure_clusters, &(&1.token == token)) do
      nil ->
        {:noreply, put_flash(socket, :error, "Could not find that failure cluster.")}

      cluster ->
        result = create_cluster_tasks(cluster.item_refs, socket.assigns.current_user)

        {:noreply,
         socket
         |> put_flash(cluster_task_flash_kind(result), cluster_task_message(result))
         |> load_attention()}
    end
  end

  def handle_event("resolve_task", %{"id" => id}, socket) do
    with {:ok, task} <- Operations.get_task(id, actor: socket.assigns.current_user),
         {:ok, resolved_task} <- resolve_task(task, socket.assigns.current_user) do
      {:noreply,
       socket
       |> put_flash(:info, "Task resolved: #{resolved_task.title}")
       |> load_attention()}
    else
      {:error, error} ->
        {:noreply, put_flash(socket, :error, "Could not resolve task: #{inspect(error)}")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.page class="pb-8">
      <.page_header eyebrow="Console">
        Agent Attention
        <:subtitle>
          Failed runtime work and failed evaluations that need operator follow-up.
        </:subtitle>
        <:actions>
          <.link navigate={~p"/console/agents/evals"} class="btn btn-sm">
            Evaluations
          </.link>
          <.link navigate={~p"/console/agents"} class="btn btn-sm">
            Agents Console
          </.link>
        </:actions>
      </.page_header>

      <div class="grid gap-2 sm:grid-cols-3">
        <.stat_card
          title="Failed Runs"
          value={to_string(@attention_counts.failed_runs)}
          description="Recent failed AgentRun records."
          icon="hero-exclamation-triangle"
          accent={if @attention_counts.failed_runs > 0, do: "rose", else: "emerald"}
        />
        <.stat_card
          title="Failed Evals"
          value={to_string(@attention_counts.failed_evals)}
          description="Recent failed or errored AgentEvalRun records."
          icon="hero-clipboard-document-check"
          accent={if @attention_counts.failed_evals > 0, do: "rose", else: "emerald"}
        />
        <.stat_card
          title="Retryable"
          value={to_string(@attention_counts.retryable_runs)}
          description="Failed runs classified as retryable."
          icon="hero-arrow-path"
          accent={if @attention_counts.retryable_runs > 0, do: "amber", else: "emerald"}
        />
      </div>

      <.section
        title="Failure Clusters"
        description="Grouped failures by surface, workflow, and failure reason."
        compact
      >
        <div class="divide-y divide-base-content/10">
          <div
            :if={@failure_clusters == []}
            class="px-4 py-8 text-center text-sm text-base-content/50"
          >
            No failure clusters in the current attention set.
          </div>

          <article
            :for={cluster <- @failure_clusters}
            class="grid gap-3 px-4 py-4 md:grid-cols-[minmax(0,1fr)_auto] md:items-center"
          >
            <div class="min-w-0 space-y-2">
              <div class="flex flex-wrap items-center gap-2">
                <span class={cluster_badge(cluster.source)}>{cluster.source}</span>
                <span class="badge badge-ghost badge-sm">{cluster.workflow}</span>
                <span class="badge badge-ghost badge-sm">{cluster.failure}</span>
              </div>
              <p class="text-sm leading-5 text-base-content/60">
                {cluster.count} recent item{plural_suffix(cluster.count)} · {task_need_label(
                  cluster.needs_task_count
                )} · {cluster.trend_count} in trend window · latest {format_datetime(
                  cluster.latest_at
                )}
              </p>
            </div>
            <div class="flex flex-wrap gap-2 md:justify-end">
              <span class={trend_badge(cluster.trend_label)}>{cluster.trend_label}</span>
              <span class="badge badge-error badge-sm">{cluster.count}</span>
              <span class={
                if cluster.needs_task_count > 0,
                  do: "badge badge-warning badge-sm",
                  else: "badge badge-success badge-sm"
              }>
                {task_need_label(cluster.needs_task_count)}
              </span>
              <button
                type="button"
                class="btn btn-sm"
                phx-click="view_cluster"
                phx-value-cluster={cluster.token}
                phx-value-kind={cluster.kind}
                phx-value-failure={cluster.failure}
              >
                View Cluster
              </button>
              <button
                :if={cluster.needs_task_count > 0}
                type="button"
                class="btn btn-sm btn-primary"
                phx-click="create_cluster_tasks"
                phx-value-cluster={cluster.token}
                phx-value-kind={cluster.kind}
                phx-value-failure={cluster.failure}
              >
                Create Missing Tasks
              </button>
            </div>
          </article>
        </div>
      </.section>

      <.section
        title="Triage Controls"
        description="Narrow the visible attention set and group it by the next operator decision."
        compact
      >
        <div
          :if={@active_cluster}
          class="mb-3 flex flex-wrap items-center justify-between gap-2 rounded-md border border-base-content/10 bg-base-200/60 px-3 py-2 text-sm"
        >
          <span class="text-base-content/70">
            Viewing cluster:
            <span class="font-medium text-base-content">{@active_cluster.workflow}</span>
            · {@active_cluster.failure} · Showing {@visible_counts.failed_runs} runs and {@visible_counts.failed_evals} evals
          </span>
          <button type="button" class="btn btn-sm" phx-click="clear_cluster">
            Clear Cluster
          </button>
        </div>

        <form
          id="agent-attention-filters"
          phx-change="filter_attention"
          class="grid gap-3 md:grid-cols-3"
        >
          <label class="space-y-1">
            <span class="text-xs font-medium uppercase tracking-wide text-base-content/50">
              Failed runs
            </span>
            <select
              name="filters[runs]"
              class="select select-bordered select-sm w-full"
              value={@triage_filters.runs}
            >
              <option value="all" selected={@triage_filters.runs == "all"}>All failed runs</option>
              <option value="retryable" selected={@triage_filters.runs == "retryable"}>
                Retryable
              </option>
              <option value="needs_task" selected={@triage_filters.runs == "needs_task"}>
                Needs task
              </option>
              <option value="has_task" selected={@triage_filters.runs == "has_task"}>
                Has task
              </option>
              <option value="resolved" selected={@triage_filters.runs == "resolved"}>
                Resolved
              </option>
            </select>
          </label>

          <label class="space-y-1">
            <span class="text-xs font-medium uppercase tracking-wide text-base-content/50">
              Failed evals
            </span>
            <select
              name="filters[evals]"
              class="select select-bordered select-sm w-full"
              value={@triage_filters.evals}
            >
              <option value="all" selected={@triage_filters.evals == "all"}>All failed evals</option>
              <option value="failed" selected={@triage_filters.evals == "failed"}>Failed</option>
              <option value="error" selected={@triage_filters.evals == "error"}>Errored</option>
              <option value="needs_task" selected={@triage_filters.evals == "needs_task"}>
                Needs task
              </option>
              <option value="has_task" selected={@triage_filters.evals == "has_task"}>
                Has task
              </option>
              <option value="resolved" selected={@triage_filters.evals == "resolved"}>
                Resolved
              </option>
            </select>
          </label>

          <label class="space-y-1">
            <span class="text-xs font-medium uppercase tracking-wide text-base-content/50">
              Group by
            </span>
            <select
              name="filters[group]"
              class="select select-bordered select-sm w-full"
              value={@triage_filters.group}
            >
              <option value="task_state" selected={@triage_filters.group == "task_state"}>
                Task state
              </option>
              <option value="failure" selected={@triage_filters.group == "failure"}>
                Failure type
              </option>
              <option value="workflow" selected={@triage_filters.group == "workflow"}>
                Workflow
              </option>
            </select>
          </label>
        </form>
      </.section>

      <div class="grid gap-3 xl:grid-cols-[1fr_1fr]">
        <.section
          title="Failed Agent Runs"
          description={
            "Showing #{@visible_counts.failed_runs} of #{@attention_counts.failed_runs} recent failed runs."
          }
          compact
        >
          <div
            :if={@run_group_counts != []}
            class="flex flex-wrap gap-2 border-b border-base-content/10 p-4"
          >
            <span
              :for={{label, count} <- @run_group_counts}
              class="badge badge-ghost badge-sm"
            >
              {label}: {count}
            </span>
          </div>

          <div
            id="agent-attention-runs"
            phx-update="stream"
            class="divide-y divide-base-content/10"
          >
            <div
              id="agent-attention-runs-empty"
              class="hidden only:block p-4"
            >
              <.empty_state
                icon="hero-check-circle"
                title="No failed runs"
                description="Recent runtime failures will appear here."
              />
            </div>

            <article :for={{row_id, run} <- @streams.failed_runs} id={row_id} class="space-y-3 p-4">
              <div class="flex flex-wrap items-center gap-2">
                <span class="badge badge-error badge-sm">failed</span>
                <span :if={run.failure_retryable} class="badge badge-warning badge-sm">
                  Retryable
                </span>
                <span class="badge badge-ghost badge-sm">{format_atom(run.run_kind)}</span>
                <span class="badge badge-ghost badge-sm">
                  {run_group_label(run, @run_tasks, @triage_filters.group)}
                </span>
                <span class="text-xs text-base-content/50">#{short_id(run.id)}</span>
              </div>

              <div class="space-y-1">
                <p class="font-semibold text-base-content">
                  {(run.deployment && run.deployment.name) || "Unassigned run"}
                </p>
                <p class="text-sm leading-5 text-base-content/60">
                  {run.failure_label || "Runtime failure"}
                </p>
                <p :if={run.error} class="line-clamp-2 text-xs leading-5 text-base-content/50">
                  {run.error}
                </p>
              </div>

              <div class="flex flex-wrap items-center gap-2">
                <span class="text-xs text-base-content/50">
                  {format_datetime(run.completed_at || run.inserted_at)}
                </span>
                <.link navigate={~p"/console/agents/runs/#{run.id}"} class="btn btn-sm">
                  Open Run
                </.link>
                <.link
                  :if={task = Map.get(@run_tasks, run.id)}
                  navigate={~p"/operations/tasks/#{task.id}"}
                  class={task_button_class(task)}
                >
                  {task_button_label(task)}
                </.link>
                <button
                  :if={resolvable_task?(Map.get(@run_tasks, run.id))}
                  type="button"
                  class="btn btn-sm btn-primary"
                  phx-click="resolve_task"
                  phx-value-id={Map.fetch!(@run_tasks, run.id).id}
                >
                  Mark Resolved
                </button>
                <button
                  :if={!Map.has_key?(@run_tasks, run.id)}
                  type="button"
                  class="btn btn-sm btn-primary"
                  phx-click="create_run_task"
                  phx-value-id={run.id}
                >
                  Create Task
                </button>
              </div>
            </article>
          </div>
        </.section>

        <.section
          title="Failed Evaluations"
          description={
            "Showing #{@visible_counts.failed_evals} of #{@attention_counts.failed_evals} recent failed or errored evals."
          }
          compact
        >
          <div
            :if={@eval_group_counts != []}
            class="flex flex-wrap gap-2 border-b border-base-content/10 p-4"
          >
            <span
              :for={{label, count} <- @eval_group_counts}
              class="badge badge-ghost badge-sm"
            >
              {label}: {count}
            </span>
          </div>

          <div
            id="agent-attention-evals"
            phx-update="stream"
            class="divide-y divide-base-content/10"
          >
            <div
              id="agent-attention-evals-empty"
              class="hidden only:block p-4"
            >
              <.empty_state
                icon="hero-check-circle"
                title="No failed evals"
                description="Failed or errored eval runs will appear here."
              />
            </div>

            <article :for={{row_id, eval_run} <- @streams.eval_runs} id={row_id} class="space-y-3 p-4">
              <div class="flex flex-wrap items-center gap-2">
                <span class={eval_status_badge(eval_run.status)}>{format_atom(eval_run.status)}</span>
                <span class="badge badge-ghost badge-sm">{workflow_label(eval_run)}</span>
                <span class="badge badge-ghost badge-sm">
                  {eval_group_label(eval_run, @eval_tasks, @triage_filters.group)}
                </span>
              </div>

              <div class="space-y-1">
                <p class="font-semibold text-base-content">{eval_case_name(eval_run)}</p>
                <p class="text-sm leading-5 text-base-content/60">
                  {eval_failure_summary(eval_run)}
                </p>
                <p :if={eval_run.reviewer_notes} class="text-xs leading-5 text-base-content/50">
                  {eval_run.reviewer_notes}
                </p>
              </div>

              <div class="flex flex-wrap items-center gap-2">
                <span class="text-xs text-base-content/50">
                  {format_datetime(eval_run.completed_at || eval_run.inserted_at)}
                </span>
                <.link
                  :if={eval_run.agent_run_id}
                  navigate={~p"/console/agents/runs/#{eval_run.agent_run_id}"}
                  class="btn btn-sm"
                >
                  Open Run
                </.link>
                <.link navigate={~p"/console/agents/evals"} class="btn btn-sm">
                  Open Evals
                </.link>
                <.link
                  :if={task = Map.get(@eval_tasks, eval_run.id)}
                  navigate={~p"/operations/tasks/#{task.id}"}
                  class={task_button_class(task)}
                >
                  {task_button_label(task)}
                </.link>
                <button
                  :if={resolvable_task?(Map.get(@eval_tasks, eval_run.id))}
                  type="button"
                  class="btn btn-sm btn-primary"
                  phx-click="resolve_task"
                  phx-value-id={Map.fetch!(@eval_tasks, eval_run.id).id}
                >
                  Mark Resolved
                </button>
                <button
                  :if={!Map.has_key?(@eval_tasks, eval_run.id)}
                  type="button"
                  class="btn btn-sm btn-primary"
                  phx-click="create_eval_task"
                  phx-value-id={eval_run.id}
                >
                  Create Task
                </button>
              </div>
            </article>
          </div>
        </.section>
      </div>
    </.page>
    """
  end

  defp load_attention(socket) do
    triage_filters = Map.get(socket.assigns, :triage_filters, default_triage_filters())
    failed_runs = list_failed_runs(@failed_run_limit)
    eval_runs = list_failed_eval_runs(@eval_run_limit)
    trend_runs = list_failed_runs(@failure_trend_limit)
    trend_eval_runs = list_failed_eval_runs(@failure_trend_limit)
    run_tasks = open_run_task_map(failed_runs, socket.assigns.current_user)
    eval_tasks = open_eval_task_map(eval_runs, socket.assigns.current_user)
    filtered_runs = filter_runs(failed_runs, run_tasks, triage_filters)
    filtered_eval_runs = filter_eval_runs(eval_runs, eval_tasks, triage_filters)

    failure_clusters =
      failure_clusters(
        filtered_runs,
        filtered_eval_runs,
        run_tasks,
        eval_tasks,
        trend_index(trend_runs, trend_eval_runs)
      )

    active_cluster = active_cluster(socket.assigns[:active_cluster], failure_clusters)

    {visible_runs, visible_eval_runs} =
      filter_by_active_cluster(filtered_runs, filtered_eval_runs, active_cluster)

    socket
    |> assign(:triage_filters, triage_filters)
    |> assign(:attention_counts, attention_counts(failed_runs, eval_runs))
    |> assign(:visible_counts, attention_counts(visible_runs, visible_eval_runs))
    |> assign(:run_tasks, run_tasks)
    |> assign(:eval_tasks, eval_tasks)
    |> assign(:active_cluster, active_cluster)
    |> assign(:failure_clusters, failure_clusters)
    |> assign(:run_group_counts, run_group_counts(visible_runs, run_tasks, triage_filters.group))
    |> assign(
      :eval_group_counts,
      eval_group_counts(visible_eval_runs, eval_tasks, triage_filters.group)
    )
    |> stream(:failed_runs, visible_runs, reset: true)
    |> stream(:eval_runs, visible_eval_runs, reset: true)
  end

  defp list_failed_runs(limit) do
    case Agents.list_recent_failed_agent_runs(limit,
           query: [load: [:failure_category]]
         ) do
      {:ok, runs} -> runs
      {:error, _error} -> []
    end
  end

  defp list_failed_eval_runs(limit) do
    case Agents.list_recent_agent_eval_runs(limit,
           query: [load: [:eval_case, :workflow_definition, :agent_run]]
         ) do
      {:ok, runs} -> Enum.filter(runs, &(&1.status in [:failed, :error]))
      {:error, _error} -> []
    end
  end

  defp attention_counts(failed_runs, eval_runs) do
    %{
      failed_runs: length(failed_runs),
      failed_evals: length(eval_runs),
      retryable_runs: Enum.count(failed_runs, & &1.failure_retryable)
    }
  end

  defp empty_counts, do: %{failed_runs: 0, failed_evals: 0, retryable_runs: 0}

  defp default_triage_filters, do: %{runs: "all", evals: "all", group: "task_state"}

  defp normalize_filters(params) do
    %{
      runs:
        normalize_choice(params["runs"], ~w(all retryable needs_task has_task resolved), "all"),
      evals:
        normalize_choice(
          params["evals"],
          ~w(all failed error needs_task has_task resolved),
          "all"
        ),
      group: normalize_choice(params["group"], ~w(task_state failure workflow), "task_state")
    }
  end

  defp normalize_choice(value, allowed, default) do
    if value in allowed, do: value, else: default
  end

  defp filter_runs(runs, run_tasks, %{runs: "retryable"}) do
    Enum.filter(runs, & &1.failure_retryable)
    |> sort_runs(run_tasks)
  end

  defp filter_runs(runs, run_tasks, %{runs: "needs_task"}) do
    Enum.reject(runs, &Map.has_key?(run_tasks, &1.id))
    |> sort_runs(run_tasks)
  end

  defp filter_runs(runs, run_tasks, %{runs: "has_task"}) do
    Enum.filter(runs, &Map.has_key?(run_tasks, &1.id))
    |> sort_runs(run_tasks)
  end

  defp filter_runs(runs, run_tasks, %{runs: "resolved"}) do
    Enum.filter(runs, &task_completed?(Map.get(run_tasks, &1.id)))
    |> sort_runs(run_tasks)
  end

  defp filter_runs(runs, run_tasks, _filters), do: sort_runs(runs, run_tasks)

  defp filter_eval_runs(eval_runs, eval_tasks, %{evals: "failed"}) do
    Enum.filter(eval_runs, &(&1.status == :failed))
    |> sort_eval_runs(eval_tasks)
  end

  defp filter_eval_runs(eval_runs, eval_tasks, %{evals: "error"}) do
    Enum.filter(eval_runs, &(&1.status == :error))
    |> sort_eval_runs(eval_tasks)
  end

  defp filter_eval_runs(eval_runs, eval_tasks, %{evals: "needs_task"}) do
    Enum.reject(eval_runs, &Map.has_key?(eval_tasks, &1.id))
    |> sort_eval_runs(eval_tasks)
  end

  defp filter_eval_runs(eval_runs, eval_tasks, %{evals: "has_task"}) do
    Enum.filter(eval_runs, &Map.has_key?(eval_tasks, &1.id))
    |> sort_eval_runs(eval_tasks)
  end

  defp filter_eval_runs(eval_runs, eval_tasks, %{evals: "resolved"}) do
    Enum.filter(eval_runs, &task_completed?(Map.get(eval_tasks, &1.id)))
    |> sort_eval_runs(eval_tasks)
  end

  defp filter_eval_runs(eval_runs, eval_tasks, _filters),
    do: sort_eval_runs(eval_runs, eval_tasks)

  defp sort_runs(runs, run_tasks) do
    Enum.sort_by(runs, fn run ->
      {task_sort_rank(Map.has_key?(run_tasks, run.id)), run.failure_category || :unknown,
       run.completed_at || run.inserted_at}
    end)
  end

  defp sort_eval_runs(eval_runs, eval_tasks) do
    Enum.sort_by(eval_runs, fn eval_run ->
      {task_sort_rank(Map.has_key?(eval_tasks, eval_run.id)), eval_run.status,
       eval_run.completed_at || eval_run.inserted_at}
    end)
  end

  defp task_sort_rank(false), do: 0
  defp task_sort_rank(true), do: 1

  defp run_group_counts(runs, run_tasks, group) do
    runs
    |> Enum.map(&run_group_label(&1, run_tasks, group))
    |> count_labels()
  end

  defp eval_group_counts(eval_runs, eval_tasks, group) do
    eval_runs
    |> Enum.map(&eval_group_label(&1, eval_tasks, group))
    |> count_labels()
  end

  defp count_labels(labels) do
    labels
    |> Enum.frequencies()
    |> Enum.sort_by(fn {label, _count} -> label end)
  end

  defp active_cluster(nil, _clusters), do: nil

  defp active_cluster(token, clusters) when is_binary(token) do
    Enum.find(clusters, &(&1.token == token))
  end

  defp active_cluster(%{token: token}, clusters), do: active_cluster(token, clusters)
  defp active_cluster(_other, _clusters), do: nil

  defp filter_by_active_cluster(runs, eval_runs, nil), do: {runs, eval_runs}

  defp filter_by_active_cluster(runs, eval_runs, cluster) do
    run_ids = cluster_item_ids(cluster, :run)
    eval_ids = cluster_item_ids(cluster, :eval)

    {
      Enum.filter(runs, &MapSet.member?(run_ids, &1.id)),
      Enum.filter(eval_runs, &MapSet.member?(eval_ids, &1.id))
    }
  end

  defp cluster_item_ids(cluster, type) do
    cluster.item_refs
    |> Enum.filter(&(&1.type == type))
    |> Enum.map(& &1.id)
    |> MapSet.new()
  end

  defp failure_clusters(runs, eval_runs, run_tasks, eval_tasks, trend_index) do
    runs
    |> Enum.map(&run_cluster_item(&1, run_tasks))
    |> Kernel.++(Enum.map(eval_runs, &eval_cluster_item(&1, eval_tasks)))
    |> Enum.group_by(& &1.key)
    |> Enum.map(fn {key, items} -> cluster_summary(items, Map.get(trend_index, key)) end)
    |> Enum.sort_by(fn cluster ->
      {-cluster.needs_task_count, -cluster.count,
       DateTime.to_unix(cluster.latest_at || DateTime.from_unix!(0))}
    end)
    |> Enum.take(6)
  end

  defp run_cluster_item(run, run_tasks) do
    workflow = run_group_label(run, run_tasks, "workflow")
    failure = run.failure_label || failure_group_label(run.failure_category)

    %{
      key: run_cluster_key(run),
      source: "Agent runs",
      kind: :run,
      workflow: workflow,
      failure: failure,
      needs_task?: !Map.has_key?(run_tasks, run.id),
      occurred_at: run.completed_at || run.inserted_at,
      item_ref: %{type: :run, id: run.id, needs_task?: !Map.has_key?(run_tasks, run.id)}
    }
  end

  defp eval_cluster_item(eval_run, eval_tasks) do
    workflow = workflow_label(eval_run)
    failure = eval_failure_cluster_label(eval_run)

    %{
      key: eval_cluster_key(eval_run),
      source: "Eval runs",
      kind: :eval,
      workflow: workflow,
      failure: failure,
      needs_task?: !Map.has_key?(eval_tasks, eval_run.id),
      occurred_at: eval_run.completed_at || eval_run.inserted_at,
      item_ref: %{
        type: :eval,
        id: eval_run.id,
        needs_task?: !Map.has_key?(eval_tasks, eval_run.id)
      }
    }
  end

  defp cluster_summary(items, trend) do
    first = List.first(items)
    trend_count = (trend && trend.count) || length(items)

    %{
      token: cluster_token(first.key),
      kind: first.kind,
      source: first.source,
      workflow: first.workflow,
      failure: first.failure,
      count: length(items),
      needs_task_count: Enum.count(items, & &1.needs_task?),
      latest_at: latest_item_at(items),
      trend_count: trend_count,
      trend_label: trend_label(trend_count),
      trend_latest_at: trend && trend.latest_at,
      item_refs: Enum.map(items, & &1.item_ref)
    }
  end

  defp trend_index(runs, eval_runs) do
    runs
    |> Enum.map(&trend_item(run_cluster_key(&1), &1.completed_at || &1.inserted_at))
    |> Kernel.++(
      Enum.map(eval_runs, &trend_item(eval_cluster_key(&1), &1.completed_at || &1.inserted_at))
    )
    |> Enum.group_by(& &1.key)
    |> Map.new(fn {key, items} ->
      {key, %{count: length(items), latest_at: latest_item_at(items)}}
    end)
  end

  defp trend_item(key, occurred_at), do: %{key: key, occurred_at: occurred_at}

  defp run_cluster_key(run) do
    workflow = run_group_label(run, %{}, "workflow")
    failure = run.failure_label || failure_group_label(run.failure_category)

    {:run, workflow, failure}
  end

  defp eval_cluster_key(eval_run) do
    {:eval, workflow_label(eval_run), eval_failure_cluster_label(eval_run)}
  end

  defp trend_label(count) when count >= 3, do: "Recurring"
  defp trend_label(2), do: "Repeated"
  defp trend_label(_count), do: "New"

  defp cluster_token(key) do
    key
    |> :erlang.term_to_binary()
    |> Base.url_encode64(padding: false)
  end

  defp latest_item_at(items) do
    items
    |> Enum.map(& &1.occurred_at)
    |> Enum.reject(&is_nil/1)
    |> Enum.max(fn left, right -> DateTime.compare(left, right) != :lt end, fn -> nil end)
  end

  defp run_group_label(run, run_tasks, "task_state") do
    case Map.get(run_tasks, run.id) do
      %{status: :completed} -> "Resolved"
      nil -> "Needs task"
      _task -> "Task open"
    end
  end

  defp run_group_label(run, _run_tasks, "failure"), do: failure_group_label(run.failure_category)

  defp run_group_label(run, _run_tasks, "workflow") do
    case run.deployment do
      %{name: name} when is_binary(name) -> name
      _deployment -> "Unassigned run"
    end
  end

  defp run_group_label(run, run_tasks, _group), do: run_group_label(run, run_tasks, "task_state")

  defp eval_group_label(eval_run, eval_tasks, "task_state") do
    case Map.get(eval_tasks, eval_run.id) do
      %{status: :completed} -> "Resolved"
      nil -> "Needs task"
      _task -> "Task open"
    end
  end

  defp eval_group_label(eval_run, _eval_tasks, "failure"), do: format_atom(eval_run.status)
  defp eval_group_label(eval_run, _eval_tasks, "workflow"), do: workflow_label(eval_run)

  defp eval_group_label(eval_run, eval_tasks, _group),
    do: eval_group_label(eval_run, eval_tasks, "task_state")

  defp failure_group_label(nil), do: "Unknown"
  defp failure_group_label(category), do: format_atom(category)

  defp fetch_agent_run(id) do
    Agents.get_agent_run(id,
      load: [
        :deployment,
        :failure_category,
        :failure_label,
        :failure_retryable,
        :failure_recovery_hint
      ]
    )
  end

  defp fetch_eval_run(id) do
    Agents.get_agent_eval_run(id, load: [:eval_case, :workflow_definition, :agent_run])
  end

  defp create_agent_run_task(run, actor) do
    case open_run_task(run.id, actor) do
      nil ->
        Operations.create_task_from_agent_run(agent_run_task_attrs(run), actor: actor)

      task ->
        {:existing, task}
    end
  end

  defp create_eval_run_task(eval_run, actor) do
    case open_eval_task(eval_run.id, actor) do
      nil ->
        Operations.create_task(eval_run_task_attrs(eval_run), actor: actor)

      task ->
        {:existing, task}
    end
  end

  defp create_cluster_tasks(item_refs, actor) do
    item_refs
    |> Enum.filter(& &1.needs_task?)
    |> Enum.reduce(%{created: 0, existing: 0, errors: []}, fn item_ref, acc ->
      case create_cluster_task(item_ref, actor) do
        {:ok, _task} ->
          Map.update!(acc, :created, &(&1 + 1))

        {:existing, _task} ->
          Map.update!(acc, :existing, &(&1 + 1))

        {:error, error} ->
          Map.update!(acc, :errors, &[error | &1])
      end
    end)
  end

  defp create_cluster_task(%{type: :run, id: id}, actor) do
    with {:ok, run} <- fetch_agent_run(id) do
      create_agent_run_task(run, actor)
    end
  end

  defp create_cluster_task(%{type: :eval, id: id}, actor) do
    with {:ok, eval_run} <- fetch_eval_run(id) do
      create_eval_run_task(eval_run, actor)
    end
  end

  defp resolve_task(%{status: :completed} = task, _actor), do: {:ok, task}

  defp resolve_task(%{status: :in_progress} = task, actor) do
    Operations.complete_task(task, actor: actor)
  end

  defp resolve_task(%{status: status} = task, actor) when status in [:pending, :blocked] do
    with {:ok, started_task} <- Operations.start_task(task, actor: actor) do
      Operations.complete_task(started_task, actor: actor)
    end
  end

  defp resolve_task(task, _actor),
    do: {:error, "Task #{task.id} cannot be resolved from #{task.status}."}

  defp resolvable_task?(%{status: status}) when status in [:pending, :in_progress, :blocked],
    do: true

  defp resolvable_task?(_task), do: false

  defp task_completed?(%{status: :completed}), do: true
  defp task_completed?(_task), do: false

  defp task_button_label(%{status: :completed}), do: "Resolved"
  defp task_button_label(_task), do: "Open Task"

  defp task_button_class(%{status: :completed}), do: "btn btn-sm btn-success"
  defp task_button_class(_task), do: "btn btn-sm btn-primary"

  defp cluster_task_flash_kind(%{errors: []}), do: :info
  defp cluster_task_flash_kind(_result), do: :error

  defp cluster_task_message(%{created: 0, existing: 0, errors: []}) do
    "No missing tasks in that failure cluster."
  end

  defp cluster_task_message(%{created: created, existing: existing, errors: []}) do
    "Created #{created} cluster task#{plural_suffix(created)}#{existing_suffix(existing)}."
  end

  defp cluster_task_message(%{created: created, existing: existing, errors: errors}) do
    "Created #{created} cluster task#{plural_suffix(created)}#{existing_suffix(existing)}; #{length(errors)} failed."
  end

  defp existing_suffix(0), do: ""
  defp existing_suffix(count), do: ", #{count} already existed"

  defp agent_run_task_attrs(run) do
    %{
      title: "Review failed agent run: #{agent_run_label(run)}",
      description: agent_run_task_description(run),
      task_type: :agent_followup,
      priority: agent_run_task_priority(run),
      due_at: DateTime.utc_now(),
      origin_id: run.id,
      origin_label: agent_run_label(run),
      origin_url: ~p"/console/agents/runs/#{run.id}",
      agent_run_id: run.id,
      metadata: %{
        "failure_category" => format_atom(run.failure_category),
        "retryable" => run.failure_retryable
      }
    }
  end

  defp eval_run_task_attrs(eval_run) do
    %{
      title: "Review failed agent eval: #{eval_case_name(eval_run)}",
      description: eval_run_task_description(eval_run),
      task_type: :agent_followup,
      priority: :high,
      due_at: DateTime.utc_now(),
      origin_domain: :agents,
      origin_resource: "agent_eval_run",
      origin_id: eval_run.id,
      origin_label: eval_case_name(eval_run),
      origin_url: ~p"/console/agents/evals",
      agent_run_id: eval_run.agent_run_id,
      metadata: %{
        "eval_status" => format_atom(eval_run.status),
        "workflow" => workflow_label(eval_run)
      }
    }
  end

  defp agent_run_task_description(run) do
    [run.failure_label || "Runtime failure", run.error, run.failure_recovery_hint]
    |> Enum.reject(&(is_nil(&1) or &1 == ""))
    |> Enum.join("\n\n")
  end

  defp eval_run_task_description(eval_run) do
    [eval_failure_summary(eval_run), eval_run.reviewer_notes]
    |> Enum.reject(&(is_nil(&1) or &1 == ""))
    |> Enum.join("\n\n")
  end

  defp open_run_task_map(runs, actor) do
    Map.new(runs, fn run -> {run.id, open_run_task(run.id, actor)} end)
    |> Enum.reject(fn {_id, task} -> is_nil(task) end)
    |> Map.new()
  end

  defp open_eval_task_map(eval_runs, actor) do
    Map.new(eval_runs, fn eval_run -> {eval_run.id, open_eval_task(eval_run.id, actor)} end)
    |> Enum.reject(fn {_id, task} -> is_nil(task) end)
    |> Map.new()
  end

  defp open_run_task(agent_run_id, actor) do
    case Operations.list_tasks_by_agent_run(agent_run_id, actor: actor) do
      {:ok, tasks} -> Enum.find(tasks, &agent_run_followup_task?/1)
      {:error, _error} -> nil
    end
  end

  defp open_eval_task(eval_run_id, actor) do
    case Operations.list_tasks_by_origin(:agents, "agent_eval_run", eval_run_id, actor: actor) do
      {:ok, tasks} -> Enum.find(tasks, &agent_eval_followup_task?/1)
      {:error, _error} -> nil
    end
  end

  defp agent_run_followup_task?(task) do
    agent_followup_task?(task) and task.origin_resource == "agent_run"
  end

  defp agent_eval_followup_task?(task) do
    agent_followup_task?(task) and task.origin_resource == "agent_eval_run"
  end

  defp agent_followup_task?(task) do
    task.status in [:pending, :in_progress, :blocked, :completed] and
      task.task_type == :agent_followup
  end

  defp agent_run_label(%{deployment: %{name: name}}) when is_binary(name), do: name
  defp agent_run_label(%{id: id}), do: "Run #{short_id(id)}"

  defp agent_run_task_priority(%{failure_retryable: true}), do: :high
  defp agent_run_task_priority(_run), do: :normal

  defp task_error_message(%Ash.Error.Invalid{} = error), do: Exception.message(error)
  defp task_error_message(%Ash.Error.Forbidden{}), do: "You are not allowed to create that task."
  defp task_error_message(error), do: "Could not create task: #{inspect(error)}"

  defp eval_case_name(%{eval_case: %{name: name}}) when is_binary(name), do: name
  defp eval_case_name(%{eval_case_id: id}) when is_binary(id), do: "Case #{short_id(id)}"
  defp eval_case_name(_eval_run), do: "Eval run"

  defp workflow_label(%{workflow_definition: %{key: key, version: version}})
       when is_binary(key),
       do: "#{key} v#{version}"

  defp workflow_label(%{eval_case: %{workflow_key: key}}) when is_binary(key), do: key
  defp workflow_label(_eval_run), do: "workflow"

  defp eval_failure_summary(%{forbidden_action_hits: hits}) when is_list(hits) and hits != [] do
    "Forbidden actions observed: #{Enum.join(hits, ", ")}"
  end

  defp eval_failure_summary(%{output_snapshot: output}) when is_map(output) do
    case Map.get(output, "mode") || Map.get(output, :mode) do
      nil -> "Expectation did not pass."
      mode -> "Observed mode: #{mode}"
    end
  end

  defp eval_failure_summary(_eval_run), do: "Expectation did not pass."

  defp eval_failure_cluster_label(%{status: :error, reviewer_notes: notes})
       when is_binary(notes) and notes != "",
       do: "error: #{notes}"

  defp eval_failure_cluster_label(%{status: status} = eval_run),
    do: "#{format_atom(status)}: #{eval_failure_summary(eval_run)}"

  defp eval_status_badge(:failed), do: "badge badge-error badge-sm"
  defp eval_status_badge(:error), do: "badge badge-error badge-sm"
  defp eval_status_badge(status), do: "badge badge-ghost badge-sm #{status}"

  defp cluster_badge("Agent runs"), do: "badge badge-error badge-sm"
  defp cluster_badge("Eval runs"), do: "badge badge-warning badge-sm"
  defp cluster_badge(_source), do: "badge badge-ghost badge-sm"

  defp trend_badge("Recurring"), do: "badge badge-error badge-sm"
  defp trend_badge("Repeated"), do: "badge badge-warning badge-sm"
  defp trend_badge(_label), do: "badge badge-info badge-sm"

  defp plural_suffix(1), do: ""
  defp plural_suffix(_count), do: "s"

  defp task_need_label(1), do: "1 task needed"
  defp task_need_label(count), do: "#{count} tasks needed"

  defp format_atom(nil), do: "-"
  defp format_atom(value), do: value |> to_string() |> String.replace("_", " ")

  defp format_datetime(nil), do: "-"
  defp format_datetime(datetime), do: Calendar.strftime(datetime, "%b %d, %H:%M")

  defp short_id(id), do: String.slice(id, 0, 8)
end
