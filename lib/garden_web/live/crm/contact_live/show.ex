defmodule GnomeGardenWeb.CRM.ContactLive.Show do
  use GnomeGardenWeb, :live_view

  import GnomeGardenWeb.CRM.Helpers

  alias GnomeGarden.Sales

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    contact = Sales.get_contact!(id, actor: socket.assigns.current_user)

    {:ok,
     socket
     |> assign(:page_title, "#{contact.first_name} #{contact.last_name}")
     |> assign(:contact, contact)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.header>
      {@contact.first_name} {@contact.last_name}
      <:actions>
        <.button navigate={~p"/crm/contacts"}>
          <.icon name="hero-arrow-left" class="size-4" /> Back
        </.button>
        <.button variant="primary" navigate={~p"/crm/contacts/#{@contact}/edit"}>
          <.icon name="hero-pencil-square" class="size-4" /> Edit
        </.button>
      </:actions>
    </.header>

    <div class="mt-6 grid grid-cols-1 gap-8 lg:grid-cols-2">
      <div>
        <.heading level={3}>Contact Information</.heading>
        <.properties>
          <.property name="Email">
            <a
              :if={@contact.email}
              href={"mailto:#{@contact.email}"}
              class="text-emerald-600 hover:text-emerald-500 dark:text-emerald-400"
            >
              {@contact.email}
            </a>
            <span :if={!@contact.email} class="text-zinc-400">-</span>
          </.property>
          <.property name="Phone">{@contact.phone || "-"}</.property>
          <.property name="Mobile">{@contact.mobile || "-"}</.property>
          <.property name="LinkedIn">
            <a
              :if={@contact.linkedin_url}
              href={@contact.linkedin_url}
              target="_blank"
              class="text-emerald-600 hover:text-emerald-500 dark:text-emerald-400"
            >
              View Profile
            </a>
            <span :if={!@contact.linkedin_url} class="text-zinc-400">-</span>
          </.property>
        </.properties>
      </div>

      <div>
        <.heading level={3}>Preferences</.heading>
        <.properties>
          <.property name="Status">
            <.status_badge status={contact_status(@contact.status)}>
              {format_atom(@contact.status)}
            </.status_badge>
          </.property>
          <.property name="Preferred Contact">
            {format_atom(@contact.preferred_contact_method)}
          </.property>
          <.property name="Do Not Call">
            <.status_badge :if={@contact.do_not_call} status={:error}>Yes</.status_badge>
            <span :if={!@contact.do_not_call}>No</span>
          </.property>
          <.property name="Do Not Email">
            <.status_badge :if={@contact.do_not_email} status={:error}>Yes</.status_badge>
            <span :if={!@contact.do_not_email}>No</span>
          </.property>
          <.property :if={@contact.last_contacted_at} name="Last Contacted">
            {format_datetime(@contact.last_contacted_at)}
          </.property>
        </.properties>
      </div>
    </div>
    """
  end
end
