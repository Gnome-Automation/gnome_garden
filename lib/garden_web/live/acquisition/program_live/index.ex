defmodule GnomeGardenWeb.Acquisition.ProgramLive.Index do
  use GnomeGardenWeb, :live_view

  import GnomeGardenWeb.Execution.Helpers, only: [format_atom: 1, format_datetime: 1]

  alias GnomeGarden.Acquisition
  alias GnomeGarden.Commercial

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Acquisition Programs")
     |> assign(:programs_empty?, true)
     |> assign(:program_counts, %{total: 0, healthy: 0, attention: 0, runnable: 0})
     |> stream(:programs, [], reset: true)
     |> refresh_programs()}
  end

  @impl true
  def handle_event("launch_run", %{"id" => id}, socket) do
    with {:ok, program} <- Acquisition.get_program(id, actor: socket.assigns.current_user),
         legacy_id when is_binary(legacy_id) <- program.legacy_discovery_program_id,
         {:ok, %{run: run}} <-
           Commercial.launch_discovery_program(legacy_id, actor: socket.assigns.current_user) do
      {:noreply,
       socket
       |> refresh_programs()
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
            <.icon name="hero-inbox-stack" class="size-4" /> Queue
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

      <.section
        title="Acquisition Programs"
        description="See family, scope, run health, and finding volume from one acquisition-native registry."
        compact
        body_class="p-0"
      >
        <div :if={@programs_empty?} class="p-6 sm:p-7">
          <.empty_state
            icon="hero-radar"
            title="No acquisition programs"
            description="Backfilled discovery programs and future research programs will appear here."
          />
        </div>

        <div :if={!@programs_empty?} class="overflow-x-auto">
          <table class="min-w-full divide-y divide-zinc-200 text-sm dark:divide-white/10">
            <thead class="bg-zinc-50 dark:bg-white/[0.03]">
              <tr>
                <th class="px-5 py-3 text-left font-medium text-zinc-500 dark:text-zinc-400">
                  Program
                </th>
                <th class="px-5 py-3 text-left font-medium text-zinc-500 dark:text-zinc-400">
                  Family
                </th>
                <th class="px-5 py-3 text-left font-medium text-zinc-500 dark:text-zinc-400">
                  Run Health
                </th>
                <th class="px-5 py-3 text-left font-medium text-zinc-500 dark:text-zinc-400">
                  Findings
                </th>
                <th class="px-5 py-3 text-left font-medium text-zinc-500 dark:text-zinc-400">
                  Actions
                </th>
              </tr>
            </thead>
            <tbody
              id="acquisition-programs"
              phx-update="stream"
              class="divide-y divide-zinc-200 dark:divide-white/10"
            >
              <tr :for={{dom_id, program} <- @streams.programs} id={dom_id}>
                <td class="px-5 py-4 align-top">
                  <div class="space-y-1">
                    <p class="font-medium text-zinc-900 dark:text-white">{program.name}</p>
                    <p class="text-sm text-zinc-500 dark:text-zinc-400">
                      {program.description || "No description yet."}
                    </p>
                    <p
                      :if={program.owner_user_id}
                      class="text-xs text-zinc-400 dark:text-zinc-500"
                    >
                      Owner {program.owner_user_id}
                    </p>
                  </div>
                </td>
                <td class="px-5 py-4 align-top">
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
                </td>
                <td class="px-5 py-4 align-top">
                  <div class="space-y-2">
                    <.status_badge status={program.status_variant}>
                      {format_atom(program.status)}
                    </.status_badge>
                    <.status_badge status={program.health_variant}>
                      {format_atom(program.health_status)}
                    </.status_badge>
                    <p class="text-xs text-zinc-500 dark:text-zinc-400">
                      {program.health_note}
                    </p>
                    <p class="text-xs text-zinc-500 dark:text-zinc-400">
                      Last run {format_datetime(program.last_run_at)}
                    </p>
                  </div>
                </td>
                <td class="px-5 py-4 align-top">
                  <div class="space-y-1 text-sm text-zinc-700 dark:text-zinc-200">
                    <p>{program.finding_count} total</p>
                    <p class="text-xs text-zinc-500 dark:text-zinc-400">
                      {program.review_finding_count} review · {program.promoted_finding_count} promoted · {program.noise_finding_count} noise
                    </p>
                  </div>
                </td>
                <td class="px-5 py-4 align-top">
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
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </.section>
    </.page>
    """
  end

  defp refresh_programs(socket) do
    programs = Acquisition.list_console_programs!(actor: socket.assigns.current_user)

    socket
    |> assign(:programs_empty?, programs == [])
    |> assign(:program_counts, program_counts(programs))
    |> stream(:programs, programs, reset: true)
  end

  defp program_counts(programs) do
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
  end
end
