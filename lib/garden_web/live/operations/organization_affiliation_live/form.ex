defmodule GnomeGardenWeb.Operations.OrganizationAffiliationLive.Form do
  use GnomeGardenWeb, :live_view

  alias GnomeGarden.Operations

  @impl true
  def mount(params, _session, socket) do
    affiliation = if id = params["id"], do: load_affiliation!(id, socket.assigns.current_user)

    {:ok,
     socket
     |> assign(:affiliation, affiliation)
     |> assign(:organizations, load_organizations(socket.assigns.current_user))
     |> assign(:people, load_people(socket.assigns.current_user))
     |> assign(:page_title, if(affiliation, do: "Edit Affiliation", else: "New Affiliation"))
     |> assign_form(prefill_params(params))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.page max_width="max-w-5xl" class="pb-8">
      <.page_header eyebrow="Operations">
        {@page_title}
        <:subtitle>
          Attach a durable person to a durable organization without duplicating the same contact across workflows.
        </:subtitle>
        <:actions>
          <.button navigate={~p"/operations/affiliations"}>
            Back to affiliations
          </.button>
        </:actions>
      </.page_header>

      <.form
        for={@form}
        id="organization-affiliation-form"
        phx-change="validate"
        phx-submit="save"
        class="space-y-6"
      >
        <.form_section
          title="Relationship Details"
          description="Capture who the person is for the organization, how they should be contacted, and whether they are the primary contact."
        >
          <div class="grid grid-cols-1 gap-6 sm:grid-cols-6">
            <div class="sm:col-span-3">
              <.input
                field={@form[:organization_id]}
                type="select"
                label="Organization"
                prompt="Select organization..."
                options={Enum.map(@organizations, &{&1.name, &1.id})}
              />
              <p class="mt-1.5 text-xs text-base-content/50">
                Organization not in the list?
                <.link navigate={~p"/operations/organizations/new?return_to=#{~p"/operations/affiliations/new"}"} class="underline text-emerald-600 dark:text-emerald-400">Create one first</.link>.
              </p>
            </div>
            <div class="sm:col-span-3">
              <.input
                field={@form[:person_id]}
                type="select"
                label="Person"
                prompt="Select person..."
                options={Enum.map(@people, &{&1.full_name, &1.id})}
              />
              <p class="mt-1.5 text-xs text-base-content/50">
                Person not in the list?
                <.link navigate={~p"/operations/people/new?return_to=#{~p"/operations/affiliations/new"}"} class="underline text-emerald-600 dark:text-emerald-400">Create one first</.link>.
              </p>
            </div>
            <div class="sm:col-span-3">
              <.input field={@form[:title]} label="Title" />
            </div>
            <div class="sm:col-span-3">
              <.input field={@form[:department]} label="Department" />
            </div>
            <div class="col-span-full">
              <label class="block text-sm/6 font-medium text-gray-900 dark:text-white">
                Contact Roles
              </label>
              <div class="mt-2 flex flex-wrap gap-x-6 gap-y-2">
                <%= for {label, value} <- contact_role_options() do %>
                  <label class="flex items-center gap-2 text-sm text-gray-900 dark:text-white cursor-pointer">
                    <input
                      type="checkbox"
                      name={"#{@form[:contact_roles].name}[]"}
                      value={value}
                      checked={value in ((@form[:contact_roles].value || []) |> Enum.map(&to_string/1))}
                      class="rounded border-gray-300 text-emerald-600 focus:ring-emerald-600 dark:border-white/20 dark:bg-white/5"
                    />
                    {label}
                  </label>
                <% end %>
                <input type="hidden" name={"#{@form[:contact_roles].name}[]"} value="" />
              </div>
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
              <.input field={@form[:is_primary]} type="checkbox" label="Primary Contact" />
            </div>
            <div class="sm:col-span-3">
              <.input field={@form[:started_on]} type="date" label="Started On" />
            </div>
            <div class="sm:col-span-3">
              <.input field={@form[:ended_on]} type="date" label="Ended On" />
            </div>
            <div class="col-span-full">
              <.input field={@form[:notes]} type="textarea" label="Notes" />
            </div>
          </div>
        </.form_section>

        <.section body_class="px-6 py-5 sm:px-7">
          <.form_actions
            cancel_path={~p"/operations/affiliations"}
            submit_label={if @affiliation, do: "Update Affiliation", else: "Create Affiliation"}
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
      {:ok, affiliation} ->
        {flash, path} =
          if socket.assigns.affiliation do
            {"Affiliation updated", ~p"/operations/affiliations/#{affiliation}"}
          else
            maybe_set_billing_contact(affiliation, socket.assigns.current_user)
          end

        {:noreply, socket |> put_flash(:info, flash) |> push_navigate(to: path)}

      {:error, form} ->
        {:noreply,
         socket
         |> put_flash(:error, "Please fix the errors below.")
         |> assign(form: to_form(form))}
    end
  end

  defp sanitize_params(params) do
    Map.update(params, "contact_roles", [], fn roles ->
      Enum.reject(roles, &(&1 == ""))
    end)
  end

  defp maybe_set_billing_contact(affiliation, actor) do
    if "billing_contact" in (affiliation.contact_roles |> Enum.map(&to_string/1)) do
      with {:ok, org} <- Operations.get_organization(affiliation.organization_id,
                           actor: actor, load: [:billing_contact]) do
        previous = org.billing_contact

        Operations.update_organization(org, %{billing_contact_id: affiliation.person_id}, actor: actor)

        flash =
          if previous && previous.id != affiliation.person_id do
            "Affiliation created — billing contact updated from #{previous.full_name} to the new contact"
          else
            "Affiliation created — billing contact set automatically"
          end

        {flash, ~p"/operations/organizations/#{affiliation.organization_id}"}
      end
    else
      if_org_has_no_billing_contact(affiliation, actor)
    end
  end

  defp if_org_has_no_billing_contact(affiliation, actor) do
    case Operations.get_organization(affiliation.organization_id, actor: actor) do
      {:ok, org} when not is_nil(org.billing_contact_id) ->
        {"Affiliation created", ~p"/operations/organizations/#{affiliation.organization_id}"}

      _ ->
        {"Affiliation created — you can now set a billing contact for this organization",
         ~p"/operations/organizations/#{affiliation.organization_id}/edit?highlight=billing_contact"}
    end
  end

  defp assign_form(%{assigns: %{affiliation: affiliation, current_user: actor}} = socket, params) do
    form =
      if affiliation do
        AshPhoenix.Form.for_update(affiliation, :update, actor: actor, domain: Operations)
      else
        AshPhoenix.Form.for_create(
          Operations.OrganizationAffiliation,
          :create,
          actor: actor,
          domain: Operations,
          params: params
        )
      end

    assign(socket, :form, to_form(form))
  end

  defp load_affiliation!(id, actor) do
    case Operations.get_organization_affiliation(id, actor: actor) do
      {:ok, affiliation} -> affiliation
      {:error, error} -> raise "failed to load affiliation #{id}: #{inspect(error)}"
    end
  end

  defp load_organizations(actor) do
    case Operations.list_organizations(actor: actor) do
      {:ok, organizations} -> Enum.sort_by(organizations, &String.downcase(&1.name || ""))
      {:error, error} -> raise "failed to load organizations: #{inspect(error)}"
    end
  end

  defp load_people(actor) do
    case Operations.list_people(actor: actor, load: [:full_name]) do
      {:ok, people} ->
        Enum.sort_by(people, fn person ->
          String.downcase(
            person.full_name || "#{person.last_name || ""} #{person.first_name || ""}"
          )
        end)

      {:error, error} ->
        raise "failed to load people: #{inspect(error)}"
    end
  end

  defp prefill_params(params) do
    params
    |> Map.take(["organization_id", "person_id"])
    |> Enum.reject(fn {_key, value} -> is_nil(value) or value == "" end)
    |> Map.new()
  end

  defp status_options do
    [
      {"Active", :active},
      {"Inactive", :inactive},
      {"Former", :former}
    ]
  end

  defp contact_role_options do
    [
      {"Buyer", "buyer"},
      {"Billing Contact", "billing_contact"},
      {"Decision Maker", "decision_maker"},
      {"Executive Sponsor", "executive_sponsor"},
      {"Procurement", "procurement"},
      {"Project Sponsor", "project_sponsor"},
      {"Service Contact", "service_contact"},
      {"Technical Contact", "technical_contact"}
    ]
  end
end
