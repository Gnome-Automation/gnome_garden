defmodule GnomeGardenWeb.CRM.ContactsLive do
  use GnomeGardenWeb, :live_view

  alias GnomeGarden.Sales.Contact

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, :page_title, "Contacts")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-4">
      <div class="flex justify-between items-center">
        <h1 class="text-2xl font-bold">Contacts</h1>
        <div class="flex gap-2">
          <a href="/admin/sales/contact?action=create" class="btn btn-sm btn-primary">
            <.icon name="hero-plus" class="size-4" /> Add Contact
          </a>
        </div>
      </div>

      <Cinder.collection
        resource={Contact}
        actor={@current_user}
        search={[placeholder: "Search contacts..."]}
      >
        <:col :let={contact} field="first_name" label="Name" filter sort search>
          <span class="font-medium">{contact.first_name} {contact.last_name}</span>
        </:col>
        <:col :let={contact} field="email" label="Email" filter search>
          {contact.email || "-"}
        </:col>
        <:col :let={contact} field="phone" label="Phone" search>
          {contact.phone || "-"}
        </:col>
        <:col :let={contact} field="status" label="Status" filter sort>
          <span class={status_badge(contact.status)}>{format_status(contact.status)}</span>
        </:col>
        <:col :let={contact} label="">
          <a href={"/admin/sales/contact/#{contact.id}"} class="btn btn-xs btn-ghost">
            <.icon name="hero-pencil" class="size-4" />
          </a>
        </:col>
      </Cinder.collection>
    </div>
    """
  end

  defp status_badge(nil), do: "badge badge-ghost badge-sm"
  defp status_badge(:active), do: "badge badge-success badge-sm"
  defp status_badge(:inactive), do: "badge badge-warning badge-sm"
  defp status_badge(:left_company), do: "badge badge-error badge-sm"
  defp status_badge(_), do: "badge badge-ghost badge-sm"

  defp format_status(nil), do: "active"
  defp format_status(status), do: status |> to_string() |> String.replace("_", " ")
end
