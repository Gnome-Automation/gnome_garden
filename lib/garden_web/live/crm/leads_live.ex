defmodule GnomeGardenWeb.CRM.LeadsLive do
  use GnomeGardenWeb, :live_view

  alias GnomeGarden.Sales.Lead

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, :page_title, "Leads")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-4">
      <div class="flex justify-between items-center">
        <h1 class="text-2xl font-bold">Leads</h1>
        <div class="flex gap-2">
          <a href="/admin/sales/lead?action=create" class="btn btn-sm btn-primary">
            <.icon name="hero-plus" class="size-4" /> Add Lead
          </a>
        </div>
      </div>

      <Cinder.collection
        resource={Lead}
        actor={@current_user}
        search={[placeholder: "Search leads..."]}
      >
        <:col :let={lead} field="first_name" label="Name" filter sort search>
          <span class="font-medium">{lead.first_name} {lead.last_name}</span>
        </:col>
        <:col :let={lead} field="company_name" label="Company" filter search>
          {lead.company_name || "-"}
        </:col>
        <:col :let={lead} field="email" label="Email" filter search>
          {lead.email || "-"}
        </:col>
        <:col :let={lead} field="status" label="Status" filter sort>
          <span class={status_badge(lead.status)}>{format_status(lead.status)}</span>
        </:col>
        <:col :let={lead} field="source" label="Source" filter>
          {format_source(lead.source)}
        </:col>
        <:col :let={lead} label="">
          <a href={"/admin/sales/lead/#{lead.id}"} class="btn btn-xs btn-ghost">
            <.icon name="hero-pencil" class="size-4" />
          </a>
        </:col>
      </Cinder.collection>
    </div>
    """
  end

  defp status_badge(:new), do: "badge badge-primary badge-sm"
  defp status_badge(:contacted), do: "badge badge-info badge-sm"
  defp status_badge(:qualified), do: "badge badge-success badge-sm"
  defp status_badge(:unqualified), do: "badge badge-warning badge-sm"
  defp status_badge(:converted), do: "badge badge-accent badge-sm"
  defp status_badge(_), do: "badge badge-ghost badge-sm"

  defp format_status(nil), do: "new"
  defp format_status(status), do: status |> to_string() |> String.replace("_", " ")

  defp format_source(nil), do: "-"
  defp format_source(source), do: source |> to_string() |> String.replace("_", " ")
end
