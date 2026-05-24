defmodule GnomeGardenWeb.Acquisition.SourceLive.Index do
  use GnomeGardenWeb, :live_view

  import GnomeGardenWeb.Execution.Helpers, only: [format_atom: 1, format_datetime: 1]

  alias GnomeGarden.Acquisition
  alias GnomeGarden.Acquisition.SourceLaunchBatch
  alias GnomeGarden.Agents.Procurement.SourceAutoConfigurator

  @buckets [:needs_configuration, :ready, :credentials_needed, :attention, :all]
  @configuration_batch_limit 10
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
     |> assign(:sources, [])
     |> assign(:configuration_batch_limit, @configuration_batch_limit)
     |> assign(:configuring_source_ids, MapSet.new())
     |> assign(:configuring_batch?, false)
     |> assign(:launching_source_ids, MapSet.new())
     |> assign(:launching_ready_batch?, false)}
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
  def handle_event("configure_source", %{"id" => id}, socket) do
    configure_source(socket, id)
  end

  @impl true
  def handle_event("configure_next_sources", _params, socket) do
    sources = configurable_sources(socket)

    if sources == [] do
      {:noreply, put_flash(socket, :error, "No sources are ready for automatic configuration.")}
    else
      actor = socket.assigns.current_user

      {:noreply,
       socket
       |> assign_configuring_sources(Enum.map(sources, & &1.id), true)
       |> assign(:configuring_batch?, true)
       |> put_flash(:info, "Configuring #{length(sources)} sources.")
       |> start_configuration_batch(sources, actor)}
    end
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

  @impl true
  def handle_event("launch_ready_runs", _params, socket) do
    actor = socket.assigns.current_user

    {:noreply,
     socket
     |> assign(:launching_ready_batch?, true)
     |> put_flash(:info, "Launching ready source scans.")
     |> start_batch_launch(actor)}
  end

  defp launch_source(socket, id) do
    with {:ok, source} <-
           Acquisition.get_source(id,
             actor: socket.assigns.current_user,
             load: [:procurement_source, :runnable]
           ),
         true <- scan_ready?(source),
         false <- launching_source?(socket.assigns.launching_source_ids, source.id) do
      actor = socket.assigns.current_user

      {:noreply,
       socket
       |> assign_launching_source(source.id, true)
       |> put_flash(:info, "Launching source scan for #{source.name}.")
       |> start_source_launch(source, actor)}
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

  defp configure_source(socket, id) do
    with {:ok, source} <-
           Acquisition.get_source(id,
             actor: socket.assigns.current_user,
             load: [:procurement_source]
           ),
         true <- auto_configurable?(source),
         false <- configuring_source?(socket.assigns.configuring_source_ids, source.id) do
      actor = socket.assigns.current_user

      {:noreply,
       socket
       |> assign_configuring_source(source.id, true)
       |> put_flash(:info, "Configuring #{source.name}.")
       |> start_source_configuration(source, actor)}
    else
      false ->
        {:noreply,
         put_flash(
           socket,
           :error,
           "This source is already configured or discovery is already running."
         )}

      {:error, error} ->
        {:noreply, put_flash(socket, :error, "Could not configure source: #{inspect(error)}")}
    end
  end

  @impl true
  def handle_info({:source_configuration_finished, source_id, source_name, result}, socket) do
    socket = assign_configuring_source(socket, source_id, false)

    case result do
      {:ok, %{mode: mode}} ->
        {:noreply,
         socket
         |> refresh_sources()
         |> put_flash(:info, source_configuration_message(source_name, mode))}

      {:error, error} ->
        {:noreply,
         socket
         |> refresh_sources()
         |> put_flash(:error, configuration_error_message(source_name, error))}
    end
  end

  def handle_info({:source_configuration_batch_finished, summary}, socket) do
    message = configuration_summary_message(summary)

    {:noreply,
     socket
     |> assign_configuring_sources(summary.source_ids, false)
     |> assign(:configuring_batch?, false)
     |> refresh_sources()
     |> put_flash(if(summary.errors > 0, do: :error, else: :info), message)}
  end

  def handle_info({:source_launch_finished, source_id, source_name, result}, socket) do
    socket = assign_launching_source(socket, source_id, false)

    case result do
      {:ok, %{run: run}} ->
        {:noreply,
         socket
         |> refresh_sources()
         |> put_flash(:info, "Launched source scan #{run.id} for #{source_name}.")}

      {:ok, _result} ->
        {:noreply,
         socket
         |> refresh_sources()
         |> put_flash(:info, "Launched source scan for #{source_name}.")}

      {:error, error} ->
        {:noreply,
         socket
         |> refresh_sources()
         |> put_flash(:error, "Could not launch source scan: #{inspect(error)}")}
    end
  end

  def handle_info({:ready_source_launches_finished, summary}, socket) do
    message =
      "Launched #{summary.launched} ready scans" <>
        if(summary.skipped > 0, do: "; skipped #{summary.skipped} active", else: "") <>
        if(summary.errors > 0, do: "; #{summary.errors} failed", else: "")

    {:noreply,
     socket
     |> assign(:launching_ready_batch?, false)
     |> refresh_sources()
     |> put_flash(if(summary.errors > 0, do: :error, else: :info), message)}
  end

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
            <div class="grid gap-2 sm:grid-cols-5 lg:grid-cols-1">
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
              <.registry_count label="Credentials" value={@source_counts.credentials_needed} />
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
                  :if={@selected_bucket == :needs_configuration}
                  phx-click="configure_next_sources"
                  variant="primary"
                  disabled={@configuring_batch?}
                  class={["px-3 py-2 text-sm", if(@configuring_batch?, do: "opacity-60")]}
                >
                  {if @configuring_batch?,
                    do: "Configuring...",
                    else: "Configure Next #{@configuration_batch_limit}"}
                </.button>
                <.button
                  :if={@selected_bucket == :ready and @next_runnable_source}
                  phx-click="launch_next_run"
                  variant="primary"
                  disabled={launching_source?(@launching_source_ids, @next_runnable_source.id)}
                  class={[
                    "px-3 py-2 text-sm",
                    if(launching_source?(@launching_source_ids, @next_runnable_source.id),
                      do: "opacity-60"
                    )
                  ]}
                >
                  {if launching_source?(@launching_source_ids, @next_runnable_source.id),
                    do: "Launching...",
                    else: "Launch Next Scan"}
                </.button>
                <.button
                  :if={@selected_bucket == :ready and @source_counts.runnable > 1}
                  phx-click="launch_ready_runs"
                  disabled={@launching_ready_batch?}
                  class={["px-3 py-2 text-sm", if(@launching_ready_batch?, do: "opacity-60")]}
                >
                  {if @launching_ready_batch?, do: "Launching...", else: "Launch Ready"}
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
              <.source_card
                :for={source <- @sources}
                source={source}
                configuring_source_ids={@configuring_source_ids}
                launching_source_ids={@launching_source_ids}
              />
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
  attr :configuring_source_ids, :any, required: true
  attr :launching_source_ids, :any, required: true

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
              <span
                :if={needs_operator_attention?(@source)}
                class="badge badge-error badge-sm"
              >
                Needs attention
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

        <div class="grid gap-2 text-sm sm:grid-cols-2 xl:grid-cols-6">
          <.source_fact label="Findings" value={"#{@source.finding_count} total"} />
          <.source_fact label="Review" value={"#{@source.review_finding_count} waiting"} />
          <.source_fact label="Accepted" value={count_label(@source.accepted_finding_count)} />
          <.source_fact label="Parked" value={count_label(@source.parked_finding_count)} />
          <.source_fact label="Rejected" value={count_label(@source.rejected_finding_count)} />
          <.source_fact label="Promoted" value={count_label(@source.promoted_finding_count)} />
        </div>

        <div class="grid gap-2 text-sm sm:grid-cols-2">
          <.source_fact label="Last Run" value={format_datetime(@source.last_run_at)} />
          <.source_fact label="Last Success" value={format_datetime(@source.last_success_at)} />
        </div>

        <div class="flex flex-col gap-2 rounded-md border border-base-content/10 bg-base-200/60 px-3 py-2 text-sm sm:flex-row sm:items-center sm:justify-between">
          <div class="min-w-0">
            <p class="text-[11px] font-semibold uppercase tracking-[0.14em] text-base-content/45">
              Run
            </p>
            <div class="mt-1 flex min-w-0 flex-wrap items-center gap-2">
              <.status_badge status={run_state_variant(@source)}>
                {run_state_label(@source)}
              </.status_badge>
              <span class="truncate text-xs text-base-content/55">
                {run_context(@source)}
              </span>
            </div>
          </div>
          <.link
            :if={@source.latest_run_id}
            navigate={~p"/console/agents/runs/#{@source.latest_run_id}"}
            class="btn btn-xs btn-ghost shrink-0"
          >
            Open Run
          </.link>
        </div>

        <p class="text-sm leading-6 text-base-content/60">
          {@source.health_note}
        </p>
        <p :if={extraction_summary(@source)} class="text-xs leading-5 text-base-content/45">
          {extraction_summary(@source)}
        </p>
        <p :if={configuration_exception(@source)} class="text-xs leading-5 text-error">
          {configuration_exception(@source)}
        </p>
      </div>

      <div class="flex flex-col gap-2 border-t border-zinc-200 pt-3 dark:border-white/10 lg:border-l lg:border-t-0 lg:pl-4 lg:pt-0">
        <.button
          :if={auto_configurable?(@source)}
          id={"configure-source-#{@source.id}"}
          phx-click="configure_source"
          phx-value-id={@source.id}
          disabled={configuring_source?(@configuring_source_ids, @source.id)}
          class={[
            "px-3 py-2 text-sm",
            if(configuring_source?(@configuring_source_ids, @source.id), do: "opacity-60")
          ]}
          variant="primary"
        >
          {if configuring_source?(@configuring_source_ids, @source.id),
            do: "Configuring...",
            else: "Configure"}
        </.button>
        <.link
          :if={manual_config_available?(@source)}
          navigate={~p"/acquisition/sources/#{@source.id}/configure"}
          class="btn btn-sm btn-ghost"
        >
          Manual Fallback
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
          disabled={launching_source?(@launching_source_ids, @source.id)}
          class={[
            "px-3 py-2 text-sm",
            if(launching_source?(@launching_source_ids, @source.id), do: "opacity-60")
          ]}
          variant="primary"
        >
          {if launching_source?(@launching_source_ids, @source.id),
            do: "Launching...",
            else: "Launch Scan"}
        </.button>
        <.link
          navigate={~p"/acquisition/findings?family=#{@source.source_family}&source_id=#{@source.id}"}
          class="btn btn-sm btn-ghost"
        >
          Open Queue
        </.link>
        <.link
          :if={@source.latest_run_id}
          navigate={
            ~p"/acquisition/findings?family=#{@source.source_family}&source_id=#{@source.id}&run_id=#{@source.latest_run_id}"
          }
          class="btn btn-sm btn-ghost"
        >
          New From Last Run
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

  defp configurable_sources(socket) do
    socket.assigns.sources
    |> Enum.filter(&auto_configurable?/1)
    |> Enum.reject(&configuring_source?(socket.assigns.configuring_source_ids, &1.id))
    |> Enum.take(@configuration_batch_limit)
  end

  defp source_counts(sources) do
    %{
      total: length(sources),
      healthy: Enum.count(sources, &(&1.health_status in [:healthy, :ready, :running])),
      attention:
        Enum.count(
          sources,
          &(&1.health_status in [
              :blocked,
              :failing,
              :selector_failed,
              :document_capture_failed,
              :no_results,
              :zero_saved,
              :stale,
              :noisy,
              :cancelled
            ])
        ),
      runnable: Enum.count(sources, &scan_ready?/1),
      needs_configuration: Enum.count(sources, &needs_configuration?/1),
      credentials_needed: Enum.count(sources, &credentials_needed?/1),
      ready: Enum.count(sources, &scan_ready?/1),
      all: length(sources)
    }
  end

  defp empty_counts do
    %{
      total: 0,
      healthy: 0,
      credentials_needed: 0,
      attention: 0,
      runnable: 0,
      needs_configuration: 0,
      ready: 0,
      all: 0
    }
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

  defp count_label(count) when is_integer(count), do: Integer.to_string(count)
  defp count_label(_count), do: "0"

  defp assign_launching_source(socket, source_id, launching?) do
    update(socket, :launching_source_ids, fn source_ids ->
      if launching? do
        MapSet.put(source_ids, source_id)
      else
        MapSet.delete(source_ids, source_id)
      end
    end)
  end

  defp launching_source?(source_ids, source_id), do: MapSet.member?(source_ids, source_id)

  defp assign_configuring_source(socket, source_id, configuring?) do
    assign_configuring_sources(socket, [source_id], configuring?)
  end

  defp assign_configuring_sources(socket, source_ids, configuring?) do
    update(socket, :configuring_source_ids, fn current_source_ids ->
      Enum.reduce(source_ids, current_source_ids, fn source_id, source_ids ->
        if configuring? do
          MapSet.put(source_ids, source_id)
        else
          MapSet.delete(source_ids, source_id)
        end
      end)
    end)
  end

  defp configuring_source?(source_ids, source_id), do: MapSet.member?(source_ids, source_id)

  defp start_source_configuration(socket, source, actor) do
    parent = self()

    case Task.Supervisor.start_child(GnomeGarden.AsyncSupervisor, fn ->
           result =
             safe_configuration_result(fn ->
               SourceAutoConfigurator.configure_source(source.procurement_source, actor: actor)
             end)

           send(parent, {:source_configuration_finished, source.id, source.name, result})
         end) do
      {:ok, _pid} ->
        socket

      {:error, reason} ->
        socket
        |> assign_configuring_source(source.id, false)
        |> put_flash(:error, "Could not start source configuration: #{inspect(reason)}")
    end
  end

  defp start_configuration_batch(socket, sources, actor) do
    parent = self()

    case Task.Supervisor.start_child(GnomeGarden.AsyncSupervisor, fn ->
           results =
             Enum.map(sources, fn source ->
               result =
                 safe_configuration_result(fn ->
                   SourceAutoConfigurator.configure_source(source.procurement_source,
                     actor: actor
                   )
                 end)

               {source, result}
             end)

           send(parent, {:source_configuration_batch_finished, configuration_summary(results)})
         end) do
      {:ok, _pid} ->
        socket

      {:error, reason} ->
        socket
        |> assign_configuring_sources(Enum.map(sources, & &1.id), false)
        |> assign(:configuring_batch?, false)
        |> put_flash(:error, "Could not start source configuration batch: #{inspect(reason)}")
    end
  end

  defp safe_configuration_result(fun) do
    fun.()
  rescue
    error -> {:error, error}
  catch
    kind, reason -> {:error, {kind, reason}}
  end

  defp configuration_summary(results) do
    Enum.reduce(
      results,
      %{
        source_ids: Enum.map(results, fn {source, _result} -> source.id end),
        auto_configured: 0,
        discovery_started: 0,
        already_pending: 0,
        already_configured: 0,
        errors: 0
      },
      fn
        {_source, {:ok, %{mode: :auto_configured}}}, summary ->
          update_in(summary.auto_configured, &(&1 + 1))

        {_source, {:ok, %{mode: :discovery_started}}}, summary ->
          update_in(summary.discovery_started, &(&1 + 1))

        {_source, {:ok, %{mode: :already_pending}}}, summary ->
          update_in(summary.already_pending, &(&1 + 1))

        {_source, {:ok, %{mode: :already_configured}}}, summary ->
          update_in(summary.already_configured, &(&1 + 1))

        {_source, {:error, _error}}, summary ->
          update_in(summary.errors, &(&1 + 1))
      end
    )
  end

  defp source_configuration_message(source_name, :auto_configured),
    do: "#{source_name} configured automatically."

  defp source_configuration_message(source_name, :discovery_started),
    do: "#{source_name} sent to browser discovery."

  defp source_configuration_message(source_name, :already_pending),
    do: "#{source_name} is already queued for discovery."

  defp source_configuration_message(source_name, :already_configured),
    do: "#{source_name} is already configured."

  defp configuration_error_message(source_name, error) do
    "#{source_name} could not be configured. Pi could not get clear listing data: #{format_configuration_error(error)}"
  end

  defp format_configuration_error(error) when is_exception(error), do: Exception.message(error)
  defp format_configuration_error(error) when is_binary(error), do: error
  defp format_configuration_error(error), do: inspect(error)

  defp configuration_summary_message(summary) do
    "Configured #{summary.auto_configured} automatically" <>
      if(summary.discovery_started > 0,
        do: "; sent #{summary.discovery_started} to discovery",
        else: ""
      ) <>
      if(summary.already_pending > 0,
        do: "; #{summary.already_pending} already running",
        else: ""
      ) <>
      if(summary.already_configured > 0,
        do: "; #{summary.already_configured} already configured",
        else: ""
      ) <>
      if(summary.errors > 0, do: "; #{summary.errors} failed", else: "")
  end

  defp start_source_launch(socket, source, actor) do
    parent = self()

    case Task.Supervisor.start_child(GnomeGarden.AsyncSupervisor, fn ->
           result =
             safe_launch_result(fn ->
               Acquisition.launch_source_run(source, actor: actor)
             end)

           send(parent, {:source_launch_finished, source.id, source.name, result})
         end) do
      {:ok, _pid} ->
        socket

      {:error, reason} ->
        socket
        |> assign_launching_source(source.id, false)
        |> put_flash(:error, "Could not start source scan launch: #{inspect(reason)}")
    end
  end

  defp start_batch_launch(socket, actor) do
    parent = self()

    case Task.Supervisor.start_child(GnomeGarden.AsyncSupervisor, fn ->
           summary =
             case safe_launch_result(fn ->
                    SourceLaunchBatch.launch_ready_sources(actor: actor)
                  end) do
               {:ok, summary} -> summary
               {:error, _reason} -> failed_batch_summary()
             end

           send(parent, {:ready_source_launches_finished, summary})
         end) do
      {:ok, _pid} ->
        socket

      {:error, reason} ->
        socket
        |> assign(:launching_ready_batch?, false)
        |> put_flash(:error, "Could not start ready source launches: #{inspect(reason)}")
    end
  end

  defp safe_launch_result(fun) do
    {:ok, fun.()}
  rescue
    error -> {:error, error}
  catch
    kind, reason -> {:error, {kind, reason}}
  end

  defp failed_batch_summary do
    %{
      checked: 0,
      eligible: 0,
      launched: 0,
      skipped: 0,
      errors: 1,
      source_ids: []
    }
  end

  defp extraction_summary(%{metadata: metadata}) when is_map(metadata) do
    extraction =
      metadata
      |> metadata_value("last_scan_summary")
      |> metadata_value("extraction")

    if is_map(extraction) do
      rows = metadata_value(extraction, "row_count") || 0
      titles = metadata_value(extraction, "title_count") || 0
      links = metadata_value(extraction, "link_count") || 0
      "Last extraction: #{rows} rows / #{titles} titles / #{links} links"
    end
  end

  defp extraction_summary(_source), do: nil

  defp configuration_exception(%{procurement_source: %{config_status: :config_failed} = source}) do
    case metadata_value(source.metadata, "last_config_error") do
      error when is_binary(error) -> error
      _ -> nil
    end
  end

  defp configuration_exception(_source), do: nil

  defp source_in_bucket?(source, :needs_configuration), do: needs_configuration?(source)
  defp source_in_bucket?(source, :ready), do: scan_ready?(source)
  defp source_in_bucket?(source, :credentials_needed), do: credentials_needed?(source)

  defp source_in_bucket?(source, :attention),
    do:
      source.health_status in [
        :blocked,
        :failing,
        :selector_failed,
        :document_capture_failed,
        :no_results,
        :zero_saved,
        :stale,
        :noisy,
        :cancelled
      ]

  defp source_in_bucket?(_source, :all), do: true

  defp bucket_count(counts, :attention), do: counts.attention
  defp bucket_count(counts, bucket), do: Map.fetch!(counts, bucket)

  defp bucket_label(:needs_configuration), do: "Needs configuration"
  defp bucket_label(:ready), do: "Ready"
  defp bucket_label(:credentials_needed), do: "Credentials needed"
  defp bucket_label(:attention), do: "Attention"
  defp bucket_label(:all), do: "All"

  defp run_state_variant(%{latest_run_id: nil, last_run_at: last_run_at})
       when not is_nil(last_run_at),
       do: :info

  defp run_state_variant(%{latest_run_id: nil, last_run_at: last_run_at})
       when not is_nil(last_run_at),
       do: :info

  defp run_state_variant(%{latest_run_id: nil}), do: :default
  defp run_state_variant(%{last_run_state_variant: variant}) when is_atom(variant), do: variant
  defp run_state_variant(_source), do: :default

  defp run_state_label(%{latest_run_id: nil, last_run_at: last_run_at})
       when not is_nil(last_run_at),
       do: "Run recorded"

  defp run_state_label(%{latest_run_id: nil}), do: "No run yet"

  defp run_state_label(%{last_run_state: state}) when is_atom(state) do
    format_atom(state)
  end

  defp run_state_label(_source), do: "Run recorded"

  defp run_context(%{latest_run_id: nil, last_run_at: last_run_at})
       when not is_nil(last_run_at) do
    "Last run #{format_datetime(last_run_at)}; no agent run link recorded."
  end

  defp run_context(%{latest_run_id: nil}), do: "Launch a scan to create a durable agent run."

  defp run_context(%{latest_run_id: latest_run_id}) when is_binary(latest_run_id) do
    "Run #{String.slice(latest_run_id, 0, 8)}"
  end

  defp run_context(_source), do: "Run linked."

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

  defp credentials_needed?(%{health_status: :needs_login}), do: true
  defp credentials_needed?(_source), do: false

  defp auto_configurable?(%{
         enabled: true,
         status: :active,
         procurement_source: %{config_status: status}
       })
       when status in [:found, :manual],
       do: true

  defp auto_configurable?(%{
         enabled: true,
         status: :active,
         procurement_source: %{config_status: :config_failed} = source
       }) do
    is_nil(metadata_value(source.metadata, "last_config_error"))
  end

  defp auto_configurable?(_source), do: false

  defp needs_operator_attention?(%{procurement_source: %{config_status: :config_failed} = source}) do
    is_binary(metadata_value(source.metadata, "last_config_error"))
  end

  defp needs_operator_attention?(_source), do: false

  defp manual_config_available?(%{procurement_source: %{config_status: status}})
       when status in [:config_failed, :manual],
       do: true

  defp manual_config_available?(_source), do: false

  defp configured_source?(%{procurement_source: %{config_status: status}})
       when status in [:configured, :scan_failed],
       do: true

  defp configured_source?(_source), do: false

  defp agentic_source?(%{procurement_source_id: source_id}) when is_binary(source_id), do: false

  defp agentic_source?(%{scan_strategy: strategy})
       when strategy in [:agentic, :deterministic],
       do: true

  defp agentic_source?(_source), do: false

  defp metadata_value(nil, _key), do: nil

  defp metadata_value(map, key) when is_map(map) do
    Map.get(map, key) || Map.get(map, String.to_existing_atom(key))
  rescue
    ArgumentError -> nil
  end

  defp metadata_value(_value, _key), do: nil
end
