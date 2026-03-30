defmodule GnomeGardenWeb.Agents.Sales.LeadSourcesLive do
  use GnomeGardenWeb, :live_view

  alias GnomeGarden.Agents.LeadSource

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, :page_title, "Lead Sources")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-4">
      <div class="flex justify-between items-center">
        <h1 class="text-2xl font-bold">Lead Sources</h1>
        <div class="flex gap-2">
          <a href="/admin/agents/lead_source?action=create" class="btn btn-sm btn-primary">
            <.icon name="hero-plus" class="size-4" /> Add Source
          </a>
          <a href="/admin/agents/lead_source" class="btn btn-sm btn-ghost">
            Open in Admin <.icon name="hero-arrow-top-right-on-square" class="size-4" />
          </a>
        </div>
      </div>

      <Cinder.collection
        resource={LeadSource}
        actor={@current_user}
        search={[placeholder: "Search lead sources..."]}
      >
        <:col :let={source} field="name" label="Name" filter sort search>
          <div>
            <div class="font-medium">{source.name}</div>
            <div class="text-sm opacity-50 truncate max-w-xs">{source.url}</div>
          </div>
        </:col>
        <:col :let={source} field="region" label="Region" filter sort>
          {format_region(source.region)}
        </:col>
        <:col :let={source} field="discovery_status" label="Status" filter sort>
          <span class={discovery_badge(source.discovery_status)}>{format_status(source.discovery_status)}</span>
        </:col>
        <:col :let={source} field="last_scanned_at" label="Last Scanned" sort>
          {format_date(source.last_scanned_at)}
        </:col>
        <:col :let={source} field="enabled" label="Enabled" filter>
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

  defp discovery_badge(:pending), do: "badge badge-warning badge-sm"
  defp discovery_badge(:discovered), do: "badge badge-success badge-sm"
  defp discovery_badge(:failed), do: "badge badge-error badge-sm"
  defp discovery_badge(_), do: "badge badge-ghost badge-sm"

  defp format_status(nil), do: "pending"
  defp format_status(status), do: status |> to_string() |> String.replace("_", " ")

  defp format_region(nil), do: "-"
  defp format_region(region), do: region |> to_string() |> String.upcase()

  defp format_date(nil), do: "Never"
  defp format_date(datetime), do: Calendar.strftime(datetime, "%b %d, %H:%M")
end
