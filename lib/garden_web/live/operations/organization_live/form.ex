defmodule GnomeGardenWeb.Operations.OrganizationLive.Form do
  use GnomeGardenWeb, :live_view

  alias GnomeGarden.Operations

  @impl true
  def mount(params, _session, socket) do
    organization = if id = params["id"], do: load_organization!(id, socket.assigns.current_user)

    {:ok,
     socket
     |> assign(:organization, organization)
     |> assign(:return_to, params["return_to"])
     |> assign(:highlight_billing_contact, params["highlight"] == "billing_contact")
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
            Back to organizations
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
              <label class="block text-sm/6 font-medium text-gray-900 dark:text-white">
                Relationship Roles
              </label>
              <div class="mt-2 flex flex-wrap gap-x-6 gap-y-2">
                <%= for {label, value} <- role_options() do %>
                  <label class="flex items-center gap-2 text-sm text-gray-900 dark:text-white cursor-pointer">
                    <input
                      type="checkbox"
                      name={"#{@form[:relationship_roles].name}[]"}
                      value={value}
                      checked={value in ((@form[:relationship_roles].value || []) |> Enum.map(&to_string/1))}
                      class="rounded border-gray-300 text-emerald-600 focus:ring-emerald-600 dark:border-white/20 dark:bg-white/5"
                    />
                    {label}
                  </label>
                <% end %>
                <input type="hidden" name={"#{@form[:relationship_roles].name}[]"} value="" />
              </div>
            </div>
            <div class="sm:col-span-3">
              <.input field={@form[:website]} label="Website" />
              <p :if={@form[:website_domain].errors != []} class="mt-1 text-sm text-red-600">
                Website domain has already been taken — use a different URL or leave it blank.
              </p>
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
            <div :if={@organization} class={["sm:col-span-3 rounded-lg transition-all", @highlight_billing_contact && "ring-2 ring-amber-400 p-3"]}>
              <.input
                field={@form[:billing_contact_id]}
                type="select"
                label="Billing Contact"
                prompt="None — use any affiliated contact"
                options={billing_contact_options(@organization)}
              />
              <p class="mt-1.5 text-xs text-base-content/50">
                Only people affiliated with this organization appear here.
                <.link navigate={~p"/operations/affiliations/new"} class="underline text-emerald-600 dark:text-emerald-400">Add an affiliation</.link>
                first if the person you want isn't listed.
              </p>
            </div>
          </div>
        </.form_section>

        <.section body_class="px-6 py-5 sm:px-7">
          <.form_actions
            cancel_path={@return_to || ~p"/operations/organizations"}
            submit_label={if @organization, do: "Update Organization", else: "Create Organization"}
          />
        </.section>
      </.form>
    </.page>
    """
  end

  @impl true
  def handle_event("validate", %{"form" => params}, socket) do
    form = AshPhoenix.Form.validate(socket.assigns.form, sanitize_params(params))
    {:noreply, assign(socket, form: to_form(form))}
  end

  @impl true
  def handle_event("save", %{"form" => params}, socket) do
    case AshPhoenix.Form.submit(socket.assigns.form, params: sanitize_params(params)) do
      {:ok, organization} ->
        path =
          if is_nil(socket.assigns.organization) && socket.assigns.return_to do
            socket.assigns.return_to
          else
            ~p"/operations/organizations/#{organization}"
          end

        {:noreply,
         socket
         |> put_flash(:info, "Organization #{if socket.assigns.organization, do: "updated", else: "created"}")
         |> push_navigate(to: path)}

      {:error, form} ->
        {:noreply,
         socket
         |> put_flash(:error, "Please fix the errors below.")
         |> assign(form: to_form(form))}
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
    case Operations.get_organization(id,
           actor: actor,
           load: [people: [:full_name], billing_contact: []]
         ) do
      {:ok, organization} -> organization
      {:error, error} -> raise "failed to load organization #{id}: #{inspect(error)}"
    end
  end

  defp billing_contact_options(nil), do: []

  defp billing_contact_options(organization) do
    (organization.people || [])
    |> Enum.map(fn person -> {person.full_name, person.id} end)
  end

  defp sanitize_params(params) do
    Map.update(params, "relationship_roles", [], fn roles ->
      Enum.reject(roles, &(&1 == ""))
    end)
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
