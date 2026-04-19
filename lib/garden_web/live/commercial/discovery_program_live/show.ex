defmodule GnomeGardenWeb.Commercial.DiscoveryProgramLive.Show do
  use GnomeGardenWeb, :live_view

  import GnomeGardenWeb.Commercial.Helpers

  alias GnomeGarden.Agents
  alias GnomeGarden.Commercial

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    discovery_program = load_discovery_program!(id, socket.assigns.current_user)

    {:ok,
     socket
     |> assign(:page_title, discovery_program.name)
     |> assign(:discovery_program, discovery_program)
     |> assign(:latest_run, load_latest_run(discovery_program))
     |> assign(:targets, load_targets(id, socket.assigns.current_user))
     |> assign(:observations, load_observations(id, socket.assigns.current_user))}
  end

  @impl true
  def handle_event("transition", %{"action" => action}, socket) do
    discovery_program = socket.assigns.discovery_program

    case transition_program(
           discovery_program,
           String.to_existing_atom(action),
           socket.assigns.current_user
         ) do
      {:ok, _updated_program} ->
        refreshed_program =
          load_discovery_program!(discovery_program.id, socket.assigns.current_user)

        {:noreply,
         socket
         |> assign(:discovery_program, refreshed_program)
         |> assign(:targets, load_targets(discovery_program.id, socket.assigns.current_user))
         |> assign(
           :observations,
           load_observations(discovery_program.id, socket.assigns.current_user)
         )
         |> put_flash(:info, "Discovery program updated")}

      {:error, error} ->
        {:noreply,
         put_flash(socket, :error, "Could not update discovery program: #{inspect(error)}")}
    end
  end

  @impl true
  def handle_event("run_now", _params, socket) do
    discovery_program = socket.assigns.discovery_program

    case Commercial.launch_discovery_program(discovery_program,
           actor: socket.assigns.current_user
         ) do
      {:ok, %{program: refreshed_program, run: run}} ->
        {:noreply,
         socket
         |> assign(:discovery_program, refreshed_program)
         |> assign(:latest_run, load_latest_run(refreshed_program))
         |> assign(:targets, load_targets(discovery_program.id, socket.assigns.current_user))
         |> assign(
           :observations,
           load_observations(discovery_program.id, socket.assigns.current_user)
         )
         |> put_flash(:info, "Started discovery run #{short_id(run.id)}.")}

      {:error, :active_run_exists} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           "This discovery program already has an active run. Wait for it to finish before launching another."
         )}

      {:error, error} ->
        {:noreply, put_flash(socket, :error, "Could not start discovery run: #{inspect(error)}")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.page class="pb-8">
      <.page_header eyebrow="Commercial">
        {@discovery_program.name}
        <:subtitle>
          <span class="inline-flex items-center gap-2">
            <.status_badge status={@discovery_program.status_variant}>
              {format_atom(@discovery_program.status)}
            </.status_badge>
            <span class="text-zinc-400 dark:text-zinc-500">/</span>
            <span>{format_atom(@discovery_program.program_type)}</span>
          </span>
        </:subtitle>
        <:actions>
          <.button
            :if={program_runnable?(@discovery_program)}
            phx-click="run_now"
            variant="primary"
          >
            <.icon name="hero-play" class="size-4" /> Run Discovery
          </.button>
          <.button navigate={~p"/commercial/observations"}>
            <.icon name="hero-document-magnifying-glass" class="size-4" /> Observations
          </.button>
          <.button navigate={~p"/commercial/discovery-programs"}>
            <.icon name="hero-arrow-left" class="size-4" /> Back
          </.button>
          <.button navigate={~p"/commercial/discovery-programs/#{@discovery_program}/edit"}>
            <.icon name="hero-pencil-square" class="size-4" /> Edit
          </.button>
        </:actions>
      </.page_header>

      <.section
        title="Program Actions"
        description="Keep the discovery motion explicitly active, paused, or archived instead of burying that decision inside agent config."
      >
        <div class="flex flex-wrap gap-3">
          <.button
            :for={action <- program_actions(@discovery_program)}
            phx-click="transition"
            phx-value-action={action.action}
            variant={action.variant}
          >
            <.icon name={action.icon} class="size-4" /> {action.label}
          </.button>
        </div>
      </.section>

      <div class="grid gap-6 lg:grid-cols-2">
        <.section title="Program Scope">
          <div class="grid gap-5 sm:grid-cols-2">
            <.property_item label="Priority" value={format_atom(@discovery_program.priority)} />
            <.property_item label="Cadence" value={"Every #{@discovery_program.cadence_hours} hours"} />
            <.property_item
              label="Cadence Status"
              value={@discovery_program.run_status_label}
              badge={@discovery_program.run_status_variant}
            />
            <.property_item
              label="Target Regions"
              value={summary_list(@discovery_program.target_regions, "No regions defined")}
            />
            <.property_item
              label="Target Industries"
              value={summary_list(@discovery_program.target_industries, "No industries defined")}
            />
            <.property_item
              label="Watch Channels"
              value={summary_list(@discovery_program.watch_channels, "No channels defined")}
            />
            <.property_item
              label="Last Run"
              value={format_datetime(@discovery_program.last_run_at)}
            />
          </div>
        </.section>

        <.section title="Program Output">
          <div class="grid gap-5 sm:grid-cols-2">
            <.property_item
              label="Targets"
              value={Integer.to_string(@discovery_program.target_account_count)}
            />
            <.property_item
              label="Review Backlog"
              value={Integer.to_string(@discovery_program.review_target_count)}
            />
            <.property_item
              label="Observations"
              value={Integer.to_string(@discovery_program.observation_count)}
            />
            <.property_item
              label="Latest Observed"
              value={format_datetime(@discovery_program.latest_observed_at)}
            />
          </div>
        </.section>
      </div>

      <.section
        title="Latest Agent Run"
        description="Discovery programs now launch through the durable agent deployment/run stack, not a hidden ad hoc task."
      >
        <div
          :if={@latest_run}
          class="rounded-2xl border border-zinc-200 bg-zinc-50/70 p-4 dark:border-white/10 dark:bg-white/[0.03]"
        >
          <div class="flex flex-wrap items-start justify-between gap-4">
            <div class="space-y-1">
              <p class="text-sm font-semibold text-zinc-900 dark:text-white">
                Run {short_id(@latest_run.id)}
              </p>
              <p class="text-xs text-zinc-500 dark:text-zinc-400">
                {run_deployment_label(@latest_run)}
              </p>
              <p class="text-xs text-zinc-400 dark:text-zinc-500">
                Started {format_datetime(@latest_run.started_at || @latest_run.inserted_at)}
              </p>
            </div>

            <div class="flex items-center gap-3">
              <.status_badge status={run_state_variant(@latest_run.state)}>
                {format_atom(@latest_run.state)}
              </.status_badge>

              <.link
                navigate={~p"/console/agents/runs/#{@latest_run.id}"}
                class="text-sm font-medium text-emerald-600 hover:text-emerald-500 dark:text-emerald-300"
              >
                Open run
              </.link>
            </div>
          </div>
        </div>

        <div :if={is_nil(@latest_run)}>
          <.empty_state
            icon="hero-cpu-chip"
            title="No run launched yet"
            description="Use Run Discovery to launch this program onto the real agent run stack."
          />
        </div>
      </.section>

      <.section :if={@discovery_program.description} title="Description">
        <p class="whitespace-pre-wrap text-sm leading-6 text-zinc-600 dark:text-zinc-300">
          {@discovery_program.description}
        </p>
      </.section>

      <.section :if={@discovery_program.notes} title="Notes">
        <p class="whitespace-pre-wrap text-sm leading-6 text-zinc-600 dark:text-zinc-300">
          {@discovery_program.notes}
        </p>
      </.section>

      <div class="grid gap-6 lg:grid-cols-2">
        <.section
          title="Attached Targets"
          description="These accounts came from this discovery motion and are still in the broad review layer."
        >
          <div :if={Enum.empty?(@targets)}>
            <.empty_state
              icon="hero-magnifying-glass"
              title="No targets yet"
              description="Once scanners or operators attach companies to this program, they will appear here."
            />
          </div>

          <div :if={!Enum.empty?(@targets)} class="space-y-3">
            <.link
              :for={target <- @targets}
              navigate={~p"/commercial/targets/#{target}"}
              class="flex items-start justify-between rounded-2xl border border-zinc-200 bg-zinc-50/70 px-4 py-4 transition hover:border-emerald-300 dark:border-white/10 dark:bg-white/[0.03] dark:hover:border-emerald-400/40"
            >
              <div class="space-y-1">
                <p class="font-medium text-zinc-900 dark:text-white">{target.name}</p>
                <p class="text-sm text-zinc-500 dark:text-zinc-400">
                  {target.website_domain || "No website domain"}
                </p>
                <p class="text-xs text-zinc-400 dark:text-zinc-500">
                  Intent {target.intent_score} · Fit {target.fit_score}
                </p>
              </div>
              <.status_badge status={target.status_variant}>
                {format_atom(target.status)}
              </.status_badge>
            </.link>
          </div>
        </.section>

        <.section
          title="Recent Observations"
          description="Evidence captured against this discovery motion before anything becomes a formal signal."
        >
          <div :if={Enum.empty?(@observations)}>
            <.empty_state
              icon="hero-document-magnifying-glass"
              title="No observations yet"
              description="Observation evidence will appear here once scanners attach findings to the program."
            />
          </div>

          <div :if={!Enum.empty?(@observations)} class="space-y-3">
            <div
              :for={observation <- @observations}
              class="rounded-2xl border border-zinc-200 bg-zinc-50/70 px-4 py-4 dark:border-white/10 dark:bg-white/[0.03]"
            >
              <div class="flex flex-wrap items-start justify-between gap-3">
                <div class="space-y-2">
                  <div class="flex flex-wrap gap-2">
                    <.tag color={:zinc}>{format_atom(observation.observation_type)}</.tag>
                    <.tag color={:sky}>{format_atom(observation.source_channel)}</.tag>
                  </div>
                  <p class="font-medium text-zinc-900 dark:text-white">{observation.summary}</p>
                  <p class="text-xs text-zinc-400 dark:text-zinc-500">
                    {format_datetime(observation.observed_at || observation.inserted_at)}
                  </p>
                </div>
                <.link
                  :if={observation.source_url}
                  href={observation.source_url}
                  target="_blank"
                  class="text-sm font-medium text-emerald-600 hover:text-emerald-500 dark:text-emerald-300"
                >
                  Source
                </.link>
                <.link
                  navigate={~p"/commercial/observations/#{observation}"}
                  class="text-sm font-medium text-sky-600 hover:text-sky-500 dark:text-sky-300"
                >
                  Details
                </.link>
              </div>
            </div>
          </div>
        </.section>
      </div>
    </.page>
    """
  end

  attr :label, :string, required: true
  attr :value, :string, required: true
  attr :badge, :atom, default: nil

  defp property_item(assigns) do
    ~H"""
    <div class="space-y-1">
      <p class="text-xs font-semibold uppercase tracking-[0.2em] text-zinc-400 dark:text-zinc-500">
        {@label}
      </p>
      <p :if={is_nil(@badge)} class="text-sm font-medium text-zinc-900 dark:text-white">{@value}</p>
      <.status_badge :if={@badge} status={@badge}>{@value}</.status_badge>
    </div>
    """
  end

  defp load_discovery_program!(id, actor) do
    case Commercial.get_discovery_program(
           id,
           actor: actor,
           load: [
             :status_variant,
             :priority_variant,
             :is_due_to_run,
             :run_status_variant,
             :run_status_label,
             :target_account_count,
             :review_target_count,
             :observation_count,
             :latest_observed_at
           ]
         ) do
      {:ok, program} -> program
      {:error, error} -> raise "failed to load discovery program #{id}: #{inspect(error)}"
    end
  end

  defp load_targets(id, actor) do
    case Commercial.list_target_accounts_for_discovery_program(
           id,
           actor: actor,
           load: [:status_variant]
         ) do
      {:ok, targets} -> Enum.take(targets, 8)
      {:error, error} -> raise "failed to load discovery targets: #{inspect(error)}"
    end
  end

  defp load_observations(id, actor) do
    case Commercial.list_target_observations_for_discovery_program(id, actor: actor) do
      {:ok, observations} -> Enum.take(observations, 8)
      {:error, error} -> raise "failed to load discovery observations: #{inspect(error)}"
    end
  end

  defp load_latest_run(%{metadata: metadata}) when is_map(metadata) do
    case Map.get(metadata, "last_agent_run_id") || Map.get(metadata, :last_agent_run_id) do
      run_id when is_binary(run_id) ->
        case Agents.get_agent_run(run_id, load: [:agent, :deployment]) do
          {:ok, run} -> run
          {:error, _error} -> nil
        end

      _ ->
        nil
    end
  end

  defp load_latest_run(_program), do: nil

  defp summary_list([], empty_label), do: empty_label
  defp summary_list(values, _empty_label), do: Enum.join(values, ", ")

  defp program_runnable?(%{status: :archived}), do: false
  defp program_runnable?(_program), do: true

  defp run_state_variant(:completed), do: :success
  defp run_state_variant(:running), do: :info
  defp run_state_variant(:failed), do: :error
  defp run_state_variant(:cancelled), do: :warning
  defp run_state_variant(_state), do: :default

  defp run_deployment_label(%{deployment: %{name: name}}), do: name
  defp run_deployment_label(_run), do: "Commercial Target Discovery"

  defp short_id(id), do: String.slice(id, 0, 8)

  defp program_actions(%{status: :draft}) do
    [
      %{action: "activate", label: "Activate", icon: "hero-play-circle", variant: "primary"},
      %{action: "archive", label: "Archive", icon: "hero-archive-box", variant: nil}
    ]
  end

  defp program_actions(%{status: :active}) do
    [
      %{action: "pause", label: "Pause", icon: "hero-pause-circle", variant: nil},
      %{action: "archive", label: "Archive", icon: "hero-archive-box", variant: nil}
    ]
  end

  defp program_actions(%{status: :paused}) do
    [
      %{action: "activate", label: "Resume", icon: "hero-play-circle", variant: "primary"},
      %{action: "archive", label: "Archive", icon: "hero-archive-box", variant: nil}
    ]
  end

  defp program_actions(%{status: :archived}) do
    [
      %{action: "reopen", label: "Reopen", icon: "hero-arrow-path", variant: "primary"}
    ]
  end

  defp program_actions(_program), do: []

  defp transition_program(program, :activate, actor),
    do: Commercial.activate_discovery_program(program, actor: actor)

  defp transition_program(program, :pause, actor),
    do: Commercial.pause_discovery_program(program, actor: actor)

  defp transition_program(program, :archive, actor),
    do: Commercial.archive_discovery_program(program, actor: actor)

  defp transition_program(program, :reopen, actor),
    do: Commercial.reopen_discovery_program(program, actor: actor)
end
