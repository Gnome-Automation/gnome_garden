defmodule GnomeGardenWeb.Acquisition.SourceLive.Index do
  use GnomeGardenWeb, :live_view

  import GnomeGardenWeb.Execution.Helpers, only: [format_atom: 1, format_datetime: 1]

  alias GnomeGarden.Acquisition
  alias GnomeGarden.Procurement

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Acquisition Sources")
     |> assign(:sources_empty?, true)
     |> assign(:source_counts, %{total: 0, healthy: 0, attention: 0, runnable: 0})
     |> stream(:sources, [], reset: true)
     |> refresh_sources()}
  end

  @impl true
  def handle_event("launch_run", %{"id" => id}, socket) do
    with {:ok, source} <- Acquisition.get_source(id, actor: socket.assigns.current_user),
         legacy_id when is_binary(legacy_id) <- source.legacy_procurement_source_id,
         {:ok, %{run: run}} <-
           Procurement.launch_procurement_source_scan(legacy_id,
             actor: socket.assigns.current_user
           ) do
      {:noreply,
       socket
       |> refresh_sources()
       |> put_flash(:info, "Launched source scan #{run.id} for #{source.name}.")}
    else
      nil ->
        {:noreply,
         put_flash(
           socket,
           :error,
           "Only procurement-backed sources can be launched from here today."
         )}

      {:error, error} ->
        {:noreply, put_flash(socket, :error, "Could not launch source scan: #{inspect(error)}")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.page class="pb-8">
      <.page_header eyebrow="Acquisition">
        Source Registry
        <:subtitle>
          Durable registry of scan targets across procurement and future discovery families. This is the acquisition-native view of source health and scan ownership.
        </:subtitle>
        <:actions>
          <.button navigate={~p"/acquisition/findings"}>
            <.icon name="hero-inbox-stack" class="size-4" /> Queue
          </.button>
        </:actions>
      </.page_header>

      <div class="grid gap-4 md:grid-cols-4">
        <.stat_card
          title="Sources"
          value={Integer.to_string(@source_counts.total)}
          description="Total registered scan targets."
          icon="hero-globe-alt"
        />
        <.stat_card
          title="Healthy"
          value={Integer.to_string(@source_counts.healthy)}
          description="Sources running cleanly or already in flight."
          icon="hero-play-circle"
          accent="emerald"
        />
        <.stat_card
          title="Attention"
          value={Integer.to_string(@source_counts.attention)}
          description="Sources that are stale, failing, noisy, or blocked."
          icon="hero-shield-exclamation"
          accent="rose"
        />
        <.stat_card
          title="Runnable"
          value={Integer.to_string(@source_counts.runnable)}
          description="Acquisition sources that can launch right now."
          icon="hero-bolt"
          accent="amber"
        />
      </div>

      <.section
        title="Acquisition Sources"
        description="See family, strategy, run health, and downstream finding volume in one table."
        compact
        body_class="p-0"
      >
        <div :if={@sources_empty?} class="p-6 sm:p-7">
          <.empty_state
            icon="hero-globe-alt"
            title="No acquisition sources"
            description="Backfilled procurement sources and future discovery sources will appear here."
          />
        </div>

        <div :if={!@sources_empty?} class="overflow-x-auto">
          <table class="min-w-full divide-y divide-zinc-200 text-sm dark:divide-white/10">
            <thead class="bg-zinc-50 dark:bg-white/[0.03]">
              <tr>
                <th class="px-5 py-3 text-left font-medium text-zinc-500 dark:text-zinc-400">
                  Source
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
              id="acquisition-sources"
              phx-update="stream"
              class="divide-y divide-zinc-200 dark:divide-white/10"
            >
              <tr :for={{dom_id, source} <- @streams.sources} id={dom_id}>
                <td class="px-5 py-4 align-top">
                  <div class="space-y-1">
                    <p class="font-medium text-zinc-900 dark:text-white">{source.name}</p>
                    <p class="text-sm text-zinc-500 dark:text-zinc-400">{source.url}</p>
                    <p :if={source.organization} class="text-xs text-zinc-400 dark:text-zinc-500">
                      {source.organization.name}
                    </p>
                  </div>
                </td>
                <td class="px-5 py-4 align-top">
                  <div class="space-y-2">
                    <span class="badge badge-info badge-sm">
                      {source.source_family |> to_string() |> String.capitalize()}
                    </span>
                    <span class="badge badge-outline badge-sm">
                      {source.source_kind
                      |> to_string()
                      |> String.replace("_", " ")
                      |> String.capitalize()}
                    </span>
                    <span class="badge badge-ghost badge-sm">
                      {source.scan_strategy |> to_string() |> String.capitalize()}
                    </span>
                  </div>
                </td>
                <td class="px-5 py-4 align-top">
                  <div class="space-y-2">
                    <.status_badge status={source.status_variant}>
                      {format_atom(source.status)}
                    </.status_badge>
                    <.status_badge status={source.health_variant}>
                      {format_atom(source.health_status)}
                    </.status_badge>
                    <p class="text-xs text-zinc-500 dark:text-zinc-400">
                      {source.health_note}
                    </p>
                    <p class="text-xs text-zinc-500 dark:text-zinc-400">
                      Last run {format_datetime(source.last_run_at)}
                    </p>
                    <p class="text-xs text-zinc-400 dark:text-zinc-500">
                      Last success {format_datetime(source.last_success_at)}
                    </p>
                  </div>
                </td>
                <td class="px-5 py-4 align-top">
                  <div class="space-y-1 text-sm text-zinc-700 dark:text-zinc-200">
                    <p>{source.finding_count} total</p>
                    <p class="text-xs text-zinc-500 dark:text-zinc-400">
                      {source.review_finding_count} review · {source.promoted_finding_count} promoted · {source.noise_finding_count} noise
                    </p>
                  </div>
                </td>
                <td class="px-5 py-4 align-top">
                  <div class="flex flex-wrap gap-2">
                    <.link
                      navigate={
                        ~p"/acquisition/findings?family=#{source.source_family}&source_id=#{source.id}"
                      }
                      class="btn btn-xs btn-ghost"
                    >
                      Open Queue
                    </.link>
                    <.button
                      :if={source.runnable}
                      id={"launch-source-#{source.id}"}
                      phx-click="launch_run"
                      phx-value-id={source.id}
                      class="px-2.5 py-1.5 text-xs"
                      variant="primary"
                    >
                      Launch Scan
                    </.button>
                    <.link
                      :if={source.latest_run_id}
                      navigate={~p"/console/agents/runs/#{source.latest_run_id}"}
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

  defp refresh_sources(socket) do
    sources = Acquisition.list_console_sources!(actor: socket.assigns.current_user)

    socket
    |> assign(:sources_empty?, sources == [])
    |> assign(:source_counts, source_counts(sources))
    |> stream(:sources, sources, reset: true)
  end

  defp source_counts(sources) do
    %{
      total: length(sources),
      healthy: Enum.count(sources, &(&1.health_status in [:healthy, :running])),
      attention:
        Enum.count(
          sources,
          &(&1.health_status in [:blocked, :failing, :stale, :noisy, :cancelled])
        ),
      runnable: Enum.count(sources, & &1.runnable)
    }
  end
end
