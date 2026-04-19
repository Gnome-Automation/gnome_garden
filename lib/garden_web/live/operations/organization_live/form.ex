defmodule GnomeGardenWeb.Operations.OrganizationLive.Form do
  use GnomeGardenWeb, :live_view

  alias GnomeGarden.Operations

  @impl true
  def mount(params, _session, socket) do
    organization = if id = params["id"], do: load_organization!(id, socket.assigns.current_user)

    {:ok,
     socket
     |> assign(:organization, organization)
     |> assign(:page_title, if(organization, do: "Edit Organization", else: "New Organization"))
     |> assign_form()}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.page max_width="max-w-5xl" class="pb-8">
      <.page_header eyebrow="Operations">
        {@page_title}
        <:subtitle>
          Define the durable account record that commercial, service, and delivery work should attach to.
        </:subtitle>
        <:actions>
          <.button navigate={~p"/operations/organizations"}>
            <.icon name="hero-arrow-left" class="size-4" /> Back to organizations
          </.button>
        </:actions>
      </.page_header>

      <.form
        for={@form}
        id="organization-form"
        phx-change="validate"
        phx-submit="save"
        class="space-y-6"
      >
        <.form_section
          title="Organization Details"
          description="Capture the durable org identity first. Relationship roles can evolve over time without changing the core record."
        >
          <div class="grid grid-cols-1 gap-6 sm:grid-cols-6">
            <div class="sm:col-span-4">
              <.input field={@form[:name]} label="Name" required />
            </div>
            <div class="sm:col-span-4">
              <.input field={@form[:legal_name]} label="Legal Name" />
            </div>
            <div class="sm:col-span-3">
              <.input
                field={@form[:organization_kind]}
                type="select"
                label="Organization Kind"
                options={[
                  {"Business", :business},
                  {"Government", :government},
                  {"Nonprofit", :nonprofit},
                  {"Internal", :internal},
                  {"Individual", :individual},
                  {"Other", :other}
                ]}
              />
            </div>
            <div class="sm:col-span-3">
              <.input
                field={@form[:status]}
                type="select"
                label="Status"
                options={[
                  {"Prospect", :prospect},
                  {"Active", :active},
                  {"Inactive", :inactive},
                  {"Archived", :archived}
                ]}
              />
            </div>
            <div class="col-span-full">
              <.input
                field={@form[:relationship_roles]}
                type="select"
                multiple
                label="Relationship Roles"
                options={role_options()}
              />
            </div>
            <div class="sm:col-span-3">
              <.input field={@form[:website]} label="Website" />
            </div>
            <div class="sm:col-span-3">
              <.input field={@form[:phone]} label="Phone" />
            </div>
            <div class="sm:col-span-3">
              <.input field={@form[:primary_region]} label="Primary Region" />
            </div>
            <div class="col-span-full">
              <.input field={@form[:notes]} type="textarea" label="Notes" />
            </div>
          </div>
        </.form_section>

        <.section body_class="px-6 py-5 sm:px-7">
          <.form_actions
            cancel_path={~p"/operations/organizations"}
            submit_label={if @organization, do: "Update Organization", else: "Create Organization"}
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
      {:ok, organization} ->
        {:noreply,
         socket
         |> put_flash(
           :info,
           "Organization #{if socket.assigns.organization, do: "updated", else: "created"}"
         )
         |> push_navigate(to: ~p"/operations/organizations/#{organization}")}

      {:error, form} ->
        {:noreply, assign(socket, form: to_form(form))}
    end
  end

  defp assign_form(%{assigns: %{organization: organization, current_user: actor}} = socket) do
    form =
      if organization do
        AshPhoenix.Form.for_update(organization, :update, actor: actor, domain: Operations)
      else
        AshPhoenix.Form.for_create(Operations.Organization, :create,
          actor: actor,
          domain: Operations
        )
      end

    assign(socket, :form, to_form(form))
  end

  defp load_organization!(id, actor) do
    case Operations.get_organization(id, actor: actor) do
      {:ok, organization} -> organization
      {:error, error} -> raise "failed to load organization #{id}: #{inspect(error)}"
    end
  end

  defp role_options do
    [
      {"Customer", "customer"},
      {"Prospect", "prospect"},
      {"Vendor", "vendor"},
      {"Subcontractor", "subcontractor"},
      {"Partner", "partner"},
      {"Agency", "agency"},
      {"Internal", "internal"}
    ]
  end
end
