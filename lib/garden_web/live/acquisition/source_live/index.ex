defmodule GnomeGardenWeb.Acquisition.SourceLive.Index do
  use GnomeGardenWeb, :live_view
  use Cinder.UrlSync

  import Cinder.Refresh

  import GnomeGardenWeb.Execution.Helpers, only: [format_atom: 1, format_datetime: 1]

  alias GnomeGarden.Acquisition
  alias GnomeGarden.Procurement

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Acquisition Sources")
     |> assign(:source_counts, source_counts(socket.assigns.current_user))}
  end

  @impl true
  def handle_params(params, uri, socket) do
    socket = Cinder.UrlSync.handle_params(params, uri, socket)
    {:noreply, socket}
  end

  @impl true
  def handle_event("launch_run", %{"id" => id}, socket) do
    with {:ok, source} <-
           Acquisition.get_source(id,
             actor: socket.assigns.current_user,
             load: [:procurement_source, :runnable]
           ),
         true <- scan_ready?(source),
         source_id when is_binary(source_id) <- source.procurement_source_id,
         {:ok, %{run: run}} <-
           Procurement.launch_procurement_source_scan(source_id,
             actor: socket.assigns.current_user
           ) do
      {:noreply,
       socket
       |> assign(:source_counts, source_counts(socket.assigns.current_user))
       |> refresh_table("acquisition-sources-table")
       |> put_flash(:info, "Launched source scan #{run.id} for #{source.name}.")}
    else
      false ->
        {:noreply,
         put_flash(
           socket,
           :error,
           "Configure this source before launching a scan."
         )}

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
          Durable registry of scan targets across procurement and future discovery families. Configure sources first, then launch scans from here.
        </:subtitle>
        <:actions>
          <.button navigate={~p"/acquisition/findings"}>
            Queue
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
          description="Configured sources that can launch right now."
          icon="hero-bolt"
          accent="amber"
        />
      </div>

      <Cinder.collection
        id="acquisition-sources-table"
        resource={GnomeGarden.Acquisition.Source}
        action={:console}
        actor={@current_user}
        url_state={@url_state}
        theme={GnomeGardenWeb.CinderTheme}
        page_size={25}
      >
        <:col :let={source} field="name" search sort label="Source">
          <div class="space-y-1">
            <p class="font-medium text-base-content">{source.name}</p>
            <p class="text-sm text-base-content/50">{source.url}</p>
            <p :if={source.organization} class="text-xs text-base-content/40">
              {source.organization.name}
            </p>
          </div>
        </:col>
        <:col :let={source} label="Family">
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
            <span :if={source.procurement_source} class="badge badge-outline badge-sm">
              {source.procurement_source.config_status
              |> to_string()
              |> String.replace("_", " ")
              |> String.capitalize()}
            </span>
          </div>
        </:col>
        <:col :let={source} field="status" sort label="Run Health">
          <div class="space-y-2">
            <.status_badge status={source.status_variant}>
              {format_atom(source.status)}
            </.status_badge>
            <.status_badge status={source.health_variant}>
              {format_atom(source.health_status)}
            </.status_badge>
            <p class="text-xs text-base-content/50">
              {source.health_note}
            </p>
            <p class="text-xs text-base-content/50">
              Last run {format_datetime(source.last_run_at)}
            </p>
            <p class="text-xs text-base-content/40">
              Last success {format_datetime(source.last_success_at)}
            </p>
          </div>
        </:col>
        <:col :let={source} label="Findings">
          <div class="space-y-1 text-sm text-base-content/80">
            <p>{source.finding_count} total</p>
            <p class="text-xs text-base-content/50">
              {source.review_finding_count} review · {source.promoted_finding_count} promoted · {source.noise_finding_count} noise
            </p>
          </div>
        </:col>
        <:col :let={source} label="Actions">
          <div class="flex flex-wrap gap-2">
            <.link
              :if={needs_configuration?(source)}
              navigate={~p"/acquisition/sources/#{source.id}/configure"}
              class="btn btn-xs btn-primary"
            >
              Configure
            </.link>
            <.link
              :if={configured_source?(source)}
              navigate={~p"/acquisition/sources/#{source.id}/configure"}
              class="btn btn-xs btn-ghost"
            >
              Edit Config
            </.link>
            <.link
              navigate={
                ~p"/acquisition/findings?family=#{source.source_family}&source_id=#{source.id}"
              }
              class="btn btn-xs btn-ghost"
            >
              Open Queue
            </.link>
            <.button
              :if={scan_ready?(source)}
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
        </:col>

        <:empty>
          <.empty_state
            icon="hero-globe-alt"
            title="No acquisition sources"
            description="Backfilled procurement sources and future discovery sources will appear here."
          />
        </:empty>
      </Cinder.collection>
    </.page>
    """
  end

  defp source_counts(actor) do
    case Acquisition.list_console_sources(actor: actor) do
      {:ok, sources} ->
        %{
          total: length(sources),
          healthy: Enum.count(sources, &(&1.health_status in [:healthy, :running])),
          attention:
            Enum.count(
              sources,
              &(&1.health_status in [:blocked, :failing, :stale, :noisy, :cancelled])
            ),
          runnable: Enum.count(sources, &scan_ready?/1)
        }

      {:error, _} ->
        %{total: 0, healthy: 0, attention: 0, runnable: 0}
    end
  end

  defp scan_ready?(source) do
    source.runnable && configured_source?(source)
  end

  defp needs_configuration?(%{procurement_source: %{config_status: status}})
       when status in [:found, :pending, :config_failed, :manual],
       do: true

  defp needs_configuration?(_source), do: false

  defp configured_source?(%{procurement_source: %{config_status: status}})
       when status in [:configured, :scan_failed],
       do: true

  defp configured_source?(_source), do: false
end
