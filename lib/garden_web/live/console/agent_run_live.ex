defmodule GnomeGardenWeb.Console.AgentRunLive do
  use GnomeGardenWeb, :live_view

  alias GnomeGarden.Acquisition
  alias GnomeGarden.Agents
  alias GnomeGarden.Agents.DeploymentRunner

  @refresh_interval_ms 2_000

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    run = load_run!(id)
    messages = Agents.list_agent_messages_for_run!(run.id)
    outputs = Agents.list_agent_run_outputs_for_run!(run.id)

    if connected?(socket) do
      maybe_subscribe(run)
      :timer.send_interval(@refresh_interval_ms, :refresh_run)
    end

    {:ok,
     socket
     |> assign(:page_title, "Run #{short_id(run.id)}")
     |> assign(:run, run)
     |> assign(:live_output, "")
     |> assign(:current_thinking, nil)
     |> assign(:active_tool, nil)
     |> assign(:last_refreshed_at, DateTime.utc_now())
     |> stream(:messages, messages, reset: true)
     |> stream(:outputs, outputs, reset: true)
     |> stream(:tool_events, [], reset: true)}
  end

  @impl true
  def handle_info(:refresh_run, socket) do
    run = load_run!(socket.assigns.run.id)
    messages = Agents.list_agent_messages_for_run!(run.id)
    outputs = Agents.list_agent_run_outputs_for_run!(run.id)

    {:noreply,
     socket
     |> assign(:run, run)
     |> assign(:last_refreshed_at, DateTime.utc_now())
     |> stream(:messages, messages, reset: true)
     |> stream(:outputs, outputs, reset: true)}
  end

  def handle_info({:stream, {:llm_delta, delta}}, socket) do
    {:noreply, assign(socket, :live_output, socket.assigns.live_output <> (delta || ""))}
  end

  def handle_info({:stream, {:llm_complete, %{thinking: thinking, text: text}}}, socket) do
    live_output =
      cond do
        is_binary(text) and String.length(text) > String.length(socket.assigns.live_output) ->
          text

        true ->
          socket.assigns.live_output
      end

    {:noreply,
     socket
     |> assign(:live_output, live_output)
     |> assign(:current_thinking, thinking)}
  end

  def handle_info({:stream, {:tool_start, tool_name}}, socket) do
    event = %{
      id: unique_event_id(),
      type: :tool_start,
      tool_name: tool_name,
      inserted_at: DateTime.utc_now()
    }

    {:noreply,
     socket
     |> assign(:active_tool, tool_name)
     |> stream_insert(:tool_events, event, at: 0)}
  end

  def handle_info({:stream, {:tool_complete, tool_info}}, socket) do
    event =
      %{
        id: unique_event_id(),
        type: :tool_complete,
        tool_name: tool_info.name,
        duration_ms: tool_info.duration_ms,
        result: tool_info.result,
        inserted_at: DateTime.utc_now()
      }

    {:noreply,
     socket
     |> assign(:active_tool, nil)
     |> stream_insert(:tool_events, event, at: 0)}
  end

  @impl true
  def handle_event("cancel_run", _, socket) do
    case DeploymentRunner.cancel_run(socket.assigns.run.id, actor: socket.assigns.current_user) do
      {:ok, _run} ->
        refreshed = load_run!(socket.assigns.run.id)

        {:noreply,
         socket
         |> assign(:run, refreshed)
         |> put_flash(:info, "Run cancelled.")}

      {:error, error} ->
        {:noreply, put_flash(socket, :error, error_message(error))}
    end
  end

  def handle_event("pi_steer", %{"message" => msg}, socket) when byte_size(msg) > 0 do
    GnomeGarden.Agents.PiRunner.steer(to_string(socket.assigns.run.id), msg)
    {:noreply, put_flash(socket, :info, "Steer queued.")}
  end

  def handle_event("pi_steer", _, socket), do: {:noreply, socket}

  def handle_event("pi_abort", _, socket) do
    case DeploymentRunner.cancel_run(socket.assigns.run.id, actor: socket.assigns.current_user) do
      {:ok, refreshed} ->
        {:noreply, socket |> assign(:run, refreshed) |> put_flash(:info, "Pi run cancelled.")}

      {:error, error} ->
        {:noreply, put_flash(socket, :error, error_message(error))}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-8">
      <div class="flex items-start justify-between gap-4">
        <div class="space-y-2">
          <.link
            navigate={~p"/console/agents"}
            class="text-sm font-medium text-emerald-600 hover:text-primary dark:hover:text-emerald-300"
          >
            Back to Agents Console
          </.link>

          <div>
            <h1 class="text-2xl font-semibold tracking-tight text-base-content">
              {@run.deployment && @run.deployment.name}
            </h1>
            <p class="mt-1 text-sm text-base-content/60">
              Run {short_id(@run.id)} · {format_atom(@run.run_kind)} · template {template_label(@run)}
            </p>
          </div>
        </div>

        <div class="flex items-center gap-2">
          <span class={run_state_badge(@run.state)}>{format_atom(@run.state)}</span>

          <button
            :if={@run.state in [:pending, :running]}
            type="button"
            class="btn btn-sm"
            phx-click="cancel_run"
          >
            Cancel Run
          </button>
        </div>
      </div>

      <section
        :if={@run.state == :running and pi_template?(@run)}
        class="rounded-2xl border border-emerald-200 bg-emerald-50 p-5 shadow-sm dark:border-emerald-900 dark:bg-emerald-950/30"
      >
        <h3 class="text-sm font-semibold text-emerald-900 dark:text-emerald-200">
          Pi sidecar controls
        </h3>
        <form phx-submit="pi_steer" class="mt-3 flex gap-2">
          <input
            type="text"
            name="message"
            placeholder="Steer the agent (delivered after current tool finishes)"
            class="flex-1 rounded-md bg-white px-3 py-1.5 text-sm text-gray-900 outline-1 -outline-offset-1 outline-gray-300 placeholder:text-gray-400 focus:outline-2 focus:-outline-offset-2 focus:outline-emerald-600 dark:bg-white/5 dark:text-white dark:outline-white/10"
          />
          <button
            type="submit"
            class="rounded-md bg-emerald-600 px-3 py-1.5 text-sm font-semibold text-white hover:bg-emerald-500 dark:bg-emerald-500"
          >
            Steer
          </button>
          <button
            type="button"
            phx-click="pi_abort"
            class="rounded-md bg-red-600 px-3 py-1.5 text-sm font-semibold text-white hover:bg-red-500"
          >
            Abort
          </button>
        </form>
      </section>

      <section class="grid gap-4 md:grid-cols-4">
        <div class="rounded-2xl border border-zinc-200 bg-white p-5 shadow-sm dark:border-zinc-800 dark:bg-zinc-900">
          <p class="text-sm font-medium text-base-content/50">Requested By</p>
          <p class="mt-2 text-base font-semibold text-base-content">
            {requester_label(@run)}
          </p>
        </div>

        <div class="rounded-2xl border border-zinc-200 bg-white p-5 shadow-sm dark:border-zinc-800 dark:bg-zinc-900">
          <p class="text-sm font-medium text-base-content/50">Started</p>
          <p class="mt-2 text-base font-semibold text-base-content">
            {format_datetime(@run.started_at || @run.inserted_at)}
          </p>
        </div>

        <div class="rounded-2xl border border-zinc-200 bg-white p-5 shadow-sm dark:border-zinc-800 dark:bg-zinc-900">
          <p class="text-sm font-medium text-base-content/50">Completed</p>
          <p class="mt-2 text-base font-semibold text-base-content">
            {format_datetime(@run.completed_at)}
          </p>
        </div>

        <div class="rounded-2xl border border-zinc-200 bg-white p-5 shadow-sm dark:border-zinc-800 dark:bg-zinc-900">
          <p class="text-sm font-medium text-base-content/50">Usage</p>
          <p class="mt-2 text-base font-semibold text-base-content">
            {@run.token_count || 0} tokens · {@run.tool_count || 0} tools
          </p>
        </div>
      </section>

      <section class="grid gap-8 xl:grid-cols-[1.4fr_1fr]">
        <div class="space-y-8">
          <section class="rounded-2xl border border-zinc-200 bg-white shadow-sm dark:border-zinc-800 dark:bg-zinc-900">
            <div class="border-b border-zinc-200 px-5 py-4 dark:border-zinc-800">
              <h2 class="text-lg font-semibold text-base-content">Task</h2>
              <p class="text-sm text-base-content/60">
                The durable execution request attached to this run.
              </p>
            </div>

            <div class="px-5 py-4">
              <pre class="whitespace-pre-wrap text-sm leading-6 text-base-content/80">{@run.task}</pre>
            </div>
          </section>

          <section class="rounded-2xl border border-zinc-200 bg-white shadow-sm dark:border-zinc-800 dark:bg-zinc-900">
            <div class="border-b border-zinc-200 px-5 py-4 dark:border-zinc-800">
              <h2 class="text-lg font-semibold text-base-content">Messages</h2>
              <p class="text-sm text-base-content/60">
                Persisted run timeline from `AgentMessage`.
              </p>
            </div>

            <div
              id="run-messages"
              phx-update="stream"
              class="divide-y divide-zinc-200 dark:divide-zinc-800"
            >
              <div
                id="run-messages-empty"
                class="hidden only:block px-5 py-8 text-center text-sm text-base-content/50"
              >
                No persisted messages yet.
              </div>

              <div :for={{dom_id, message} <- @streams.messages} id={dom_id} class="px-5 py-4">
                <div class="flex items-center gap-3">
                  <span class={message_role_badge(message.role)}>{format_atom(message.role)}</span>
                  <span class="text-xs text-base-content/50">
                    {format_datetime(message.inserted_at)}
                  </span>
                </div>

                <div
                  :if={message.content}
                  class="mt-3 whitespace-pre-wrap text-sm leading-6 text-base-content/80"
                >
                  {message.content}
                </div>

                <div
                  :if={message.tool_name}
                  class="mt-3 rounded-xl bg-zinc-50 px-3 py-2 text-xs text-zinc-600 dark:bg-zinc-950/70 dark:text-zinc-300"
                >
                  Tool: {message.tool_name}
                </div>
              </div>
            </div>
          </section>

          <section class="rounded-2xl border border-zinc-200 bg-white shadow-sm dark:border-zinc-800 dark:bg-zinc-900">
            <div class="border-b border-zinc-200 px-5 py-4 dark:border-zinc-800">
              <h2 class="text-lg font-semibold text-base-content">Business Outputs</h2>
              <p class="text-sm text-base-content/60">
                Durable business entities created or reused by this run.
              </p>
            </div>

            <div
              id="run-outputs"
              phx-update="stream"
              class="divide-y divide-zinc-200 dark:divide-zinc-800"
            >
              <div
                id="run-outputs-empty"
                class="hidden only:block px-5 py-8 text-center text-sm text-base-content/50"
              >
                No business outputs recorded yet.
              </div>

              <div :for={{dom_id, output} <- @streams.outputs} id={dom_id} class="px-5 py-4">
                <div class="flex items-center gap-3">
                  <span class={output_type_badge(output.output_type)}>
                    {output_type_label(output.output_type)}
                  </span>
                  <span class={output_event_badge(output.event)}>{format_atom(output.event)}</span>
                  <span class="text-xs text-base-content/50">
                    {format_datetime(output.inserted_at)}
                  </span>
                </div>

                <div class="mt-3">
                  <p class="font-medium text-base-content">{output.label}</p>
                  <p :if={output.summary} class="mt-1 text-sm text-base-content/70">
                    {output.summary}
                  </p>
                </div>

                <div
                  :if={output_summary_details(output)}
                  class="mt-3 text-xs text-base-content/50"
                >
                  {output_summary_details(output)}
                </div>

                <.scan_diagnostics_panel
                  :if={scan_diagnostics(output)}
                  diagnostics={scan_diagnostics(output)}
                />

                <div :if={output_path(output)} class="mt-4 flex flex-wrap gap-2">
                  <.link navigate={output_path(output)} class="btn btn-sm">
                    {output_action_label(output)}
                  </.link>
                </div>
              </div>
            </div>
          </section>
        </div>

        <div class="space-y-8">
          <section class="rounded-2xl border border-zinc-200 bg-white shadow-sm dark:border-zinc-800 dark:bg-zinc-900">
            <div class="flex items-center justify-between border-b border-zinc-200 px-5 py-4 dark:border-zinc-800">
              <div>
                <h2 class="text-lg font-semibold text-base-content">Live Stream</h2>
                <p class="text-sm text-base-content/60">
                  Ephemeral output from the runtime while the run is active.
                </p>
              </div>

              <span class="text-xs text-base-content/50">
                Refreshed {format_datetime(@last_refreshed_at)}
              </span>
            </div>

            <div class="space-y-4 px-5 py-4">
              <div
                :if={@active_tool}
                class="rounded-xl bg-amber-50 px-3 py-2 text-sm text-amber-700 dark:bg-amber-500/10 dark:text-amber-300"
              >
                Active tool: {@active_tool}
              </div>

              <div
                :if={@current_thinking}
                class="rounded-xl bg-zinc-50 px-3 py-3 text-sm text-zinc-600 dark:bg-zinc-950/70 dark:text-zinc-300"
              >
                <p class="mb-2 font-medium text-base-content">Thinking</p>
                <pre class="whitespace-pre-wrap">{@current_thinking}</pre>
              </div>

              <div class="min-h-40 rounded-xl bg-zinc-950 px-4 py-3 text-sm text-zinc-100">
                <pre class="whitespace-pre-wrap leading-6">{if @live_output == "", do: "Waiting for live output...", else: @live_output}</pre>
              </div>

              <div
                :if={@run.error}
                class="rounded-xl border border-red-200 bg-red-50 px-3 py-3 text-sm text-red-700 dark:border-red-900/70 dark:bg-red-500/10 dark:text-red-300"
              >
                <div class="mb-3 flex flex-wrap items-center gap-2">
                  <p class="font-medium">Failure</p>
                  <span :if={@run.failure_label} class="badge badge-error badge-sm">
                    {@run.failure_label}
                  </span>
                  <span :if={@run.failure_retryable} class="badge badge-warning badge-sm">
                    Retryable
                  </span>
                </div>

                <p :if={@run.failure_recovery_hint} class="mb-3 leading-6">
                  {@run.failure_recovery_hint}
                </p>

                <pre class="whitespace-pre-wrap">{@run.error}</pre>

                <dl
                  :if={failure_detail_rows(@run) != []}
                  class="mt-3 divide-y divide-red-200/70 rounded-lg border border-red-200/70 text-xs dark:divide-red-900/70 dark:border-red-900/70"
                >
                  <div
                    :for={{label, value} <- failure_detail_rows(@run)}
                    class="flex items-start justify-between gap-4 px-3 py-2"
                  >
                    <dt class="font-medium">{label}</dt>
                    <dd class="text-right">{value}</dd>
                  </div>
                </dl>
              </div>

              <div
                :if={@run.result}
                class="rounded-xl bg-emerald-50 px-3 py-3 text-sm text-emerald-700 dark:bg-emerald-500/10 dark:text-emerald-300"
              >
                <p class="mb-2 font-medium">Final Result</p>
                <pre class="whitespace-pre-wrap">{@run.result}</pre>
              </div>
            </div>
          </section>

          <section class="rounded-2xl border border-zinc-200 bg-white shadow-sm dark:border-zinc-800 dark:bg-zinc-900">
            <div class="border-b border-zinc-200 px-5 py-4 dark:border-zinc-800">
              <h2 class="text-lg font-semibold text-base-content">Tool Activity</h2>
              <p class="text-sm text-base-content/60">
                Live tool execution events from the runtime stream.
              </p>
            </div>

            <div
              id="tool-events"
              phx-update="stream"
              class="divide-y divide-zinc-200 dark:divide-zinc-800"
            >
              <div
                id="tool-events-empty"
                class="hidden only:block px-5 py-8 text-center text-sm text-base-content/50"
              >
                No live tool events yet.
              </div>

              <div :for={{dom_id, event} <- @streams.tool_events} id={dom_id} class="px-5 py-4">
                <div class="flex items-center justify-between gap-3">
                  <div>
                    <p class="font-medium text-base-content">{event.tool_name}</p>
                    <p class="mt-1 text-xs text-base-content/50">
                      {tool_event_label(event)} · {format_datetime(event.inserted_at)}
                    </p>
                  </div>

                  <span class={tool_event_badge(event.type)}>{format_atom(event.type)}</span>
                </div>

                <div :if={event.duration_ms} class="mt-2 text-xs text-base-content/50">
                  Duration: {event.duration_ms}ms
                </div>

                <div
                  :if={event.result}
                  class="mt-2 rounded-xl bg-zinc-50 px-3 py-2 text-xs text-zinc-600 dark:bg-zinc-950/70 dark:text-zinc-300"
                >
                  {event.result}
                </div>
              </div>
            </div>
          </section>

          <section class="rounded-2xl border border-zinc-200 bg-white shadow-sm dark:border-zinc-800 dark:bg-zinc-900">
            <div class="border-b border-zinc-200 px-5 py-4 dark:border-zinc-800">
              <h2 class="text-lg font-semibold text-base-content">Runtime Metadata</h2>
            </div>

            <dl class="divide-y divide-zinc-200 text-sm dark:divide-zinc-800">
              <div class="flex items-start justify-between gap-4 px-5 py-4">
                <dt class="text-base-content/50">Runtime Instance</dt>
                <dd class="text-right font-medium text-base-content">
                  {@run.runtime_instance_id || "-"}
                </dd>
              </div>
              <div class="flex items-start justify-between gap-4 px-5 py-4">
                <dt class="text-base-content/50">Request ID</dt>
                <dd class="text-right font-medium text-base-content">
                  {@run.request_id || "-"}
                </dd>
              </div>
              <div class="flex items-start justify-between gap-4 px-5 py-4">
                <dt class="text-base-content/50">Deployment Visibility</dt>
                <dd class="text-right font-medium text-base-content">
                  {run_visibility(@run)}
                </dd>
              </div>
            </dl>
          </section>
        </div>
      </section>
    </div>
    """
  end

  defp load_run!(id) do
    Agents.get_agent_run!(
      id,
      load: [
        :agent,
        :deployment,
        :requested_by_user,
        :requested_by_team_member,
        :parent_run,
        :failure_category,
        :failure_label,
        :failure_retryable,
        :failure_recovery_hint,
        :output_count,
        :procurement_source_output_count,
        :bid_output_count,
        child_runs: [:deployment]
      ]
    )
  end

  defp maybe_subscribe(%{state: state} = run) when state in [:pending, :running] do
    Phoenix.PubSub.subscribe(
      GnomeGarden.PubSub,
      "agent_stream:#{run.runtime_instance_id || run.id}"
    )
  end

  defp maybe_subscribe(_run), do: :ok

  defp unique_event_id, do: "tool-event-#{System.unique_integer([:positive])}"

  defp requester_label(%{requested_by_team_member: %{display_name: display_name}}),
    do: display_name

  defp requester_label(%{requested_by_user: %{email: email}}), do: email
  defp requester_label(_run), do: "System"

  defp template_label(%{agent: %{template: template}}), do: template
  defp template_label(_run), do: "-"

  defp pi_template?(%{agent: %{template: "pi_" <> _}}), do: true
  defp pi_template?(_), do: false

  defp run_visibility(%{deployment: %{visibility: visibility}}), do: format_atom(visibility)
  defp run_visibility(_run), do: "-"

  defp failure_detail_rows(%{failure_details: details}) when is_map(details) do
    [
      {"Phase", failure_detail_value(details, :phase)},
      {"Category", failure_detail_value(details, :category)},
      {"Type", failure_detail_value(details, :type)},
      {"Kind", failure_detail_value(details, :kind)}
    ]
    |> Enum.reject(fn {_label, value} -> is_nil(value) or value == "" end)
  end

  defp failure_detail_rows(_run), do: []

  defp failure_detail_value(details, key) do
    details
    |> metadata_value(key)
    |> case do
      value when is_binary(value) -> value
      value when is_atom(value) -> format_atom(value)
      value when is_boolean(value) -> to_string(value)
      nil -> nil
      value -> inspect(value)
    end
  end

  defp short_id(id), do: String.slice(id, 0, 8)

  defp tool_event_label(%{type: :tool_start}), do: "started"
  defp tool_event_label(%{type: :tool_complete}), do: "completed"
  defp tool_event_label(_event), do: "event"

  defp tool_event_badge(:tool_start), do: "badge badge-info badge-sm"
  defp tool_event_badge(:tool_complete), do: "badge badge-success badge-sm"
  defp tool_event_badge(_type), do: "badge badge-ghost badge-sm"

  defp message_role_badge(:user), do: "badge badge-info badge-sm"
  defp message_role_badge(:assistant), do: "badge badge-success badge-sm"
  defp message_role_badge(:system), do: "badge badge-warning badge-sm"
  defp message_role_badge(:tool_call), do: "badge badge-secondary badge-sm"
  defp message_role_badge(:tool_result), do: "badge badge-ghost badge-sm"
  defp message_role_badge(_role), do: "badge badge-ghost badge-sm"

  defp output_type_badge(:procurement_source), do: "badge badge-info badge-sm"
  defp output_type_badge(:bid), do: "badge badge-secondary badge-sm"
  defp output_type_badge(:finding), do: "badge badge-accent badge-sm"
  defp output_type_badge(_type), do: "badge badge-ghost badge-sm"

  defp output_type_label(:procurement_source), do: "procurement source"
  defp output_type_label(:bid), do: "bid"
  defp output_type_label(:finding), do: "finding"
  defp output_type_label(type), do: format_atom(type)

  defp output_event_badge(:created), do: "badge badge-success badge-sm"
  defp output_event_badge(:existing), do: "badge badge-ghost badge-sm"
  defp output_event_badge(:updated), do: "badge badge-warning badge-sm"
  defp output_event_badge(_event), do: "badge badge-ghost badge-sm"

  attr :diagnostics, :map, required: true

  defp scan_diagnostics_panel(assigns) do
    ~H"""
    <div class="mt-4 rounded-xl border border-zinc-200 bg-zinc-50/80 p-3 dark:border-zinc-800 dark:bg-zinc-950/60">
      <div class="flex flex-wrap items-center gap-2">
        <p class="text-xs font-semibold uppercase tracking-[0.16em] text-base-content/50">
          Scan Diagnostics
        </p>
        <span class="badge badge-ghost badge-sm">{diagnosis_label(@diagnostics)}</span>
      </div>

      <div :if={diagnostic_saved_examples(@diagnostics) != []} class="mt-3">
        <p class="text-xs font-medium text-base-content/60">Saved examples</p>
        <ul class="mt-1 space-y-1 text-xs text-base-content/70">
          <li :for={title <- diagnostic_saved_examples(@diagnostics)}>{title}</li>
        </ul>
      </div>

      <div :if={diagnostic_top_unsaved(@diagnostics) != []} class="mt-3">
        <p class="text-xs font-medium text-base-content/60">Top unsaved candidates</p>
        <div class="mt-2 space-y-2">
          <div
            :for={candidate <- diagnostic_top_unsaved(@diagnostics)}
            class="rounded-lg border border-zinc-200 bg-white p-3 text-xs dark:border-zinc-800 dark:bg-zinc-900"
          >
            <div class="flex flex-col gap-2 sm:flex-row sm:items-start sm:justify-between">
              <div class="min-w-0">
                <p class="font-medium text-base-content">{diagnostic_title(candidate)}</p>
                <p class="mt-1 text-base-content/55">{diagnostic_reason(candidate)}</p>
              </div>
              <div class="flex shrink-0 flex-wrap gap-1">
                <span class="badge badge-sm">{diagnostic_score(candidate)}</span>
                <span class="badge badge-ghost badge-sm">{diagnostic_tier(candidate)}</span>
                <span class="badge badge-outline badge-sm">
                  {diagnostic_packet_status(candidate)}
                </span>
              </div>
            </div>

            <p :if={diagnostic_terms(candidate, :matched) != ""} class="mt-2 text-base-content/60">
              Matched: {diagnostic_terms(candidate, :matched)}
            </p>
            <p :if={diagnostic_terms(candidate, :risk_flags) != ""} class="mt-1 text-base-content/60">
              Risks: {diagnostic_terms(candidate, :risk_flags)}
            </p>
            <p :if={diagnostic_terms(candidate, :rejected) != ""} class="mt-1 text-base-content/60">
              Rejected terms: {diagnostic_terms(candidate, :rejected)}
            </p>
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp output_summary_details(output) do
    parts =
      [
        metadata_value(output.metadata, :url),
        score_summary(output.metadata)
      ]
      |> Enum.reject(&is_nil/1)

    case parts do
      [] -> nil
      _ -> Enum.join(parts, " · ")
    end
  end

  defp scan_diagnostics(%{metadata: metadata}) when is_map(metadata) do
    case metadata_value(metadata, :diagnostics) do
      diagnostics when is_map(diagnostics) -> diagnostics
      _ -> nil
    end
  end

  defp scan_diagnostics(_output), do: nil

  defp diagnosis_label(diagnostics) do
    diagnostics
    |> metadata_value(:diagnosis)
    |> case do
      nil -> "No diagnosis"
      value -> value |> to_string() |> String.replace("_", " ")
    end
  end

  defp diagnostic_saved_examples(diagnostics) do
    case metadata_value(diagnostics, :saved_examples) do
      values when is_list(values) -> values
      _ -> []
    end
  end

  defp diagnostic_top_unsaved(diagnostics) do
    case metadata_value(diagnostics, :top_unsaved) do
      values when is_list(values) -> values
      _ -> []
    end
  end

  defp diagnostic_title(candidate), do: metadata_value(candidate, :title) || "Untitled"
  defp diagnostic_reason(candidate), do: metadata_value(candidate, :reason) || "Not saved"

  defp diagnostic_score(candidate) do
    case metadata_value(candidate, :score_total) do
      nil -> "score -"
      score -> "score #{score}"
    end
  end

  defp diagnostic_tier(candidate), do: metadata_value(candidate, :score_tier) || "tier -"

  defp diagnostic_packet_status(candidate),
    do: metadata_value(candidate, :packet_status) || "packet -"

  defp diagnostic_terms(candidate, key) do
    case metadata_value(candidate, key) do
      values when is_list(values) -> Enum.join(values, ", ")
      value when is_binary(value) -> value
      _ -> ""
    end
  end

  defp metadata_value(metadata, key) when is_map(metadata) do
    cond do
      Map.has_key?(metadata, key) -> Map.get(metadata, key)
      Map.has_key?(metadata, Atom.to_string(key)) -> Map.get(metadata, Atom.to_string(key))
      true -> nil
    end
  end

  defp metadata_value(_metadata, _key), do: nil

  defp score_summary(metadata) do
    case {metadata_value(metadata, :score_total), metadata_value(metadata, :score_tier)} do
      {nil, nil} -> nil
      {score, nil} -> "score #{score}"
      {score, tier} -> "score #{score} (#{tier})"
    end
  end

  defp output_path(%{output_type: :bid, output_id: output_id}) do
    case Acquisition.get_finding_by_source_bid(output_id) do
      {:ok, finding} -> ~p"/acquisition/findings/#{finding.id}"
      _ -> ~p"/acquisition/findings?family=procurement"
    end
  end

  defp output_path(%{output_type: :finding, output_id: output_id}) do
    case Acquisition.get_finding(output_id) do
      {:ok, finding} -> ~p"/acquisition/findings/#{finding.id}"
      _ -> ~p"/acquisition/findings"
    end
  end

  defp output_path(%{output_type: :procurement_source, output_id: _output_id}),
    do: ~p"/acquisition/sources"

  defp output_path(_output), do: nil

  defp output_action_label(%{output_type: :bid}), do: "Open Finding"
  defp output_action_label(%{output_type: :finding}), do: "Open Finding"
  defp output_action_label(%{output_type: :procurement_source}), do: "Open Source"
  defp output_action_label(_output), do: "Open"

  defp error_message(error) when is_exception(error), do: Exception.message(error)
  defp error_message(error) when is_binary(error), do: error
  defp error_message(error), do: inspect(error)

  defp format_atom(nil), do: "-"
  defp format_atom(atom), do: atom |> to_string() |> String.replace("_", " ")

  defp format_datetime(nil), do: "-"
  defp format_datetime(datetime), do: Calendar.strftime(datetime, "%b %d, %H:%M:%S")

  defp run_state_badge(:pending), do: "badge badge-ghost badge-sm"
  defp run_state_badge(:running), do: "badge badge-info badge-sm"
  defp run_state_badge(:completed), do: "badge badge-success badge-sm"
  defp run_state_badge(:failed), do: "badge badge-error badge-sm"
  defp run_state_badge(:cancelled), do: "badge badge-warning badge-sm"
  defp run_state_badge(_state), do: "badge badge-ghost badge-sm"
end
