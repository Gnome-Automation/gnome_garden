defmodule GnomeGardenWeb.Console.AgentEvalsLive do
  use GnomeGardenWeb, :live_view

  alias GnomeGarden.Agents
  alias GnomeGarden.Agents.AgentEvalRunner
  alias GnomeGarden.Agents.AgentEvalSweep
  alias GnomeGarden.Agents.AgentEvalSweepHealth
  alias GnomeGarden.Agents.AgentEvalSweepWorker

  @recent_run_limit 20
  @refresh_interval_ms 5_000
  @manual_eval_timeout_ms 5_000

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      :timer.send_interval(@refresh_interval_ms, :refresh_evals)
    end

    {:ok,
     socket
     |> assign(:page_title, "Agent Evaluations")
     |> assign(:eval_counts, empty_eval_counts())
     |> assign(:sweep_health, empty_sweep_health())
     |> assign(:eval_case_summaries, %{})
     |> assign(:coverage_summaries, [])
     |> stream(:eval_cases, [], reset: true)
     |> stream(:eval_runs, [], reset: true)
     |> load_evals()}
  end

  @impl true
  def handle_info(:refresh_evals, socket) do
    {:noreply, load_evals(socket)}
  end

  @impl true
  def handle_event("seed_procurement_inspection_eval", _params, socket) do
    case AgentEvalRunner.seed_known_cases(actor: socket.assigns.current_user) do
      {:ok, _eval_cases} ->
        {:noreply,
         socket
         |> load_evals()
         |> put_flash(:info, "Procurement inspection eval cases are ready.")}

      {:error, error} ->
        {:noreply, put_flash(socket, :error, error_message(error))}
    end
  end

  def handle_event("prepare_procurement_inspection_fixture", _params, socket) do
    case AgentEvalRunner.prepare_procurement_inspection_fixtures(
           actor: socket.assigns.current_user,
           fixture_base_url: procurement_fixture_base_url()
         ) do
      {:ok, _prepared} ->
        {:noreply,
         socket
         |> load_evals()
         |> put_flash(:info, "Runnable procurement inspection fixtures are ready.")}

      {:error, error} ->
        {:noreply, put_flash(socket, :error, error_message(error))}
    end
  end

  def handle_event("run_procurement_inspection_fixture", _params, socket) do
    case AgentEvalRunner.prepare_and_run_procurement_inspection_fixtures(
           actor: socket.assigns.current_user,
           fixture_base_url: procurement_fixture_base_url(),
           timeout_ms: @manual_eval_timeout_ms,
           browser: procurement_fixture_browser()
         ) do
      {:ok, %{sweep_result: sweep_result}} ->
        {:noreply,
         socket
         |> load_evals()
         |> put_flash(:info, local_fixture_run_message(sweep_result))}

      {:error, error} ->
        {:noreply, put_flash(socket, :error, error_message(error))}
    end
  end

  def handle_event("run_procurement_inspection_fixture_sweep", _params, socket) do
    case AgentEvalSweepWorker.enqueue("local_fixture",
           timeout_ms: @manual_eval_timeout_ms,
           fixture_base_url: procurement_fixture_base_url()
         ) do
      {:ok, _job} ->
        {:noreply,
         socket
         |> load_evals()
         |> put_flash(:info, local_fixture_sweep_queued_message())}

      {:error, error} ->
        {:noreply, put_flash(socket, :error, error_message(error))}
    end
  end

  def handle_event("run_eval", %{"id" => id}, socket) do
    with {:ok, %{eval_run: eval_run}} <-
           AgentEvalRunner.run_case(id, actor: socket.assigns.current_user) do
      message =
        case eval_run.status do
          :passed -> "Eval passed."
          :failed -> "Eval completed with failures."
          :error -> "Eval errored."
          _status -> "Eval recorded."
        end

      {:noreply,
       socket
       |> load_evals()
       |> put_flash(:info, message)}
    else
      {:error, error} ->
        {:noreply, put_flash(socket, :error, error_message(error))}
    end
  end

  def handle_event("run_runnable_evals", _params, socket) do
    case AgentEvalSweep.run(
           actor: socket.assigns.current_user,
           timeout_ms: @manual_eval_timeout_ms
         ) do
      {:ok, result} ->
        {:noreply,
         socket
         |> load_evals()
         |> put_flash(:info, sweep_message(result))}

      {:error, error} ->
        {:noreply, put_flash(socket, :error, error_message(error))}
    end
  end

  def handle_event("queue_eval_sweep", _params, socket) do
    case AgentEvalSweepWorker.enqueue() do
      {:ok, _job} ->
        {:noreply,
         socket
         |> load_evals()
         |> put_flash(:info, "Eval sweep queued.")}

      {:error, error} ->
        {:noreply, put_flash(socket, :error, error_message(error))}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.page class="pb-8">
      <.page_header eyebrow="Console">
        Agent Evaluations
        <:subtitle>
          Inspect active eval cases and recent run evidence for governed workflow behavior.
        </:subtitle>
        <:actions>
          <.link navigate={~p"/console/agents/workflows"} class="btn btn-sm">
            Workflows
          </.link>
          <.link navigate={~p"/console/agents"} class="btn btn-sm">
            Agents Console
          </.link>
          <button
            type="button"
            class="btn btn-sm"
            phx-click="queue_eval_sweep"
            phx-disable-with="Queueing..."
          >
            Queue Eval Sweep
          </button>
          <button
            type="button"
            class="btn btn-sm"
            phx-click="run_runnable_evals"
          >
            Run Runnable Evals
          </button>
          <button
            type="button"
            class="btn btn-sm"
            phx-click="prepare_procurement_inspection_fixture"
          >
            Prepare Local Fixture
          </button>
          <button
            type="button"
            class="btn btn-sm btn-primary"
            phx-click="run_procurement_inspection_fixture"
            phx-disable-with="Running..."
          >
            Run Local Checks
          </button>
          <button
            type="button"
            class="btn btn-sm btn-primary"
            phx-click="run_procurement_inspection_fixture_sweep"
            phx-disable-with="Queueing..."
          >
            Queue Local Sweep
          </button>
          <button
            type="button"
            class="btn btn-sm"
            phx-click="seed_procurement_inspection_eval"
          >
            Seed Inspection Eval
          </button>
        </:actions>
      </.page_header>

      <div class="grid gap-2 sm:grid-cols-2 xl:grid-cols-6">
        <.stat_card
          title="Active Cases"
          value={to_string(@eval_counts.active_cases)}
          description="Cases available for operator review or execution."
          icon="hero-clipboard-document-list"
          accent="sky"
        />
        <.stat_card
          title="Runnable"
          value={to_string(@eval_counts.runnable_cases)}
          description="Active cases with concrete source and deployment inputs."
          icon="hero-play-circle"
          accent={if @eval_counts.runnable_cases > 0, do: "emerald", else: "amber"}
        />
        <.stat_card
          title="Passed"
          value={to_string(@eval_counts.passed)}
          description="Recent eval runs that matched expected behavior."
          icon="hero-check-circle"
          accent="emerald"
        />
        <.stat_card
          title="Needs Review"
          value={to_string(@eval_counts.failed + @eval_counts.error)}
          description="Recent failed or errored eval runs."
          icon="hero-exclamation-triangle"
          accent={if @eval_counts.failed + @eval_counts.error > 0, do: "rose", else: "emerald"}
        />
        <.stat_card
          title="Sweep Queue"
          value={"#{@sweep_health.queued}/#{@sweep_health.running}"}
          description="Queued/running background eval sweeps."
          icon="hero-clock"
          accent={if @sweep_health.queued + @sweep_health.running > 0, do: "amber", else: "emerald"}
        />
        <.stat_card
          title="Sweep Health"
          value={sweep_health_value(@sweep_health)}
          description={sweep_health_description(@sweep_health)}
          icon="hero-arrow-path"
          accent={latest_sweep_accent(@sweep_health)}
        />
      </div>

      <.section
        title="Coverage Breakdown"
        description="Workflow coverage by runnable scenario and latest eval outcome."
        compact
      >
        <div class="grid gap-3 p-4 lg:grid-cols-2">
          <div
            :if={@coverage_summaries == []}
            class="text-sm text-base-content/50"
          >
            No active eval coverage yet.
          </div>

          <article
            :for={summary <- @coverage_summaries}
            class="rounded-md border border-base-content/10 bg-base-100 p-3"
          >
            <div class="flex flex-wrap items-start justify-between gap-3">
              <div class="min-w-0">
                <h3 class="font-semibold text-base-content">{summary.workflow_key}</h3>
                <p class="mt-1 text-xs leading-5 text-base-content/60">
                  {summary.total_cases} case{plural_suffix(summary.total_cases)} · {summary.runnable_cases} runnable · {summary.needs_input_cases} need input
                </p>
              </div>
              <span class={coverage_badge(summary)}>
                {coverage_label(summary)}
              </span>
            </div>
            <div class="mt-3 flex flex-wrap gap-2 text-xs">
              <span class="rounded-md bg-success/10 px-2 py-1 text-success">
                passed {summary.latest_passed}
              </span>
              <span class="rounded-md bg-error/10 px-2 py-1 text-error">
                failed {summary.latest_failed}
              </span>
              <span class="rounded-md bg-error/10 px-2 py-1 text-error">
                errored {summary.latest_error}
              </span>
              <span class="rounded-md bg-base-200 px-2 py-1 text-base-content/60">
                unrun {summary.unrun_cases}
              </span>
            </div>
          </article>
        </div>
      </.section>

      <.section
        title="Active Eval Cases"
        description="Cases define the input, expected output, required actions, and forbidden actions for a workflow scenario."
        compact
      >
        <div class="divide-y divide-base-content/10">
          <div
            id="agent-eval-cases"
            phx-update="stream"
            class="divide-y divide-base-content/10"
          >
            <div
              id="agent-eval-cases-empty"
              class="hidden only:block px-4 py-8 text-center text-sm text-base-content/50"
            >
              No active eval cases yet.
            </div>

            <article
              :for={{row_id, eval_case} <- @streams.eval_cases}
              id={row_id}
              class="grid gap-3 px-4 py-4 lg:grid-cols-[minmax(0,1fr)_auto] lg:items-start"
            >
              <div class="min-w-0 space-y-2">
                <div class="flex flex-wrap items-center gap-2">
                  <h3 class="font-semibold text-base-content">{eval_case.name}</h3>
                  <span class="badge badge-ghost badge-sm">{eval_case.workflow_key}</span>
                  <span class="badge badge-info badge-sm">{format_atom(eval_case.status)}</span>
                  <span class={readiness_badge(eval_case)}>
                    {readiness_label(eval_case)}
                  </span>
                </div>
                <p :if={eval_case.description} class="text-sm leading-5 text-base-content/60">
                  {eval_case.description}
                </p>
                <div class="flex flex-wrap gap-2 text-xs text-base-content/60">
                  <span class={last_run_badge(eval_case_summary(@eval_case_summaries, eval_case))}>
                    Last run: {last_run_label(eval_case_summary(@eval_case_summaries, eval_case))}
                  </span>
                  <span
                    :if={
                      last_run_completed_label(eval_case_summary(@eval_case_summaries, eval_case)) !=
                        "-"
                    }
                    class="rounded-md bg-base-200 px-2 py-1 text-base-content/60"
                  >
                    {last_run_completed_label(eval_case_summary(@eval_case_summaries, eval_case))}
                  </span>
                </div>
                <div class="grid gap-2 text-xs leading-5 text-base-content/60 md:grid-cols-2">
                  <p>
                    <span class="font-semibold text-base-content/70">Expected:</span> {map_label(
                      eval_case.expected_output
                    )}
                  </p>
                  <p>
                    <span class="font-semibold text-base-content/70">Required:</span> {list_label(
                      eval_case.expected_actions
                    )}
                  </p>
                  <p>
                    <span class="font-semibold text-base-content/70">Forbidden:</span> {list_label(
                      eval_case.forbidden_actions
                    )}
                  </p>
                  <p>
                    <span class="font-semibold text-base-content/70">Input:</span> {map_label(
                      eval_case.input
                    )}
                  </p>
                </div>
              </div>

              <div class="flex flex-wrap gap-2 lg:justify-end">
                <button
                  :if={AgentEvalRunner.runnable?(eval_case)}
                  type="button"
                  class="btn btn-sm btn-primary"
                  phx-click="run_eval"
                  phx-value-id={eval_case.id}
                >
                  Run Eval
                </button>
                <span
                  :if={!AgentEvalRunner.runnable?(eval_case)}
                  class="badge badge-warning badge-sm"
                >
                  Needs source input
                </span>
              </div>
            </article>
          </div>
        </div>
      </.section>

      <.section
        title="Recent Eval Runs"
        description="Run evidence links expected behavior to actual AgentRun output snapshots."
        compact
      >
        <div class="overflow-x-auto">
          <table class="min-w-full divide-y divide-base-content/10 text-sm">
            <thead class="bg-base-200/60 text-left">
              <tr>
                <th class="px-4 py-3 font-medium text-base-content/50">Case</th>
                <th class="px-4 py-3 font-medium text-base-content/50">Status</th>
                <th class="px-4 py-3 font-medium text-base-content/50">Score</th>
                <th class="px-4 py-3 font-medium text-base-content/50">Output</th>
                <th class="px-4 py-3 font-medium text-base-content/50">Completed</th>
                <th class="px-4 py-3 font-medium text-base-content/50">Run</th>
              </tr>
            </thead>
            <tbody id="agent-eval-runs" phx-update="stream" class="divide-y divide-base-content/10">
              <tr id="agent-eval-runs-empty" class="hidden only:table-row">
                <td colspan="6" class="px-4 py-8 text-center text-sm text-base-content/50">
                  No eval runs recorded yet.
                </td>
              </tr>

              <tr :for={{row_id, eval_run} <- @streams.eval_runs} id={row_id}>
                <td class="px-4 py-4">
                  <div class="font-medium text-base-content">
                    {eval_case_name(eval_run)}
                  </div>
                  <div class="mt-1 text-xs text-base-content/50">
                    {workflow_label(eval_run)}
                  </div>
                </td>
                <td class="px-4 py-4">
                  <span class={eval_status_badge(eval_run.status)}>
                    {format_atom(eval_run.status)}
                  </span>
                </td>
                <td class="px-4 py-4 font-medium tabular-nums text-base-content/80">
                  {score_label(eval_run.score)}
                </td>
                <td class="max-w-sm px-4 py-4 text-xs leading-5 text-base-content/60">
                  {map_label(eval_run.output_snapshot)}
                </td>
                <td class="px-4 py-4 text-base-content/70">
                  {format_datetime(eval_run.completed_at || eval_run.inserted_at)}
                </td>
                <td class="px-4 py-4">
                  <.link
                    :if={eval_run.agent_run_id}
                    navigate={~p"/console/agents/runs/#{eval_run.agent_run_id}"}
                    class="btn btn-sm"
                  >
                    Open Run
                  </.link>
                  <span :if={!eval_run.agent_run_id} class="text-xs text-base-content/40">-</span>
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </.section>
    </.page>
    """
  end

  defp load_evals(socket) do
    eval_cases = list_active_cases()
    eval_runs = list_recent_runs()

    socket
    |> assign(:eval_counts, eval_counts(eval_cases, eval_runs))
    |> assign(:sweep_health, sweep_health())
    |> assign(:eval_case_summaries, eval_case_summaries(eval_runs))
    |> assign(:coverage_summaries, coverage_summaries(eval_cases, eval_runs))
    |> stream(:eval_cases, eval_cases, reset: true)
    |> stream(:eval_runs, eval_runs, reset: true)
  end

  defp list_active_cases do
    case Agents.list_active_agent_eval_cases(query: [load: [:workflow_definition]]) do
      {:ok, cases} -> cases
      {:error, _error} -> []
    end
  end

  defp list_recent_runs do
    case Agents.list_recent_agent_eval_runs(@recent_run_limit,
           query: [load: [:eval_case, :workflow_definition, :agent_run]]
         ) do
      {:ok, runs} -> runs
      {:error, _error} -> []
    end
  end

  defp eval_counts(eval_cases, eval_runs) do
    %{
      active_cases: length(eval_cases),
      runnable_cases: Enum.count(eval_cases, &AgentEvalRunner.runnable?/1),
      recent_runs: length(eval_runs),
      passed: Enum.count(eval_runs, &(&1.status == :passed)),
      failed: Enum.count(eval_runs, &(&1.status == :failed)),
      error: Enum.count(eval_runs, &(&1.status == :error))
    }
  end

  defp empty_eval_counts do
    %{active_cases: 0, runnable_cases: 0, recent_runs: 0, passed: 0, failed: 0, error: 0}
  end

  defp empty_sweep_health do
    %{
      queued: 0,
      running: 0,
      completed: 0,
      failed: 0,
      latest: nil,
      next_scheduled_at: nil,
      schedule: nil,
      stale_after_seconds: AgentEvalSweepHealth.stale_after_seconds(),
      stale?: false,
      status: :idle
    }
  end

  defp sweep_health do
    case AgentEvalSweepHealth.summary() do
      {:ok, summary} -> summary
      {:error, _error} -> empty_sweep_health()
    end
  end

  defp eval_case_summaries(eval_runs) do
    eval_runs
    |> Enum.reject(&is_nil(&1.eval_case_id))
    |> Enum.group_by(& &1.eval_case_id)
    |> Map.new(fn {eval_case_id, runs} ->
      {eval_case_id, List.first(runs)}
    end)
  end

  defp eval_case_summary(summaries, eval_case), do: Map.get(summaries, eval_case.id)

  defp coverage_summaries(eval_cases, eval_runs) do
    latest_runs = eval_case_summaries(eval_runs)

    eval_cases
    |> Enum.group_by(& &1.workflow_key)
    |> Enum.map(fn {workflow_key, cases} ->
      latest_statuses =
        cases
        |> Enum.map(&Map.get(latest_runs, &1.id))
        |> Enum.map(&latest_status/1)

      %{
        workflow_key: workflow_key,
        total_cases: length(cases),
        runnable_cases: Enum.count(cases, &AgentEvalRunner.runnable?/1),
        needs_input_cases: Enum.count(cases, &(not AgentEvalRunner.runnable?(&1))),
        latest_passed: Enum.count(latest_statuses, &(&1 == :passed)),
        latest_failed: Enum.count(latest_statuses, &(&1 == :failed)),
        latest_error: Enum.count(latest_statuses, &(&1 == :error)),
        unrun_cases: Enum.count(latest_statuses, &is_nil/1)
      }
    end)
    |> Enum.sort_by(& &1.workflow_key)
  end

  defp latest_status(nil), do: nil
  defp latest_status(%{status: status}), do: status

  defp sweep_message(result) do
    "Eval sweep ran #{result.attempted}, passed #{result.passed}, failed #{result.failed}, errored #{result.errored}, skipped #{result.skipped}."
  end

  defp sweep_health_value(%{status: status}), do: format_atom(status)
  defp sweep_health_value(_health), do: "-"

  defp sweep_health_description(%{latest: nil, next_scheduled_at: next_scheduled_at}) do
    "No sweeps yet. Next #{format_datetime(next_scheduled_at)}."
  end

  defp sweep_health_description(%{
         latest: %{mode: mode, completed_at: completed_at, attempted_at: attempted_at},
         next_scheduled_at: next_scheduled_at
       }) do
    timestamp = completed_at || attempted_at

    "Last #{format_atom(mode)} #{format_datetime(timestamp)}. Next #{format_datetime(next_scheduled_at)}."
  end

  defp latest_sweep_accent(%{status: :failed}), do: "rose"
  defp latest_sweep_accent(%{status: :stale}), do: "amber"
  defp latest_sweep_accent(%{status: :running}), do: "amber"
  defp latest_sweep_accent(%{status: :queued}), do: "amber"
  defp latest_sweep_accent(%{status: :healthy}), do: "emerald"
  defp latest_sweep_accent(_health), do: "zinc"

  defp local_fixture_run_message(result) do
    "Local procurement inspection checks ran #{result.attempted}, passed #{result.passed}, failed #{result.failed}, errored #{result.errored}, skipped #{result.skipped}."
  end

  defp local_fixture_sweep_queued_message do
    "Local procurement inspection sweep queued. The worker will prepare fixtures and run the scoped eval cases."
  end

  defp procurement_fixture_base_url do
    url(~p"/")
  end

  defp procurement_fixture_browser do
    Application.get_env(:gnome_garden, :agent_eval_fixture_browser, GnomeGarden.Browser)
  end

  defp eval_case_name(%{eval_case: %{name: name}}) when is_binary(name), do: name
  defp eval_case_name(%{eval_case_id: id}) when is_binary(id), do: "Case #{short_id(id)}"
  defp eval_case_name(_eval_run), do: "-"

  defp workflow_label(%{workflow_definition: %{key: key, version: version}})
       when is_binary(key),
       do: "#{key} v#{version}"

  defp workflow_label(%{eval_case: %{workflow_key: key}}) when is_binary(key), do: key
  defp workflow_label(_eval_run), do: "-"

  defp eval_status_badge(:passed), do: "badge badge-success badge-sm"
  defp eval_status_badge(:failed), do: "badge badge-error badge-sm"
  defp eval_status_badge(:error), do: "badge badge-error badge-sm"
  defp eval_status_badge(:running), do: "badge badge-info badge-sm"
  defp eval_status_badge(_status), do: "badge badge-ghost badge-sm"

  defp readiness_label(eval_case) do
    if AgentEvalRunner.runnable?(eval_case), do: "Runnable", else: "Needs input"
  end

  defp readiness_badge(eval_case) do
    if AgentEvalRunner.runnable?(eval_case),
      do: "badge badge-success badge-sm",
      else: "badge badge-warning badge-sm"
  end

  defp coverage_label(%{latest_failed: 0, latest_error: 0, unrun_cases: 0}), do: "Covered"
  defp coverage_label(%{needs_input_cases: count}) when count > 0, do: "Needs input"
  defp coverage_label(_summary), do: "Needs runs"

  defp coverage_badge(%{latest_failed: 0, latest_error: 0, unrun_cases: 0}),
    do: "badge badge-success badge-sm"

  defp coverage_badge(%{needs_input_cases: count}) when count > 0,
    do: "badge badge-warning badge-sm"

  defp coverage_badge(_summary), do: "badge badge-info badge-sm"

  defp last_run_label(nil), do: "none"
  defp last_run_label(%{status: status}), do: format_atom(status)

  defp last_run_badge(nil), do: "rounded-md bg-base-200 px-2 py-1 text-base-content/60"
  defp last_run_badge(%{status: :passed}), do: "rounded-md bg-success/10 px-2 py-1 text-success"
  defp last_run_badge(%{status: :failed}), do: "rounded-md bg-error/10 px-2 py-1 text-error"
  defp last_run_badge(%{status: :error}), do: "rounded-md bg-error/10 px-2 py-1 text-error"
  defp last_run_badge(%{status: :running}), do: "rounded-md bg-info/10 px-2 py-1 text-info"
  defp last_run_badge(_run), do: "rounded-md bg-base-200 px-2 py-1 text-base-content/60"

  defp last_run_completed_label(nil), do: "-"

  defp last_run_completed_label(eval_run) do
    format_datetime(eval_run.completed_at || eval_run.inserted_at)
  end

  defp score_label(nil), do: "-"
  defp score_label(score), do: Decimal.to_string(score, :normal)

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

  defp map_label(value), do: scalar_label(value)

  defp scalar_label(value) when is_map(value), do: "#{map_size(value)} fields"
  defp scalar_label(values) when is_list(values), do: "#{length(values)} items"
  defp scalar_label(value) when is_atom(value), do: format_atom(value)
  defp scalar_label(value), do: to_string(value)

  defp format_atom(nil), do: "-"
  defp format_atom(value), do: value |> to_string() |> String.replace("_", " ")

  defp format_datetime(nil), do: "-"
  defp format_datetime(datetime), do: Calendar.strftime(datetime, "%b %d, %H:%M")

  defp plural_suffix(1), do: ""
  defp plural_suffix(_count), do: "s"

  defp short_id(id), do: String.slice(id, 0, 8)

  defp error_message(error) when is_binary(error), do: error

  defp error_message(%{__struct__: _} = error) do
    Exception.message(error)
  rescue
    Protocol.UndefinedError -> inspect(error)
  end

  defp error_message(error), do: inspect(error)
end
