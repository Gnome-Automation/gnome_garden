defmodule GnomeGardenWeb.CRM.ContactLive.Form do
  use GnomeGardenWeb, :live_view

  alias GnomeGarden.Sales

  @impl true
  def mount(params, _session, socket) do
    contact =
      if id = params["id"] do
        Sales.get_contact!(id, actor: socket.assigns.current_user)
      else
        nil
      end

    {:ok,
     socket
     |> assign(:contact, contact)
     |> assign(
       :page_title,
       if(contact, do: "Edit #{contact.first_name} #{contact.last_name}", else: "New Contact")
     )
     |> assign_form()}
  end

  defp assign_form(%{assigns: %{contact: contact, current_user: actor}} = socket) do
    form =
      if contact do
        Sales.form_to_update_contact(contact, actor: actor)
      else
        Sales.form_to_create_contact(actor: actor)
      end

    assign(socket, form: to_form(form))
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.header>
      {@page_title}
    </.header>

    <.form
      for={@form}
      id="contact-form"
      phx-change="validate"
      phx-submit="save"
      class="space-y-6 max-w-2xl"
    >
      <div class="grid grid-cols-1 gap-6 sm:grid-cols-2">
        <.input field={@form[:first_name]} label="First Name" required />
        <.input field={@form[:last_name]} label="Last Name" required />
      </div>

      <div class="grid grid-cols-1 gap-6 sm:grid-cols-2">
        <.input field={@form[:email]} label="Email" type="email" />
        <.input field={@form[:phone]} label="Phone" type="tel" />
      </div>

      <.input field={@form[:mobile]} label="Mobile" type="tel" />

      <div class="grid grid-cols-1 gap-6 sm:grid-cols-2">
        <.input
          field={@form[:status]}
          type="select"
          label="Status"
          options={[
            {"Active", :active},
            {"Inactive", :inactive}
          ]}
        />
        <.input
          field={@form[:preferred_contact_method]}
          type="select"
          label="Preferred Contact Method"
          prompt="Select..."
          options={[
            {"Email", :email},
            {"Phone", :phone},
            {"LinkedIn", :linkedin},
            {"Any", :any}
          ]}
        />
      </div>

      <.input field={@form[:linkedin_url]} label="LinkedIn URL" type="url" />

      <div class="grid grid-cols-1 gap-6 sm:grid-cols-2">
        <.input field={@form[:do_not_call]} type="checkbox" label="Do Not Call" />
        <.input field={@form[:do_not_email]} type="checkbox" label="Do Not Email" />
      </div>

      <div class="flex gap-4 pt-4">
        <.button type="submit" variant="primary" phx-disable-with="Saving...">
          Save Contact
        </.button>
        <.button type="button" navigate={~p"/crm/contacts"}>Cancel</.button>
      </div>
    </.form>
    """
  end

  @impl true
  def handle_event("validate", %{"form" => params}, socket) do
    form = AshPhoenix.Form.validate(socket.assigns.form, params)
    {:noreply, assign(socket, form: to_form(form))}
  end

  @impl true
  def handle_event("save", %{"form" => params}, socket) do
    case AshPhoenix.Form.submit(socket.assigns.form, params: params) do
      {:ok, contact} ->
        {:noreply,
         socket
         |> put_flash(
           :info,
           "Contact #{if socket.assigns.contact, do: "updated", else: "created"}"
         )
         |> push_navigate(to: ~p"/crm/contacts/#{contact}")}

      {:error, form} ->
        {:noreply, assign(socket, form: to_form(form))}
    end
  end
end
