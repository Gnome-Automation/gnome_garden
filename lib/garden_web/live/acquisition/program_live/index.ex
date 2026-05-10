defmodule GnomeGardenWeb.Acquisition.ProgramLive.Index do
  use GnomeGardenWeb, :live_view
  use Cinder.UrlSync

  import Cinder.Refresh

  import GnomeGardenWeb.Execution.Helpers, only: [format_atom: 1, format_datetime: 1]

  alias GnomeGarden.Acquisition
  alias GnomeGarden.Commercial

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Acquisition Programs")
     |> assign(:program_counts, program_counts(socket.assigns.current_user))}
  end

  @impl true
  def handle_params(params, uri, socket) do
    socket = Cinder.UrlSync.handle_params(params, uri, socket)
    {:noreply, socket}
  end

  @impl true
  def handle_event("launch_run", %{"id" => id}, socket) do
    with {:ok, program} <- Acquisition.get_program(id, actor: socket.assigns.current_user),
         discovery_program_id when is_binary(discovery_program_id) <- program.discovery_program_id,
         {:ok, %{run: run}} <-
           Commercial.launch_discovery_program(discovery_program_id,
             actor: socket.assigns.current_user
           ) do
      {:noreply,
       socket
       |> assign(:program_counts, program_counts(socket.assigns.current_user))
       |> refresh_table("acquisition-programs-table")
       |> put_flash(:info, "Launched discovery run #{run.id} for #{program.name}.")}
    else
      nil ->
        {:noreply,
         put_flash(
           socket,
           :error,
           "Only discovery-backed programs can be launched from here today."
         )}

      {:error, error} ->
        {:noreply, put_flash(socket, :error, "Could not launch program run: #{inspect(error)}")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.page class="pb-8">
      <.page_header eyebrow="Acquisition">
        Program Registry
        <:subtitle>
          Durable acquisition programs define why the platform is scanning. This is the acquisition-native view of lane ownership, cadence, and output volume.
        </:subtitle>
        <:actions>
          <.button navigate={~p"/acquisition/findings"}>
            Queue
          </.button>
        </:actions>
      </.page_header>

      <div class="grid gap-4 md:grid-cols-4">
        <.stat_card
          title="Programs"
          value={Integer.to_string(@program_counts.total)}
          description="Total acquisition programs."
          icon="hero-radar"
        />
        <.stat_card
          title="Healthy"
          value={Integer.to_string(@program_counts.healthy)}
          description="Programs running cleanly or already in flight."
          icon="hero-play-circle"
          accent="emerald"
        />
        <.stat_card
          title="Attention"
          value={Integer.to_string(@program_counts.attention)}
          description="Programs that are stale, failing, or noisy."
          icon="hero-pause-circle"
          accent="amber"
        />
        <.stat_card
          title="Runnable"
          value={Integer.to_string(@program_counts.runnable)}
          description="Programs that can launch right now."
          icon="hero-bolt"
          accent="sky"
        />
      </div>

      <Cinder.collection
        id="acquisition-programs-table"
        resource={GnomeGarden.Acquisition.Program}
        action={:console}
        actor={@current_user}
        url_state={@url_state}
        theme={GnomeGardenWeb.CinderTheme}
        page_size={25}
      >
        <:col :let={program} field="name" search sort label="Program">
          <div class="space-y-1">
            <p class="font-medium text-base-content">{program.name}</p>
            <p class="text-sm text-base-content/50">
              {program.description || "No description yet."}
            </p>
            <p :if={program.owner_team_member} class="text-xs text-base-content/40">
              Owner {program.owner_team_member.display_name}
            </p>
          </div>
        </:col>
        <:col :let={program} label="Family">
          <div class="space-y-2">
            <span class="badge badge-info badge-sm">
              {program.program_family |> to_string() |> String.capitalize()}
            </span>
            <span class="badge badge-outline badge-sm">
              {program.program_type
              |> to_string()
              |> String.replace("_", " ")
              |> String.capitalize()}
            </span>
          </div>
        </:col>
        <:col :let={program} field="status" sort label="Run Health">
          <div class="space-y-2">
            <.status_badge status={program.status_variant}>
              {format_atom(program.status)}
            </.status_badge>
            <.status_badge status={program.health_variant}>
              {format_atom(program.health_status)}
            </.status_badge>
            <p class="text-xs text-base-content/50">
              {program.health_note}
            </p>
            <p class="text-xs text-base-content/50">
              Last run {format_datetime(program.last_run_at)}
            </p>
          </div>
        </:col>
        <:col :let={program} label="Findings">
          <div class="space-y-1 text-sm text-base-content/80">
            <p>{program.finding_count} total</p>
            <p class="text-xs text-base-content/50">
              {program.review_finding_count} review · {program.promoted_finding_count} promoted · {program.noise_finding_count} noise
            </p>
          </div>
        </:col>
        <:col :let={program} label="Actions">
          <div class="flex flex-wrap gap-2">
            <.link
              navigate={
                ~p"/acquisition/findings?family=#{program.program_family}&program_id=#{program.id}"
              }
              class="btn btn-xs btn-ghost"
            >
              Open Queue
            </.link>
            <.button
              :if={program.runnable}
              id={"launch-program-#{program.id}"}
              phx-click="launch_run"
              phx-value-id={program.id}
              class="px-2.5 py-1.5 text-xs"
              variant="primary"
            >
              Launch Run
            </.button>
            <.link
              :if={program.latest_run_id}
              navigate={~p"/console/agents/runs/#{program.latest_run_id}"}
              class="btn btn-xs btn-ghost"
            >
              Open Run
            </.link>
          </div>
        </:col>

        <:empty>
          <.empty_state
            icon="hero-radar"
            title="No acquisition programs"
            description="Backfilled discovery programs and future research programs will appear here."
          />
        </:empty>
      </Cinder.collection>
    </.page>
    """
  end

  defp program_counts(actor) do
    case Acquisition.list_console_programs(actor: actor) do
      {:ok, programs} ->
        %{
          total: length(programs),
          healthy: Enum.count(programs, &(&1.health_status in [:healthy, :running])),
          attention:
            Enum.count(
              programs,
              &(&1.health_status in [:failing, :stale, :noisy, :cancelled])
            ),
          runnable: Enum.count(programs, & &1.runnable)
        }

      {:error, _} ->
        %{total: 0, healthy: 0, attention: 0, runnable: 0}
    end
  end
end
