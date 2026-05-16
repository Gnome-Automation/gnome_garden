defmodule GnomeGardenWeb.Acquisition.SourceLive.Index do
  use GnomeGardenWeb, :live_view

  import GnomeGardenWeb.Execution.Helpers, only: [format_atom: 1, format_datetime: 1]

  alias GnomeGarden.Acquisition

  @buckets [:needs_configuration, :ready, :attention, :all]
  @source_limit 75

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      GnomeGardenWeb.Endpoint.subscribe("source:created")
      GnomeGardenWeb.Endpoint.subscribe("source:updated")
    end

    {:ok,
     socket
     |> assign(:page_title, "Acquisition Sources")
     |> assign(:buckets, @buckets)
     |> assign(:selected_bucket, :needs_configuration)
     |> assign(:source_counts, empty_counts())
     |> assign(:next_runnable_source, nil)
     |> assign(:sources, [])}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    bucket = parse_bucket(Map.get(params, "bucket"))
    sources = list_sources(socket.assigns.current_user)

    {:noreply,
     socket
     |> assign(:selected_bucket, bucket)
     |> assign_sources(sources)}
  end

  @impl true
  def handle_event("launch_run", %{"id" => id}, socket) do
    launch_source(socket, id)
  end

  @impl true
  def handle_event("launch_next_run", _params, socket) do
    case socket.assigns.next_runnable_source do
      %{id: id} ->
        launch_source(socket, id)

      nil ->
        {:noreply, put_flash(socket, :error, "No ready source is available to scan.")}
    end
  end

  defp launch_source(socket, id) do
    with {:ok, source} <-
           Acquisition.get_source(id,
             actor: socket.assigns.current_user,
             load: [:procurement_source, :runnable]
           ),
         true <- scan_ready?(source),
         {:ok, %{run: run}} <-
           Acquisition.launch_source_run(source,
             actor: socket.assigns.current_user
           ) do
      {:noreply,
       socket
       |> refresh_sources()
       |> put_flash(:info, "Launched source scan #{run.id} for #{source.name}.")}
    else
      false ->
        {:noreply,
         put_flash(
           socket,
           :error,
           "Configure this source before launching a scan."
         )}

      {:error, error} ->
        {:noreply, put_flash(socket, :error, "Could not launch source scan: #{inspect(error)}")}
    end
  end

  @impl true
  def handle_info(%{topic: "source:" <> _event}, socket) do
    {:noreply, refresh_sources(socket)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.page class="pb-8">
      <.page_header eyebrow="Acquisition">
        Source Registry
        <:subtitle>
          Work the source backlog from configuration to scanning. The restored catalog starts here before it creates reviewable findings.
        </:subtitle>
        <:actions>
          <.button navigate={~p"/acquisition/dashboard"}>
            Dashboard
          </.button>
          <.button navigate={~p"/acquisition/findings"}>
            Queue
          </.button>
        </:actions>
      </.page_header>

      <.section
        title="Source Work Queue"
        description="Configure and launch source lanes that feed reviewable findings into acquisition."
        compact
        body_class="p-0"
      >
        <div class="grid min-h-[34rem] lg:grid-cols-[17rem_minmax(0,1fr)]">
          <aside class="border-b border-zinc-200 bg-zinc-50/70 p-3 dark:border-white/10 dark:bg-white/[0.03] lg:border-b-0 lg:border-r">
            <div class="grid gap-2 sm:grid-cols-4 lg:grid-cols-1">
              <.bucket_link
                :for={bucket <- @buckets}
                bucket={bucket}
                selected_bucket={@selected_bucket}
                count={bucket_count(@source_counts, bucket)}
              />
            </div>

            <div class="mt-4 grid grid-cols-2 gap-2 lg:grid-cols-1">
              <.registry_count label="Total" value={@source_counts.total} />
              <.registry_count label="Healthy" value={@source_counts.healthy} />
              <.registry_count label="Attention" value={@source_counts.attention} />
              <.registry_count label="Runnable" value={@source_counts.runnable} />
            </div>
          </aside>

          <div class="min-w-0">
            <div class="flex flex-col gap-3 border-b border-zinc-200 px-3 py-3 dark:border-white/10 sm:flex-row sm:items-center sm:justify-between sm:px-4">
              <div class="min-w-0">
                <p class="text-sm font-semibold text-base-content">
                  {bucket_label(@selected_bucket)}
                </p>
                <p class="mt-0.5 text-xs text-base-content/50">
                  Showing {length(@sources)} of {bucket_count(@source_counts, @selected_bucket)} sources
                </p>
              </div>
              <div class="flex flex-col gap-2 sm:flex-row sm:items-center sm:justify-end">
                <.button
                  :if={@next_runnable_source}
                  phx-click="launch_next_run"
                  variant="primary"
                  class="px-3 py-2 text-sm"
                >
                  Launch Next Scan
                </.button>
                <.link navigate={~p"/acquisition/findings"} class="btn btn-sm btn-ghost">
                  Open Review Queue
                </.link>
              </div>
            </div>

            <div
              :if={@sources != []}
              id="acquisition-source-cards"
              class="divide-y divide-zinc-200 bg-base-100 dark:divide-white/10"
            >
              <.source_card :for={source <- @sources} source={source} />
            </div>

            <div :if={@sources == []} class="p-4">
              <.empty_state
                icon="hero-globe-alt"
                title="No sources in this queue"
                description="Change the source queue filter or import/configure more sources."
              />
            </div>
          </div>
        </div>
      </.section>
    </.page>
    """
  end

  attr :bucket, :atom, required: true
  attr :selected_bucket, :atom, required: true
  attr :count, :integer, required: true

  defp bucket_link(assigns) do
    ~H"""
    <.link
      patch={~p"/acquisition/sources?bucket=#{@bucket}"}
      class={[
        "inline-flex min-w-0 items-center justify-between gap-2 rounded-md border px-3 py-2 text-sm font-medium transition",
        if(@selected_bucket == @bucket,
          do: "border-emerald-600 bg-emerald-600 text-white shadow-sm shadow-emerald-600/20",
          else:
            "border-zinc-200 bg-white text-zinc-600 hover:border-emerald-300 hover:text-emerald-700 dark:border-white/10 dark:bg-white/[0.03] dark:text-zinc-300 dark:hover:border-emerald-400/40 dark:hover:text-emerald-300"
        )
      ]}
    >
      <span class="truncate">{bucket_label(@bucket)}</span>
      <span class={[
        "rounded-full px-2 py-0.5 text-xs font-semibold",
        if(@selected_bucket == @bucket,
          do: "bg-white/20 text-white",
          else: "bg-zinc-100 text-zinc-500 dark:bg-white/10 dark:text-zinc-300"
        )
      ]}>
        {if @count > 99, do: "99+", else: @count}
      </span>
    </.link>
    """
  end

  attr :source, :map, required: true

  defp source_card(assigns) do
    ~H"""
    <article class="grid gap-3 px-3 py-3 transition hover:bg-zinc-50/80 dark:hover:bg-white/[0.025] sm:px-4 lg:grid-cols-[minmax(0,1fr)_16rem]">
      <div class="min-w-0 space-y-3">
        <div class="flex flex-col gap-3 sm:flex-row sm:items-start sm:justify-between">
          <div class="min-w-0">
            <div class="flex flex-wrap gap-2">
              <span class="badge badge-info badge-sm">{@source.source_family_label}</span>
              <span class="badge badge-outline badge-sm">{@source.source_kind_label}</span>
              <span class="badge badge-ghost badge-sm">{@source.scan_strategy_label}</span>
              <span :if={@source.procurement_source} class="badge badge-outline badge-sm">
                {format_atom(@source.procurement_source.config_status)}
              </span>
            </div>
            <h3 class="mt-2 text-base font-semibold leading-6 text-base-content">
              {@source.name}
            </h3>
            <p class="mt-1 break-all text-sm leading-5 text-base-content/60">
              {@source.url}
            </p>
          </div>

          <div class="flex shrink-0 flex-wrap gap-2 sm:justify-end">
            <.status_badge status={@source.status_variant}>
              {@source.status_label}
            </.status_badge>
            <.status_badge status={@source.health_variant}>
              {@source.health_label}
            </.status_badge>
          </div>
        </div>

        <div class="grid gap-2 text-sm sm:grid-cols-2 xl:grid-cols-4">
          <.source_fact label="Findings" value={"#{@source.finding_count} total"} />
          <.source_fact label="Review" value={"#{@source.review_finding_count} waiting"} />
          <.source_fact label="Last Run" value={format_datetime(@source.last_run_at)} />
          <.source_fact label="Last Success" value={format_datetime(@source.last_success_at)} />
        </div>

        <p class="text-sm leading-6 text-base-content/60">
          {@source.health_note}
        </p>
      </div>

      <div class="flex flex-col gap-2 border-t border-zinc-200 pt-3 dark:border-white/10 lg:border-l lg:border-t-0 lg:pl-4 lg:pt-0">
        <.link
          :if={needs_configuration?(@source)}
          navigate={~p"/acquisition/sources/#{@source.id}/configure"}
          class="btn btn-sm btn-primary"
        >
          Configure
        </.link>
        <.link
          :if={configured_source?(@source)}
          navigate={~p"/acquisition/sources/#{@source.id}/configure"}
          class="btn btn-sm btn-ghost"
        >
          Edit Config
        </.link>
        <.button
          :if={scan_ready?(@source)}
          id={"launch-source-#{@source.id}"}
          phx-click="launch_run"
          phx-value-id={@source.id}
          class="px-3 py-2 text-sm"
          variant="primary"
        >
          Launch Scan
        </.button>
        <.link
          navigate={~p"/acquisition/findings?family=#{@source.source_family}&source_id=#{@source.id}"}
          class="btn btn-sm btn-ghost"
        >
          Open Queue
        </.link>
        <.link
          :if={@source.latest_run_id}
          navigate={~p"/console/agents/runs/#{@source.latest_run_id}"}
          class="btn btn-sm btn-ghost"
        >
          Open Run
        </.link>
      </div>
    </article>
    """
  end

  attr :label, :string, required: true
  attr :value, :string, required: true

  defp registry_count(assigns) do
    ~H"""
    <div class="rounded-md border border-base-content/10 bg-base-200/70 px-2.5 py-2">
      <p class="text-[10px] font-semibold uppercase tracking-[0.14em] text-base-content/45">
        {@label}
      </p>
      <p class="mt-0.5 text-sm font-semibold tabular-nums text-base-content">{@value}</p>
    </div>
    """
  end

  defp source_fact(assigns) do
    ~H"""
    <div class="rounded-md border border-base-content/10 bg-base-200/60 px-3 py-2">
      <p class="text-[11px] font-semibold uppercase tracking-[0.14em] text-base-content/45">
        {@label}
      </p>
      <p class="mt-1 truncate font-medium text-base-content">{@value}</p>
    </div>
    """
  end

  defp refresh_sources(socket) do
    sources = list_sources(socket.assigns.current_user)

    assign_sources(socket, sources)
  end

  defp assign_sources(socket, sources) do
    socket
    |> assign(:source_counts, source_counts(sources))
    |> assign(:next_runnable_source, next_runnable_source(sources))
    |> assign(:sources, bucket_sources(sources, socket.assigns.selected_bucket))
  end

  defp list_sources(actor) do
    case Acquisition.list_console_sources(actor: actor) do
      {:ok, sources} -> sources
      {:error, _} -> []
    end
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
      runnable: Enum.count(sources, &scan_ready?/1),
      needs_configuration: Enum.count(sources, &needs_configuration?/1),
      ready: Enum.count(sources, &scan_ready?/1),
      all: length(sources)
    }
  end

  defp empty_counts do
    %{total: 0, healthy: 0, attention: 0, runnable: 0, needs_configuration: 0, ready: 0, all: 0}
  end

  defp bucket_sources(sources, bucket) do
    sources
    |> Enum.filter(&source_in_bucket?(&1, bucket))
    |> Enum.take(@source_limit)
  end

  defp next_runnable_source(sources) do
    sources
    |> Enum.filter(&scan_ready?/1)
    |> Enum.sort_by(&run_sort_key/1, DateTime)
    |> List.first()
  end

  defp run_sort_key(%{last_run_at: nil}), do: DateTime.from_unix!(0)
  defp run_sort_key(%{last_run_at: last_run_at}), do: last_run_at

  defp source_in_bucket?(source, :needs_configuration), do: needs_configuration?(source)
  defp source_in_bucket?(source, :ready), do: scan_ready?(source)

  defp source_in_bucket?(source, :attention),
    do: source.health_status in [:blocked, :failing, :stale, :noisy, :cancelled]

  defp source_in_bucket?(_source, :all), do: true

  defp bucket_count(counts, :attention), do: counts.attention
  defp bucket_count(counts, bucket), do: Map.fetch!(counts, bucket)

  defp bucket_label(:needs_configuration), do: "Needs configuration"
  defp bucket_label(:ready), do: "Ready"
  defp bucket_label(:attention), do: "Attention"
  defp bucket_label(:all), do: "All"

  defp parse_bucket(bucket) when is_binary(bucket) do
    bucket
    |> String.to_existing_atom()
    |> then(fn bucket -> if bucket in @buckets, do: bucket, else: :needs_configuration end)
  rescue
    ArgumentError -> :needs_configuration
  end

  defp parse_bucket(_bucket), do: :needs_configuration

  defp scan_ready?(source) do
    source.runnable && (configured_source?(source) || agentic_source?(source))
  end

  defp needs_configuration?(%{procurement_source: %{config_status: status}})
       when status in [:found, :pending, :config_failed, :manual],
       do: true

  defp needs_configuration?(_source), do: false

  defp configured_source?(%{procurement_source: %{config_status: status}})
       when status in [:configured, :scan_failed],
       do: true

  defp configured_source?(_source), do: false

  defp agentic_source?(%{procurement_source_id: source_id}) when is_binary(source_id), do: false

  defp agentic_source?(%{scan_strategy: strategy})
       when strategy in [:agentic, :deterministic],
       do: true

  defp agentic_source?(_source), do: false
end
