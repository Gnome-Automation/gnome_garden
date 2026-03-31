defmodule GnomeGardenWeb.CRM.LeadLive.Show do
  use GnomeGardenWeb, :live_view

  alias GnomeGarden.Sales

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    lead = Sales.get_lead!(id, actor: socket.assigns.current_user)

    {:ok,
     socket
     |> assign(:page_title, "#{lead.first_name} #{lead.last_name}")
     |> assign(:lead, lead)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.header>
      {@lead.first_name} {@lead.last_name}
      <:subtitle :if={@lead.title}>{@lead.title}</:subtitle>
      <:actions>
        <.button navigate={~p"/crm/leads"}>
          <.icon name="hero-arrow-left" class="size-4" /> Back
        </.button>
        <.button variant="primary" navigate={~p"/crm/leads/#{@lead}/edit"}>
          <.icon name="hero-pencil-square" class="size-4" /> Edit
        </.button>
      </:actions>
    </.header>

    <div class="mt-6 grid grid-cols-1 gap-8 lg:grid-cols-2">
      <div>
        <h2 class="text-base font-semibold mb-4">Lead Information</h2>
        <.list>
          <:item title="Company">{@lead.company_name || "-"}</:item>
          <:item title="Email">
            <a
              :if={@lead.email}
              href={"mailto:#{@lead.email}"}
              class="text-emerald-600 hover:text-emerald-500 dark:text-emerald-400"
            >
              {@lead.email}
            </a>
            <span :if={!@lead.email} class="text-zinc-400">-</span>
          </:item>
          <:item title="Phone">{@lead.phone || "-"}</:item>
          <:item title="Title">{@lead.title || "-"}</:item>
        </.list>
      </div>

      <div>
        <h2 class="text-base font-semibold mb-4">Status & Source</h2>
        <.list>
          <:item title="Status">
            <span class={status_badge(@lead.status)}>{format_atom(@lead.status)}</span>
          </:item>
          <:item title="Source">{format_atom(@lead.source)}</:item>
          <:item :if={@lead.source_details} title="Source Details">{@lead.source_details}</:item>
          <:item :if={@lead.converted_at} title="Converted At">
            {Calendar.strftime(@lead.converted_at, "%b %d, %Y %H:%M")}
          </:item>
        </.list>
      </div>
    </div>
    """
  end

  defp status_badge(:new), do: "badge badge-primary badge-sm"
  defp status_badge(:contacted), do: "badge badge-info badge-sm"
  defp status_badge(:qualified), do: "badge badge-success badge-sm"
  defp status_badge(:unqualified), do: "badge badge-warning badge-sm"
  defp status_badge(:converted), do: "badge badge-accent badge-sm"
  defp status_badge(_), do: "badge badge-ghost badge-sm"

  defp format_atom(nil), do: "-"
  defp format_atom(atom), do: atom |> to_string() |> String.replace("_", " ") |> String.capitalize()
end
