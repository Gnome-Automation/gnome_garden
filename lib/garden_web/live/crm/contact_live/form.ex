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
    <.page max_width="max-w-5xl" class="pb-8">
      <.page_header eyebrow="CRM">
        {@page_title}
        <:subtitle>
          {if @contact,
            do: "Update contact channels and communication preferences.",
            else: "Add a person who can be linked to companies, leads, and ongoing sales activity."}
        </:subtitle>
        <:actions>
          <.button navigate={~p"/crm/contacts"}>
            <.icon name="hero-arrow-left" class="size-4" /> Back to contacts
          </.button>
        </:actions>
      </.page_header>

      <.form for={@form} id="contact-form" phx-change="validate" phx-submit="save" class="space-y-6">
        <.form_section
          title="Personal Information"
          description="Primary identity and the channels your team will use to reach this person."
        >
          <div class="grid grid-cols-1 gap-6 sm:grid-cols-6">
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
        </.form_section>

        <.form_section
          title="Preferences"
          description="Respect communication preferences and mark the contact record appropriately."
        >
          <div class="grid grid-cols-1 gap-6 sm:grid-cols-6">
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
        </.form_section>

        <.section body_class="px-6 py-5 sm:px-7">
          <.form_actions
            cancel_path={~p"/crm/contacts"}
            submit_label={if @contact, do: "Update Contact", else: "Create Contact"}
          />
        </.section>
      </.form>
    </.page>
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
