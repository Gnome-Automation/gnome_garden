defmodule GnomeGardenWeb.Commercial.DiscoveryProgramLive.Index do
  use GnomeGardenWeb, :live_view
  use Cinder.UrlSync

  import Cinder.Refresh
  import GnomeGardenWeb.Commercial.Helpers

  alias GnomeGarden.Acquisition
  alias GnomeGarden.Commercial

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Discovery Programs")
     |> assign_counts()}
  end

  @impl true
  def handle_params(params, uri, socket) do
    socket = Cinder.UrlSync.handle_params(params, uri, socket)
    {:noreply, socket}
  end

  @impl true
  def handle_event("run_now", %{"id" => id}, socket) do
    with {:ok, discovery_program} <-
           Commercial.get_discovery_program(id, actor: socket.assigns.current_user),
         {:ok, %{run: run}} <-
           Commercial.launch_discovery_program(discovery_program,
             actor: socket.assigns.current_user
           ) do
      {:noreply,
       socket
       |> assign_counts()
       |> refresh_table("discovery-programs-table")
       |> put_flash(:info, "Started discovery run #{short_id(run.id)}.")}
    else
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
        Discovery Programs
        <:subtitle>
          Durable target-finder definitions for regions, industries, and search motions. Programs own the discovery backlog without confusing it with runtime-only agent state.
        </:subtitle>
        <:actions>
          <.button navigate={~p"/acquisition/findings?family=discovery"}>
            Discovery Intake
          </.button>
          <.button navigate={~p"/commercial/discovery-programs/new"} variant="primary">
            New Program
          </.button>
        </:actions>
      </.page_header>

      <div class="grid gap-4 md:grid-cols-4">
        <.stat_card
          title="Programs"
          value={Integer.to_string(@program_count)}
          description="Defined outbound and market-discovery motions."
          icon="hero-radar"
        />
        <.stat_card
          title="Active"
          value={Integer.to_string(@active_count)}
          description="Programs currently intended to drive discovery work."
          icon="hero-play-circle"
          accent="emerald"
        />
        <.stat_card
          title="Review Findings"
          value={Integer.to_string(@review_discovery_record_count)}
          description="Backlog of acquisition findings currently fed by these programs."
          icon="hero-magnifying-glass"
          accent="sky"
        />
        <.stat_card
          title="Pilot Ready"
          value={Integer.to_string(@pilot_ready_count)}
          description="Programs that are active and due for a manual run right now."
          icon="hero-bolt"
          accent="amber"
        />
      </div>

      <Cinder.collection
        id="discovery-programs-table"
        resource={GnomeGarden.Commercial.DiscoveryProgram}
        actor={@current_user}
        url_state={@url_state}
        theme={GnomeGardenWeb.CinderTheme}
        page_size={25}
        query_opts={[
          load: [
            :status_variant,
            :priority_variant,
            :is_due_to_run,
            :run_status_variant,
            :run_status_label,
            :discovery_record_count,
            :review_discovery_record_count,
            :discovery_evidence_count,
            :latest_evidence_at
          ]
        ]}
      >
        <:col :let={program} field="name" sort search label="Program">
          <div class="space-y-1">
            <.link
              navigate={~p"/commercial/discovery-programs/#{program}"}
              class="font-medium text-zinc-900 hover:text-emerald-600 dark:text-white"
            >
              {program.name}
            </.link>
            <p class="text-sm text-base-content/50">
              {format_atom(program.program_type)}
            </p>
          </div>
        </:col>

        <:col :let={program} label="Scope">
          <div class="space-y-1">
            <p>{summary_list(program.target_regions, "No regions")}</p>
            <p class="text-xs text-base-content/40">
              {summary_list(program.target_industries, "No industries")}
            </p>
          </div>
        </:col>

        <:col :let={program} label="Backlog">
          <div class="space-y-1">
            <p>{program.discovery_record_count} discovery records</p>
            <p class="text-xs text-base-content/40">
              {program.review_discovery_record_count} waiting review
            </p>
            <p class="text-xs text-base-content/40">
              {program.discovery_evidence_count} evidence items
            </p>
          </div>
        </:col>

        <:col :let={program} field="cadence_hours" sort label="Cadence">
          <div class="space-y-1">
            <p>Every {program.cadence_hours}h</p>
            <div class="flex flex-wrap items-center gap-2 text-xs text-base-content/40">
              <span>{format_datetime(program.last_run_at)}</span>
              <.status_badge status={program.run_status_variant}>
                {program.run_status_label}
              </.status_badge>
            </div>
          </div>
        </:col>

        <:col :let={program} field="status" sort label="Status">
          <div class="space-y-2">
            <.status_badge status={program.status_variant}>
              {format_atom(program.status)}
            </.status_badge>
            <.status_badge status={program.priority_variant}>
              {format_atom(program.priority)}
            </.status_badge>
          </div>
        </:col>

        <:col :let={program} label="Actions">
          <div class="flex flex-wrap gap-2">
            <.button
              :if={program_runnable?(program)}
              id={"run-program-#{program.id}"}
              phx-click="run_now"
              phx-value-id={program.id}
              class="px-2.5 py-1.5 text-xs"
              variant={if(program.is_due_to_run, do: "primary", else: nil)}
            >
              Run Now
            </.button>
            <.button
              id={"program-targets-#{program.id}"}
              navigate={discovery_intake_path(program)}
              class="px-2.5 py-1.5 text-xs"
            >
              Intake
            </.button>
            <.button
              navigate={~p"/commercial/discovery-programs/#{program}"}
              class="px-2.5 py-1.5 text-xs"
            >
              Open
            </.button>
          </div>
        </:col>

        <:empty>
          <.empty_state
            icon="hero-radar"
            title="No discovery programs yet"
            description="Create a program for a region, industry, or target hunt before scaling discovery."
          >
            <:action>
              <.button navigate={~p"/commercial/discovery-programs/new"} variant="primary">
                Create Discovery Program
              </.button>
            </:action>
          </.empty_state>
        </:empty>
      </Cinder.collection>
    </.page>
    """
  end

  defp assign_counts(socket) do
    counts = load_counts(socket.assigns.current_user)

    socket
    |> assign(:program_count, counts.total)
    |> assign(:active_count, counts.active)
    |> assign(:review_discovery_record_count, counts.review_discovery_record_count)
    |> assign(:pilot_ready_count, counts.pilot_ready)
  end

  defp load_counts(actor) do
    case Commercial.list_discovery_programs(
           actor: actor,
           load: [:is_due_to_run, :review_discovery_record_count]
         ) do
      {:ok, programs} ->
        %{
          total: length(programs),
          active: Enum.count(programs, &(&1.status == :active)),
          review_discovery_record_count:
            Enum.reduce(programs, 0, &(&1.review_discovery_record_count + &2)),
          pilot_ready: Enum.count(programs, &(&1.status == :active and &1.is_due_to_run))
        }

      {:error, _} ->
        %{total: 0, active: 0, review_discovery_record_count: 0, pilot_ready: 0}
    end
  end

  defp program_runnable?(%{status: :archived}), do: false
  defp program_runnable?(_program), do: true

  defp short_id(id), do: String.slice(id, 0, 8)

  defp summary_list([], empty_label), do: empty_label
  defp summary_list(values, _empty_label), do: Enum.join(values, ", ")

  defp discovery_intake_path(program) do
    case Acquisition.get_program_by_discovery_program(program.id) do
      {:ok, acquisition_program} ->
        ~p"/acquisition/findings?family=discovery&program_id=#{acquisition_program.id}"

      _ ->
        ~p"/acquisition/findings?family=discovery"
    end
  end
end
