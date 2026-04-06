defmodule GnomeGardenWeb.Agents.Sales.LeadSourcesLive do
  use GnomeGardenWeb, :live_view

  alias GnomeGarden.Agents.LeadSource

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      GnomeGardenWeb.Endpoint.subscribe("lead_source:configured")
      GnomeGardenWeb.Endpoint.subscribe("lead_source:config_failed")
      GnomeGardenWeb.Endpoint.subscribe("lead_source:scanned")
      GnomeGardenWeb.Endpoint.subscribe("lead_source:scan_failed")
      GnomeGardenWeb.Endpoint.subscribe("lead_source:queued")
    end

    {:ok, assign(socket, :page_title, "Lead Sources")}
  end

  @impl true
  def handle_info(%{topic: "lead_source:" <> _}, socket) do
    {:noreply, Cinder.refresh_table(socket, "lead-sources")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-4">
      <div class="flex justify-end gap-2">
        <a href="/admin/agents/lead_source?action=create" class="btn btn-sm btn-primary gap-1">
          <.icon name="hero-plus" class="size-4" /> Add Source
        </a>
        <a href="/admin/agents/lead_source" class="btn btn-sm btn-ghost gap-1">
          Open in Admin <.icon name="hero-arrow-top-right-on-square" class="size-4" />
        </a>
      </div>

      <Cinder.collection
        id="lead-sources"
        resource={LeadSource}
        actor={@current_user}
        search={[placeholder: "Search lead sources..."]}
      >
        <:col :let={source} field="name" label="Name" sort search>
          <div>
            <div class="font-medium">{source.name}</div>
            <div class="text-sm opacity-50 truncate max-w-xs">{source.url}</div>
          </div>
        </:col>
        <:col :let={source} field="region" label="Region" sort>
          {format_region(source.region)}
        </:col>
        <:col :let={source} field="config_status" label="Config" sort>
          <span class={config_badge(source.config_status)}>
            {format_status(source.config_status)}
          </span>
        </:col>
        <:col :let={source} field="inserted_at" label="Added" sort>
          {format_date(source.inserted_at)}
        </:col>
        <:col :let={source} field="configured_at" label="Configured" sort>
          {format_date(source.configured_at)}
        </:col>
        <:col :let={source} field="last_scanned_at" label="Last Scanned" sort>
          {format_date(source.last_scanned_at)}
        </:col>
        <:col :let={source} field="enabled" label="Enabled">
          <span :if={source.enabled} class="badge badge-success badge-sm">Yes</span>
          <span :if={!source.enabled} class="badge badge-ghost badge-sm">No</span>
        </:col>
        <:col :let={source} label="">
          <a href={"/admin/agents/lead_source/#{source.id}"} class="btn btn-xs btn-ghost">
            <.icon name="hero-pencil" class="size-4" />
          </a>
        </:col>
      </Cinder.collection>
    </div>
    """
  end

  defp config_badge(:found), do: "badge badge-ghost badge-sm"
  defp config_badge(:pending), do: "badge badge-warning badge-sm"
  defp config_badge(:configured), do: "badge badge-success badge-sm"
  defp config_badge(:config_failed), do: "badge badge-error badge-sm"
  defp config_badge(:scan_failed), do: "badge badge-error badge-sm"
  defp config_badge(:manual), do: "badge badge-info badge-sm"
  defp config_badge(_), do: "badge badge-ghost badge-sm"

  defp format_status(nil), do: "pending"
  defp format_status(status), do: status |> to_string() |> String.replace("_", " ")

  defp format_region(nil), do: "-"
  defp format_region(region), do: region |> to_string() |> String.upcase()

  defp format_date(nil), do: "-"
  defp format_date(datetime), do: Calendar.strftime(datetime, "%b %d, %H:%M")
end
