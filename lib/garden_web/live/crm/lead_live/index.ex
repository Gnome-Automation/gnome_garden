defmodule GnomeGardenWeb.CRM.LeadLive.Index do
  use GnomeGardenWeb, :live_view

  alias GnomeGarden.Sales.Lead

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, :page_title, "Leads")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <div class="flex justify-end">
        <.button navigate={~p"/crm/leads/new"} variant="primary">
          <.icon name="hero-plus" class="size-4" /> Add Lead
        </.button>
      </div>

      <Cinder.collection
        resource={Lead}
        actor={@current_user}
        search={[placeholder: "Search leads..."]}
      >
        <:col :let={lead} field="first_name" label="Name" sort search>
          <.link navigate={~p"/crm/leads/#{lead}"} class="font-medium hover:text-emerald-600">
            {lead.first_name} {lead.last_name}
          </.link>
        </:col>
        <:col :let={lead} field="company_name" label="Company" search>
          {lead.company_name || "-"}
        </:col>
        <:col :let={lead} field="email" label="Email" search>
          {lead.email || "-"}
        </:col>
        <:col :let={lead} field="status" label="Status" sort>
          <span class={status_badge(lead.status)}>{format_status(lead.status)}</span>
        </:col>
        <:col :let={lead} field="source" label="Source">
          {format_source(lead.source)}
        </:col>
        <:col :let={lead} label="">
          <.link
            navigate={~p"/crm/leads/#{lead}/edit"}
            class="inline-flex items-center justify-center rounded-md p-1.5 text-zinc-400 transition hover:bg-zinc-900/5 hover:text-zinc-600 dark:hover:bg-white/5 dark:hover:text-zinc-300"
          >
            <.icon name="hero-pencil" class="size-4" />
          </.link>
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
