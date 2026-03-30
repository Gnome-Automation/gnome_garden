defmodule GnomeGardenWeb.Agents.Sales.ProspectsLive do
  use GnomeGardenWeb, :live_view

  alias GnomeGarden.Agents.Prospect

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, :page_title, "Prospects")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-4">
      <div class="flex justify-between items-center">
        <h1 class="text-2xl font-bold">Prospects</h1>
        <a href="/admin/agents/prospect" class="btn btn-sm btn-ghost">
          Open in Admin <.icon name="hero-arrow-top-right-on-square" class="size-4" />
        </a>
      </div>

      <Cinder.collection
        resource={Prospect}
        actor={@current_user}
        search={[placeholder: "Search prospects..."]}
      >
        <:col :let={prospect} field="name" label="Name" filter sort search>
          <span class="font-medium">{prospect.name}</span>
        </:col>
        <:col :let={prospect} field="website" label="Website" search>
          <a :if={prospect.website} href={prospect.website} target="_blank" class="link link-primary">
            {URI.parse(prospect.website).host}
          </a>
          <span :if={!prospect.website} class="opacity-50">-</span>
        </:col>
        <:col :let={prospect} field="industry" label="Industry" filter search>
          {prospect.industry || "-"}
        </:col>
        <:col :let={prospect} field="status" label="Status" filter sort>
          <span class={status_badge(prospect.status)}>{format_status(prospect.status)}</span>
        </:col>
        <:col :let={prospect} field="source_type" label="Source" filter>
          {format_source(prospect.source_type)}
        </:col>
        <:col :let={prospect} label="">
          <a href={"/admin/agents/prospect/#{prospect.id}"} class="btn btn-xs btn-ghost">
            <.icon name="hero-pencil" class="size-4" />
          </a>
        </:col>
      </Cinder.collection>
    </div>
    """
  end

  defp status_badge(:new), do: "badge badge-primary badge-sm"
  defp status_badge(:researching), do: "badge badge-info badge-sm"
  defp status_badge(:qualified), do: "badge badge-success badge-sm"
  defp status_badge(:contacted), do: "badge badge-warning badge-sm"
  defp status_badge(:won), do: "badge badge-accent badge-sm"
  defp status_badge(:lost), do: "badge badge-error badge-sm"
  defp status_badge(_), do: "badge badge-ghost badge-sm"

  defp format_status(nil), do: "new"
  defp format_status(status), do: status |> to_string() |> String.replace("_", " ")

  defp format_source(nil), do: "-"
  defp format_source(source), do: source |> to_string() |> String.replace("_", " ")
end
