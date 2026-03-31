defmodule GnomeGardenWeb.CRM.ContactLive.Show do
  use GnomeGardenWeb, :live_view

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
        <h2 class="text-base font-semibold mb-4">Contact Information</h2>
        <.list>
          <:item title="Email">
            <a
              :if={@contact.email}
              href={"mailto:#{@contact.email}"}
              class="text-emerald-600 hover:text-emerald-500 dark:text-emerald-400"
            >
              {@contact.email}
            </a>
            <span :if={!@contact.email} class="text-zinc-400">-</span>
          </:item>
          <:item title="Phone">{@contact.phone || "-"}</:item>
          <:item title="Mobile">{@contact.mobile || "-"}</:item>
          <:item title="LinkedIn">
            <a
              :if={@contact.linkedin_url}
              href={@contact.linkedin_url}
              target="_blank"
              class="text-emerald-600 hover:text-emerald-500 dark:text-emerald-400"
            >
              View Profile
            </a>
            <span :if={!@contact.linkedin_url} class="text-zinc-400">-</span>
          </:item>
        </.list>
      </div>

      <div>
        <h2 class="text-base font-semibold mb-4">Preferences</h2>
        <.list>
          <:item title="Status">{format_atom(@contact.status)}</:item>
          <:item title="Preferred Contact">{format_atom(@contact.preferred_contact_method)}</:item>
          <:item title="Do Not Call">
            <span :if={@contact.do_not_call} class="text-error">Yes</span>
            <span :if={!@contact.do_not_call}>No</span>
          </:item>
          <:item title="Do Not Email">
            <span :if={@contact.do_not_email} class="text-error">Yes</span>
            <span :if={!@contact.do_not_email}>No</span>
          </:item>
          <:item :if={@contact.last_contacted_at} title="Last Contacted">
            {Calendar.strftime(@contact.last_contacted_at, "%b %d, %Y %H:%M")}
          </:item>
        </.list>
      </div>
    </div>
    """
  end

  defp format_atom(nil), do: "-"
  defp format_atom(atom), do: atom |> to_string() |> String.replace("_", " ") |> String.capitalize()
end
