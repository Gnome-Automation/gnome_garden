defmodule GnomeGardenWeb.CRM.ContactLive.Index do
  use GnomeGardenWeb, :live_view

  import GnomeGardenWeb.CRM.Helpers

  alias GnomeGarden.Sales.Contact

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, page_title: "Contacts")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.page class="pb-8">
      <.page_header eyebrow="CRM">
        Contacts
        <:subtitle>
          Maintain the people connected to accounts, pursuits, and follow-up work.
        </:subtitle>
        <:actions>
          <.button navigate={~p"/crm/contacts/new"} variant="primary">
            <.icon name="hero-plus" class="size-4" /> Add Contact
          </.button>
        </:actions>
      </.page_header>

      <.section
        title="Contact Directory"
        description="Search by name or channel and open records for outreach context."
        compact
        body_class="p-0"
      >
        <Cinder.collection
          id="contacts"
          resource={Contact}
          actor={@current_user}
          search={[placeholder: "Search contacts..."]}
        >
          <:col :let={contact} field="first_name" label="Name" sort search>
            <.link navigate={~p"/crm/contacts/#{contact}"} class="font-medium hover:text-emerald-600">
              {contact.first_name} {contact.last_name}
            </.link>
          </:col>
          <:col :let={contact} field="email" label="Email" search>
            {contact.email || "-"}
          </:col>
          <:col :let={contact} field="phone" label="Phone" search>
            {contact.phone || "-"}
          </:col>
          <:col :let={contact} field="status" label="Status" sort>
            <.status_badge status={contact_status(contact.status)}>
              {format_atom(contact.status)}
            </.status_badge>
          </:col>
          <:col :let={contact} label="">
            <.link
              navigate={~p"/crm/contacts/#{contact}/edit"}
              class="inline-flex items-center justify-center rounded-md p-1.5 text-zinc-400 transition hover:bg-zinc-900/5 hover:text-zinc-600 dark:hover:bg-white/5 dark:hover:text-zinc-300"
            >
              <.icon name="hero-pencil" class="size-4" />
            </.link>
          </:col>
        </Cinder.collection>
      </.section>
    </.page>
    """
  end
end
