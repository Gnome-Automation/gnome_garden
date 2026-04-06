defmodule GnomeGardenWeb.CRM.LeadLive.Show do
  use GnomeGardenWeb, :live_view

  import GnomeGardenWeb.CRM.Helpers

  alias GnomeGarden.Sales

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    lead = Sales.get_lead!(id, actor: socket.assigns.current_user, load: [:company])

    {:ok,
     socket
     |> assign(:page_title, lead.company_name || "Lead")
     |> assign(:lead, lead)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.header>
      {display_name(@lead)}
      <:subtitle>
        <span class={status_badge_class(@lead.status)}>{format_atom(@lead.status)}</span>
        <span :if={@lead.source} class="badge badge-sm badge-ghost ml-1">{@lead.source}</span>
      </:subtitle>
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
        <.heading level={3}>Lead Details</.heading>
        <.properties>
          <.property name="Company">
            <.link
              :if={@lead.company_id}
              navigate={~p"/crm/companies/#{@lead.company_id}"}
              class="text-emerald-600 hover:text-emerald-500"
            >
              {@lead.company_name}
            </.link>
            <span :if={!@lead.company_id}>{@lead.company_name || "-"}</span>
          </.property>
          <.property :if={has_contact?(@lead)} name="Contact">
            {@lead.first_name} {@lead.last_name}
          </.property>
          <.property :if={@lead.title} name="Title">{@lead.title}</.property>
          <.property :if={@lead.email} name="Email">
            <a
              href={"mailto:#{@lead.email}"}
              class="text-emerald-600 hover:text-emerald-500"
            >
              {@lead.email}
            </a>
          </.property>
          <.property :if={@lead.phone} name="Phone">{@lead.phone}</.property>
        </.properties>
      </div>

      <div>
        <.heading level={3}>Source & Status</.heading>
        <.properties>
          <.property name="Status">
            <span class={status_badge_class(@lead.status)}>
              {format_atom(@lead.status)}
            </span>
          </.property>
          <.property name="Source">{format_atom(@lead.source)}</.property>
          <.property :if={@lead.source_details} name="Signal">
            <span class="text-sm font-medium">{@lead.source_details}</span>
          </.property>
          <.property :if={@lead.description} name="Description">
            <span class="text-sm">{@lead.description}</span>
          </.property>
          <.property :if={@lead.source_url} name="Source">
            <a
              href={@lead.source_url}
              target="_blank"
              class="text-emerald-600 hover:text-emerald-500 break-all text-sm"
            >
              {@lead.source_url}
            </a>
          </.property>
          <.property :if={@lead.rejection_reason} name="Rejection Reason">
            <span class="badge badge-error badge-sm">
              {format_atom(@lead.rejection_reason)}
            </span>
          </.property>
          <.property :if={@lead.rejection_notes} name="Rejection Notes">
            {@lead.rejection_notes}
          </.property>
          <.property name="Created">{format_datetime(@lead.inserted_at)}</.property>
          <.property :if={@lead.converted_at} name="Converted">
            {format_datetime(@lead.converted_at)}
          </.property>
        </.properties>
      </div>
    </div>
    """
  end

  defp display_name(lead) do
    if has_contact?(lead) do
      "#{lead.first_name} #{lead.last_name}"
    else
      lead.company_name || "Unknown Lead"
    end
  end

  defp has_contact?(lead) do
    lead.first_name not in [nil, "Unknown", "Bid", "Hiring", "Expansion"] and
      lead.last_name not in [nil, lead.company_name]
  end

  defp status_badge_class(:new), do: "badge badge-warning badge-sm"
  defp status_badge_class(:screening), do: "badge badge-info badge-sm"
  defp status_badge_class(:qualified), do: "badge badge-success badge-sm"
  defp status_badge_class(:outreach), do: "badge badge-primary badge-sm"
  defp status_badge_class(:meeting), do: "badge badge-primary badge-sm"
  defp status_badge_class(:proposal), do: "badge badge-accent badge-sm"
  defp status_badge_class(:converted), do: "badge badge-success badge-sm"
  defp status_badge_class(:rejected), do: "badge badge-error badge-sm"
  defp status_badge_class(_), do: "badge badge-ghost badge-sm"
end
