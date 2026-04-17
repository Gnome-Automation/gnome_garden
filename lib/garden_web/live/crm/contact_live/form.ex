defmodule GnomeGardenWeb.CRM.ContactLive.Form do
  use GnomeGardenWeb, :live_view

  alias GnomeGarden.CRM.Forms, as: CRMForms

  @impl true
  def mount(params, _session, socket) do
    contact =
      if id = params["id"] do
        CRMForms.get_contact!(id, actor: socket.assigns.current_user)
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
        CRMForms.form_to_update_contact(contact, actor: actor)
      else
        CRMForms.form_to_create_contact(actor: actor)
      end

    assign(socket, form: to_form(form))
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.header>
      {@page_title}
    </.header>

    <.form for={@form} id="contact-form" phx-change="validate" phx-submit="save">
      <div class="space-y-12">
        <div class="border-b border-gray-900/10 pb-12 dark:border-white/10">
          <h2 class="text-base/7 font-semibold text-gray-900 dark:text-white">
            Personal Information
          </h2>
          <p class="mt-1 text-sm/6 text-gray-600 dark:text-gray-400">
            Name and contact details.
          </p>
          <div class="mt-10 grid grid-cols-1 gap-x-6 gap-y-8 sm:grid-cols-6">
            <div class="sm:col-span-3">
              <.input field={@form[:first_name]} label="First Name" required />
            </div>
            <div class="sm:col-span-3">
              <.input field={@form[:last_name]} label="Last Name" required />
            </div>
            <div class="sm:col-span-3">
              <.input field={@form[:email]} label="Email" type="email" />
            </div>
            <div class="sm:col-span-3">
              <.input field={@form[:phone]} label="Phone" type="tel" />
            </div>
            <div class="sm:col-span-3">
              <.input field={@form[:mobile]} label="Mobile" type="tel" />
            </div>
            <div class="sm:col-span-3">
              <.input field={@form[:linkedin_url]} label="LinkedIn URL" type="url" />
            </div>
          </div>
        </div>

        <div class="border-b border-gray-900/10 pb-12 dark:border-white/10">
          <h2 class="text-base/7 font-semibold text-gray-900 dark:text-white">Preferences</h2>
          <p class="mt-1 text-sm/6 text-gray-600 dark:text-gray-400">
            Status, contact preferences, and communication opt-outs.
          </p>
          <div class="mt-10 grid grid-cols-1 gap-x-6 gap-y-8 sm:grid-cols-6">
            <div class="sm:col-span-3">
              <.input
                field={@form[:status]}
                type="select"
                label="Status"
                options={[
                  {"Active", :active},
                  {"Inactive", :inactive}
                ]}
              />
            </div>
            <div class="sm:col-span-3">
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
            <div class="sm:col-span-3">
              <.input field={@form[:do_not_call]} type="checkbox" label="Do Not Call" />
            </div>
            <div class="sm:col-span-3">
              <.input field={@form[:do_not_email]} type="checkbox" label="Do Not Email" />
            </div>
          </div>
        </div>
      </div>

      <div class="mt-6 flex items-center justify-end gap-x-6">
        <.button type="button" navigate={~p"/crm/contacts"}>Cancel</.button>
        <.button type="submit" variant="primary" phx-disable-with="Saving...">Save</.button>
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
