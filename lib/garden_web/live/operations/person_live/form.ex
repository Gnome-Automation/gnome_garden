defmodule GnomeGardenWeb.Operations.PersonLive.Form do
  use GnomeGardenWeb, :live_view

  alias GnomeGarden.Operations

  @impl true
  def mount(params, _session, socket) do
    person = if id = params["id"], do: load_person!(id, socket.assigns.current_user)

    {:ok,
     socket
     |> assign(:person, person)
     |> assign(:page_title, if(person, do: "Edit Person", else: "New Person"))
     |> assign_form()}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.page max_width="max-w-5xl" class="pb-8">
      <.page_header eyebrow="Operations">
        {@page_title}
        <:subtitle>
          Create the durable external person record that commercial, service, and delivery contexts should share.
        </:subtitle>
        <:actions>
          <.button navigate={~p"/operations/people"}>
            <.icon name="hero-arrow-left" class="size-4" /> Back to people
          </.button>
        </:actions>
      </.page_header>

      <.form for={@form} id="person-form" phx-change="validate" phx-submit="save" class="space-y-6">
        <.form_section
          title="Person Details"
          description="Capture one durable person record instead of duplicating contacts per company or workflow."
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
            <div class="sm:col-span-3">
              <.input
                field={@form[:status]}
                type="select"
                label="Status"
                options={status_options()}
              />
            </div>
            <div class="sm:col-span-3">
              <.input
                field={@form[:preferred_contact_method]}
                type="select"
                label="Preferred Contact Method"
                prompt="Select..."
                options={contact_method_options()}
              />
            </div>
            <div class="sm:col-span-3">
              <.input field={@form[:timezone]} label="Timezone" />
            </div>
            <div class="sm:col-span-3">
              <.input field={@form[:do_not_call]} type="checkbox" label="Do Not Call" />
            </div>
            <div class="sm:col-span-3">
              <.input field={@form[:do_not_email]} type="checkbox" label="Do Not Email" />
            </div>
            <div class="col-span-full">
              <.input field={@form[:notes]} type="textarea" label="Notes" />
            </div>
          </div>
        </.form_section>

        <.section body_class="px-6 py-5 sm:px-7">
          <.form_actions
            cancel_path={~p"/operations/people"}
            submit_label={if @person, do: "Update Person", else: "Create Person"}
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
      {:ok, person} ->
        {:noreply,
         socket
         |> put_flash(:info, "Person #{if socket.assigns.person, do: "updated", else: "created"}")
         |> push_navigate(to: ~p"/operations/people/#{person}")}

      {:error, form} ->
        {:noreply, assign(socket, form: to_form(form))}
    end
  end

  defp assign_form(%{assigns: %{person: person, current_user: actor}} = socket) do
    form =
      if person do
        AshPhoenix.Form.for_update(person, :update, actor: actor, domain: Operations)
      else
        AshPhoenix.Form.for_create(Operations.Person, :create, actor: actor, domain: Operations)
      end

    assign(socket, :form, to_form(form))
  end

  defp load_person!(id, actor) do
    case Operations.get_person(id, actor: actor) do
      {:ok, person} -> person
      {:error, error} -> raise "failed to load person #{id}: #{inspect(error)}"
    end
  end

  defp status_options do
    [
      {"Active", :active},
      {"Inactive", :inactive},
      {"Archived", :archived}
    ]
  end

  defp contact_method_options do
    [
      {"Email", :email},
      {"Phone", :phone},
      {"SMS", :sms},
      {"LinkedIn", :linkedin},
      {"Any", :any}
    ]
  end
end
