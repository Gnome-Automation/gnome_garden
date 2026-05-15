defmodule GnomeGardenWeb.Acquisition.DashboardLive do
  use GnomeGardenWeb, :live_view

  import GnomeGardenWeb.Execution.Helpers, only: [format_atom: 1, format_datetime: 1]

  alias GnomeGarden.Acquisition
  alias GnomeGarden.Acquisition.PilotSeeds
  alias GnomeGarden.Agents

  @preview_limit 10

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Acquisition Dashboard")
     |> load_dashboard()}
  end

  @impl true
  def handle_event("seed_pilot", _params, socket) do
    case PilotSeeds.ensure_defaults(actor: socket.assigns.current_user) do
      {:ok, %{programs: programs, sources: sources}} ->
        {:noreply,
         socket
         |> load_dashboard()
         |> put_flash(
           :info,
           "Seeded #{length(programs)} discovery programs and #{length(sources)} procurement sources."
         )}

      {:error, error} ->
        {:noreply, put_flash(socket, :error, "Could not seed pilot defaults: #{inspect(error)}")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.page class="pb-8">
      <.page_header eyebrow="Acquisition">
        Lead System Dashboard
        <:subtitle>
          One place to seed the pilot, launch the next source or program, review saved leads, and judge Pi/Jido runs by what they produced.
        </:subtitle>
        <:actions>
          <.button phx-click="seed_pilot" variant="primary">
            Seed Pilot Defaults
          </.button>
          <.button navigate={~p"/acquisition/findings"}>
            Review Queue
          </.button>
        </:actions>
      </.page_header>

      <div class="grid gap-2 sm:grid-cols-2 xl:grid-cols-4">
        <.stat_card
          title="Review"
          value={Integer.to_string(@counts.review_findings)}
          description="saved leads waiting"
          icon="hero-queue-list"
          accent="emerald"
        />
        <.stat_card
          title="Sources"
          value={Integer.to_string(@counts.ready_sources)}
          description="ready to scan"
          icon="hero-globe-alt"
          accent="sky"
        />
        <.stat_card
          title="Programs"
          value={Integer.to_string(@counts.ready_programs)}
          description="ready to launch"
          icon="hero-radar"
          accent="amber"
        />
        <.stat_card
          title="Runs"
          value={Integer.to_string(@counts.active_runs)}
          description="running now"
          icon="hero-bolt"
          accent="rose"
        />
      </div>

      <.section
        title="Next Objective"
        description="For the next seven days, the goal is simple: produce reviewable automation leads and learn which runtime does that reliably."
      >
        <div class="grid gap-3 lg:grid-cols-[minmax(0,1fr)_18rem]">
          <div class="space-y-3">
            <div class="rounded-lg border border-base-content/10 bg-base-200/60 p-3">
              <p class="text-xs font-semibold uppercase tracking-wider text-base-content/50">
                Today
              </p>
              <p class="mt-1 text-base font-semibold text-base-content">
                Launch one ready source or discovery program, then review every saved finding before starting another run.
              </p>
            </div>

            <div class="grid gap-2 sm:grid-cols-3">
              <.objective_step
                label="1"
                title="Seed"
                text="Create the pilot lanes if they are missing."
              />
              <.objective_step label="2" title="Run" text="Use one source or one program at a time." />
              <.objective_step
                label="3"
                title="Review"
                text="Accept, reject, park, or suppress saved findings."
              />
            </div>
          </div>

          <div class="grid content-start gap-2">
            <.button navigate={~p"/acquisition/sources?bucket=ready"} variant="primary">
              Open Ready Sources
            </.button>
            <.button navigate={~p"/acquisition/programs?bucket=ready"}>
              Open Ready Programs
            </.button>
            <.button navigate={~p"/console/agents"}>
              Open Run Console
            </.button>
          </div>
        </div>
      </.section>

      <div class="grid gap-3 xl:grid-cols-2">
        <.section
          title="Lead Review"
          description="The queue is the source of truth for whether the system found anything useful."
        >
          <div :if={@review_findings == []}>
            <.empty_state
              icon="hero-inbox"
              title="No review findings yet"
              description="Launch a ready source or discovery program, then come back here when outputs are saved."
            />
          </div>

          <div :if={@review_findings != []} class="divide-y divide-base-content/10">
            <.finding_row :for={finding <- @review_findings} finding={finding} />
          </div>

          <div class="mt-3">
            <.button navigate={~p"/acquisition/findings"} variant="primary">
              Work Review Queue
            </.button>
          </div>
        </.section>

        <.section
          title="Run Next"
          description="Start with ready lanes. Anything blocked belongs in configuration before it consumes runtime."
        >
          <div class="grid gap-4 md:grid-cols-2">
            <.lane_list
              title="Sources"
              items={@ready_sources}
              path={~p"/acquisition/sources?bucket=ready"}
            />
            <.lane_list
              title="Programs"
              items={@ready_programs}
              path={~p"/acquisition/programs?bucket=ready"}
            />
          </div>
        </.section>
      </div>

      <div class="grid gap-3 xl:grid-cols-2">
        <.section
          title="Runtime Evidence"
          description="Pi and Jido should be judged by saved outputs, clean completion, and operator review value."
        >
          <div :if={@recent_runs == []}>
            <.empty_state
              icon="hero-cpu-chip"
              title="No runs yet"
              description="Runs will appear here after a source or program is launched."
            />
          </div>

          <div :if={@recent_runs != []} class="divide-y divide-base-content/10">
            <.run_row :for={run <- @recent_runs} run={run} />
          </div>
        </.section>

        <.section
          title="Learning Loop"
          description="You do not need abstract metrics. Every review decision either creates a real lead or teaches the system what to ignore."
        >
          <div class="grid gap-2">
            <.loop_item
              title="Accept"
              text="Promotes a finding only after the evidence is strong enough for follow-up."
            />
            <.loop_item
              title="Reject"
              text="Stores the reason so repeated weak patterns can be filtered."
            />
            <.loop_item
              title="Park"
              text="Keeps maybe-later leads out of the active queue without losing context."
            />
            <.loop_item
              title="Suppress"
              text="Turns noisy source patterns into targeting feedback."
            />
          </div>

          <div class="mt-3 flex flex-wrap gap-2">
            <.button navigate={~p"/acquisition/findings?family=discovery&queue=review"}>
              Review Discovery
            </.button>
            <.button navigate={~p"/procurement/targeting"}>
              Procurement Targeting
            </.button>
          </div>
        </.section>
      </div>
    </.page>
    """
  end

  attr :label, :string, required: true
  attr :title, :string, required: true
  attr :text, :string, required: true

  defp objective_step(assigns) do
    ~H"""
    <div class="rounded-lg border border-base-content/10 bg-base-200/50 p-3">
      <div class="flex items-start gap-3">
        <span class="flex size-7 shrink-0 items-center justify-center rounded-md bg-primary/10 text-sm font-semibold text-primary">
          {@label}
        </span>
        <div class="min-w-0">
          <p class="font-semibold text-base-content">{@title}</p>
          <p class="mt-0.5 text-sm leading-5 text-base-content/65">{@text}</p>
        </div>
      </div>
    </div>
    """
  end

  attr :finding, :map, required: true

  defp finding_row(assigns) do
    ~H"""
    <div class="flex flex-col gap-2 py-3 sm:flex-row sm:items-start sm:justify-between">
      <div class="min-w-0">
        <div class="flex flex-wrap gap-1.5">
          <span class="badge badge-info badge-sm">{@finding.finding_family_label}</span>
          <span class="badge badge-outline badge-sm">{@finding.finding_type_label}</span>
          <span class="badge badge-ghost badge-sm">{@finding.confidence_label}</span>
        </div>
        <p class="mt-1 font-semibold text-base-content">{@finding.title}</p>
        <p class="mt-0.5 line-clamp-2 text-sm leading-5 text-base-content/60">
          {@finding.summary || "No summary saved."}
        </p>
      </div>
      <.button navigate={~p"/acquisition/findings/#{@finding.id}"} class="shrink-0">
        Review
      </.button>
    </div>
    """
  end

  attr :title, :string, required: true
  attr :items, :list, required: true
  attr :path, :string, required: true

  defp lane_list(assigns) do
    ~H"""
    <div class="min-w-0">
      <div class="mb-2 flex items-center justify-between gap-2">
        <p class="text-sm font-semibold text-base-content">{@title}</p>
        <.link navigate={@path} class="text-xs font-medium text-primary hover:underline">
          Open
        </.link>
      </div>
      <div
        :if={@items == []}
        class="rounded-lg border border-dashed border-base-content/15 p-3 text-sm text-base-content/55"
      >
        None ready.
      </div>
      <div :if={@items != []} class="space-y-2">
        <div :for={item <- @items} class="rounded-lg border border-base-content/10 bg-base-200/50 p-3">
          <p class="truncate text-sm font-semibold text-base-content">{item.name}</p>
          <p class="mt-0.5 text-xs text-base-content/55">
            {lane_note(item)}
          </p>
        </div>
      </div>
    </div>
    """
  end

  attr :run, :map, required: true

  defp run_row(assigns) do
    ~H"""
    <div class="flex flex-col gap-2 py-3 sm:flex-row sm:items-start sm:justify-between">
      <div class="min-w-0">
        <div class="flex flex-wrap gap-1.5">
          <span class="badge badge-outline badge-sm">{format_atom(@run.state)}</span>
          <span class="badge badge-ghost badge-sm">{output_label(@run.output_count)}</span>
        </div>
        <p class="mt-1 truncate font-semibold text-base-content">
          {(@run.deployment && @run.deployment.name) || (@run.agent && @run.agent.name) || "Agent run"}
        </p>
        <p class="mt-0.5 text-xs text-base-content/55">
          {format_datetime(@run.completed_at || @run.started_at || @run.inserted_at)}
        </p>
      </div>
      <.button navigate={~p"/console/agents/runs/#{@run.id}"} class="shrink-0">
        Evidence
      </.button>
    </div>
    """
  end

  attr :title, :string, required: true
  attr :text, :string, required: true

  defp loop_item(assigns) do
    ~H"""
    <div class="rounded-lg border border-base-content/10 bg-base-200/50 p-3">
      <p class="text-sm font-semibold text-base-content">{@title}</p>
      <p class="mt-0.5 text-sm leading-5 text-base-content/65">{@text}</p>
    </div>
    """
  end

  defp load_dashboard(socket) do
    actor = socket.assigns.current_user
    sources = list_sources(actor)
    programs = list_programs(actor)
    review_findings = list_review_findings(actor)
    active_runs = list_active_runs(actor)
    recent_runs = list_recent_runs(actor)

    socket
    |> assign(:ready_sources, sources |> Enum.filter(&scan_ready?/1) |> Enum.take(@preview_limit))
    |> assign(
      :ready_programs,
      programs |> Enum.filter(& &1.runnable) |> Enum.take(@preview_limit)
    )
    |> assign(:review_findings, Enum.take(review_findings, @preview_limit))
    |> assign(:recent_runs, Enum.take(recent_runs, @preview_limit))
    |> assign(:counts, %{
      review_findings: length(review_findings),
      ready_sources: Enum.count(sources, &scan_ready?/1),
      ready_programs: Enum.count(programs, & &1.runnable),
      active_runs: length(active_runs)
    })
  end

  defp list_sources(actor) do
    case Acquisition.list_console_sources(actor: actor) do
      {:ok, sources} -> sources
      {:error, _error} -> []
    end
  end

  defp list_programs(actor) do
    case Acquisition.list_console_programs(actor: actor) do
      {:ok, programs} -> programs
      {:error, _error} -> []
    end
  end

  defp list_review_findings(actor) do
    case Acquisition.list_review_findings(actor: actor) do
      {:ok, findings} -> findings
      {:error, _error} -> []
    end
  end

  defp list_active_runs(actor) do
    case Agents.list_active_agent_runs(actor: actor) do
      {:ok, runs} -> runs
      {:error, _error} -> []
    end
  end

  defp list_recent_runs(actor) do
    case Agents.list_recent_agent_runs(10, actor: actor) do
      {:ok, runs} -> runs
      {:error, _error} -> []
    end
  end

  defp scan_ready?(source) do
    source.runnable && (configured_source?(source) || agentic_source?(source))
  end

  defp configured_source?(%{procurement_source: %{config_status: status}})
       when status in [:configured, :scan_failed],
       do: true

  defp configured_source?(_source), do: false

  defp agentic_source?(%{procurement_source_id: source_id}) when is_binary(source_id), do: false

  defp agentic_source?(%{scan_strategy: strategy})
       when strategy in [:agentic, :deterministic],
       do: true

  defp agentic_source?(_source), do: false

  defp lane_note(%{review_finding_count: count}) when is_integer(count) and count > 0,
    do: "#{count} waiting in review"

  defp lane_note(%{last_run_at: nil}), do: "Not run yet"
  defp lane_note(%{last_run_at: value}), do: "Last run #{format_datetime(value)}"
  defp lane_note(_item), do: "Ready"

  defp output_label(1), do: "1 output"
  defp output_label(count) when is_integer(count), do: "#{count} outputs"
  defp output_label(_count), do: "0 outputs"
end
