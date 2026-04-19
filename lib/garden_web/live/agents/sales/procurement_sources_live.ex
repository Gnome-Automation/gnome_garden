defmodule GnomeGardenWeb.Agents.Sales.ProcurementSourcesLive do
  use GnomeGardenWeb, :live_view

  alias GnomeGarden.Agents.Procurement.SourceConfigurator
  alias GnomeGarden.Procurement

  @topics [
    "procurement_source:configured",
    "procurement_source:config_failed",
    "procurement_source:scanned",
    "procurement_source:scan_failed",
    "procurement_source:queued"
  ]

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Enum.each(@topics, &GnomeGardenWeb.Endpoint.subscribe/1)
    end

    {:ok,
     socket
     |> assign(:page_title, "Procurement Sources")
     |> assign(:focus_id, nil)
     |> assign(:source_count, 0)
     |> stream(:sources, [], reset: true)}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    {:noreply,
     socket
     |> assign(:focus_id, params["focus"])
     |> load_sources()}
  end

  @impl true
  def handle_info(%{topic: "procurement_source:" <> _}, socket) do
    {:noreply, load_sources(socket)}
  end

  @impl true
  def handle_event("toggle_enabled", %{"id" => id}, socket) do
    with {:ok, source} <- fetch_source(id, socket),
         {:ok, _source} <-
           Procurement.update_procurement_source(
             source,
             %{enabled: !source.enabled},
             actor_opts(socket)
           ) do
      {:noreply,
       socket
       |> load_sources()
       |> put_flash(:info, enabled_message(source))}
    else
      {:error, error} -> {:noreply, put_flash(socket, :error, error_message(error))}
    end
  end

  def handle_event("approve_source", %{"id" => id}, socket) do
    with {:ok, source} <- fetch_source(id, socket),
         {:ok, _source} <- Procurement.approve_procurement_source(source, %{}, actor_opts(socket)) do
      {:noreply,
       socket
       |> load_sources()
       |> put_flash(:info, "Approved #{source.name} for configuration and scanning.")}
    else
      {:error, error} -> {:noreply, put_flash(socket, :error, error_message(error))}
    end
  end

  def handle_event("ignore_source", %{"id" => id}, socket) do
    with {:ok, source} <- fetch_source(id, socket),
         {:ok, _source} <- Procurement.ignore_procurement_source(source, %{}, actor_opts(socket)) do
      {:noreply,
       socket
       |> load_sources()
       |> put_flash(:info, "Ignored #{source.name}.")}
    else
      {:error, error} -> {:noreply, put_flash(socket, :error, error_message(error))}
    end
  end

  def handle_event("block_source", %{"id" => id}, socket) do
    with {:ok, source} <- fetch_source(id, socket),
         {:ok, _source} <- Procurement.block_procurement_source(source, %{}, actor_opts(socket)) do
      {:noreply,
       socket
       |> load_sources()
       |> put_flash(:info, "Blocked #{source.name}.")}
    else
      {:error, error} -> {:noreply, put_flash(socket, :error, error_message(error))}
    end
  end

  def handle_event("reconsider_source", %{"id" => id}, socket) do
    with {:ok, source} <- fetch_source(id, socket),
         {:ok, _source} <-
           Procurement.reconsider_procurement_source(source, %{}, actor_opts(socket)) do
      {:noreply,
       socket
       |> load_sources()
       |> put_flash(:info, "Moved #{source.name} back to candidates.")}
    else
      {:error, error} -> {:noreply, put_flash(socket, :error, error_message(error))}
    end
  end

  def handle_event("discover_source", %{"id" => id}, socket) do
    with {:ok, source} <- fetch_source(id, socket),
         {:ok, %{source: _source, mode: mode}} <-
           SourceConfigurator.discover_source(source, actor: socket.assigns.current_user) do
      {:noreply,
       socket
       |> load_sources()
       |> put_flash(:info, discovery_message(source, mode))}
    else
      {:error, error} -> {:noreply, put_flash(socket, :error, error_message(error))}
    end
  end

  def handle_event("scan_source", %{"id" => id}, socket) do
    with {:ok, source} <- fetch_source(id, socket),
         {:ok, _source} <- Procurement.scan_procurement_source(source, %{}, actor_opts(socket)) do
      {:noreply,
       socket
       |> load_sources()
       |> put_flash(:info, "Triggered scan for #{source.name}.")}
    else
      {:error, error} -> {:noreply, put_flash(socket, :error, error_message(error))}
    end
  end

  def handle_event("retry_source", %{"id" => id}, socket) do
    with {:ok, source} <- fetch_source(id, socket),
         {:ok, _source} <- retry_source(source, socket) do
      {:noreply,
       socket
       |> load_sources()
       |> put_flash(:info, retry_message(source))}
    else
      {:error, error} -> {:noreply, put_flash(socket, :error, error_message(error))}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <div class="flex items-start justify-between gap-4">
        <div>
          <h1 class="text-2xl font-semibold tracking-tight text-zinc-900 dark:text-white">
            Procurement Sources
          </h1>
          <p class="mt-1 text-sm text-zinc-600 dark:text-zinc-400">
            Native operator view for procurement sources discovered and scanned by agents.
          </p>
        </div>

        <div class="rounded-2xl border border-zinc-200 bg-white px-4 py-3 text-right shadow-sm dark:border-zinc-800 dark:bg-zinc-900">
          <p class="text-xs font-medium uppercase tracking-wide text-zinc-500 dark:text-zinc-400">
            Sources
          </p>
          <p class="mt-1 text-2xl font-semibold text-zinc-900 dark:text-white">{@source_count}</p>
        </div>
      </div>

      <section class="rounded-2xl border border-zinc-200 bg-white shadow-sm dark:border-zinc-800 dark:bg-zinc-900">
        <div class="border-b border-zinc-200 px-5 py-4 dark:border-zinc-800">
          <h2 class="text-lg font-semibold text-zinc-900 dark:text-white">Tracked Sources</h2>
          <p class="text-sm text-zinc-600 dark:text-zinc-400">
            Launch site discovery, retry failed configuration, or trigger scans without leaving the console.
          </p>
        </div>

        <div
          id="procurement-sources"
          phx-update="stream"
          class="divide-y divide-zinc-200 dark:divide-zinc-800"
        >
          <div class="hidden only:block px-5 py-8 text-center text-sm text-zinc-500 dark:text-zinc-400">
            No procurement sources yet.
          </div>

          <div
            :for={{dom_id, source} <- @streams.sources}
            id={dom_id}
            class={[
              "px-5 py-4",
              source_focus_class(source, @focus_id)
            ]}
          >
            <div class="flex flex-col gap-4 xl:flex-row xl:items-start xl:justify-between">
              <div class="min-w-0 space-y-3">
                <div class="flex flex-wrap items-center gap-2">
                  <p class="font-medium text-zinc-900 dark:text-white">{source.name}</p>
                  <.status_badge status={source.status_variant}>
                    {format_status(source.status)}
                  </.status_badge>
                  <.status_badge status={source.config_status_variant}>
                    {format_status(source.config_status)}
                  </.status_badge>
                  <.status_badge status={source.enabled_variant}>
                    {if(source.enabled, do: "enabled", else: "disabled")}
                  </.status_badge>
                  <span class="badge badge-ghost badge-sm">
                    {format_source_type(source.source_type)}
                  </span>
                  <span class="badge badge-ghost badge-sm">{format_region(source.region)}</span>
                </div>

                <div class="flex flex-wrap items-center gap-x-4 gap-y-2 text-sm text-zinc-600 dark:text-zinc-400">
                  <a
                    href={source.url}
                    target="_blank"
                    rel="noreferrer"
                    class="truncate font-medium text-emerald-600 hover:text-emerald-500 dark:text-emerald-400 dark:hover:text-emerald-300"
                  >
                    {source.url}
                  </a>

                  <span :if={source.portal_id}>Portal ID: {source.portal_id}</span>
                  <span>Added {format_date(source.inserted_at)}</span>
                  <span>Last scanned {format_date(source.last_scanned_at)}</span>
                </div>

                <div :if={source.notes} class="text-sm text-zinc-600 dark:text-zinc-300">
                  {source.notes}
                </div>
              </div>

              <div class="flex flex-wrap items-center gap-2 xl:justify-end">
                <button
                  :if={source.status == :candidate}
                  type="button"
                  class="btn btn-sm btn-primary"
                  phx-click="approve_source"
                  phx-value-id={source.id}
                >
                  Approve
                </button>

                <button
                  :if={source.status == :candidate}
                  type="button"
                  class="btn btn-sm"
                  phx-click="ignore_source"
                  phx-value-id={source.id}
                >
                  Ignore
                </button>

                <button
                  :if={source.status in [:candidate, :approved]}
                  type="button"
                  class="btn btn-sm"
                  phx-click="block_source"
                  phx-value-id={source.id}
                >
                  Block
                </button>

                <button
                  :if={
                    source.status == :approved and
                      source.config_status in [:found, :pending, :config_failed]
                  }
                  type="button"
                  class="btn btn-sm btn-primary"
                  phx-click="discover_source"
                  phx-value-id={source.id}
                >
                  {discovery_button_label(source)}
                </button>

                <button
                  :if={
                    source.status == :approved and source.config_status in [:configured, :scan_failed]
                  }
                  type="button"
                  class="btn btn-sm"
                  phx-click={
                    if(source.config_status == :scan_failed, do: "retry_source", else: "scan_source")
                  }
                  phx-value-id={source.id}
                >
                  {if(source.config_status == :scan_failed, do: "Retry Scan", else: "Scan Now")}
                </button>

                <button
                  :if={source.status in [:ignored, :blocked]}
                  type="button"
                  class="btn btn-sm"
                  phx-click="reconsider_source"
                  phx-value-id={source.id}
                >
                  Reconsider
                </button>

                <button
                  type="button"
                  class="btn btn-sm"
                  phx-click="toggle_enabled"
                  phx-value-id={source.id}
                >
                  {if(source.enabled, do: "Disable", else: "Enable")}
                </button>

                <a
                  href={source.url}
                  target="_blank"
                  rel="noreferrer"
                  class="btn btn-sm btn-ghost"
                >
                  Open Portal
                </a>
              </div>
            </div>
          </div>
        </div>
      </section>
    </div>
    """
  end

  defp load_sources(socket) do
    sources = Procurement.list_console_procurement_sources!(actor_opts(socket))

    socket
    |> assign(:source_count, length(sources))
    |> stream(:sources, sources, reset: true)
  end

  defp fetch_source(id, socket) do
    Procurement.get_procurement_source(id, actor_opts(socket))
  end

  defp retry_source(source, socket) do
    case source.config_status do
      :config_failed ->
        Procurement.retry_procurement_source_config(source, %{}, actor_opts(socket))

      :scan_failed ->
        Procurement.retry_procurement_source_scan(source, %{}, actor_opts(socket))

      _ ->
        {:error, "This source is not in a retryable state."}
    end
  end

  defp retry_message(%{config_status: :config_failed, name: name}),
    do: "Retrying configuration for #{name}."

  defp retry_message(%{config_status: :scan_failed, name: name}),
    do: "Retrying scan for #{name}."

  defp discovery_message(%{name: name}, :already_pending),
    do: "Discovery already pending for #{name}. Launched SmartScanner."

  defp discovery_message(%{name: name}, :started),
    do: "Started SmartScanner discovery for #{name}."

  defp enabled_message(%{enabled: true, name: name}), do: "Disabled #{name}."
  defp enabled_message(%{enabled: false, name: name}), do: "Enabled #{name}."

  defp discovery_button_label(%{config_status: :config_failed}), do: "Retry Discovery"
  defp discovery_button_label(%{config_status: :pending}), do: "Run Discovery"
  defp discovery_button_label(_source), do: "Discover Config"

  defp actor_opts(socket) do
    case socket.assigns.current_user do
      nil -> []
      user -> [actor: user]
    end
  end

  defp source_focus_class(%{id: id}, id),
    do: "bg-emerald-50/70 dark:bg-emerald-500/10"

  defp source_focus_class(_source, _focus_id), do: nil

  defp format_status(nil), do: "pending"
  defp format_status(status), do: status |> to_string() |> String.replace("_", " ")

  defp format_source_type(nil), do: "-"

  defp format_source_type(source_type) do
    source_type
    |> to_string()
    |> String.replace("_", " ")
  end

  defp format_region(nil), do: "-"
  defp format_region(region), do: region |> to_string() |> String.upcase()

  defp format_date(nil), do: "-"
  defp format_date(datetime), do: Calendar.strftime(datetime, "%b %d, %H:%M")

  defp error_message(%Ash.Error.Invalid{} = error),
    do: Ash.Error.to_error_class(error) |> inspect()

  defp error_message(error) when is_exception(error), do: Exception.message(error)
  defp error_message(error) when is_binary(error), do: error
  defp error_message(error), do: inspect(error)
end
