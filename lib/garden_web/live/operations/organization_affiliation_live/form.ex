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
            <.icon name="hero-arrow-left" class="size-4" /> Back to affiliations
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
            </div>
            <div class="sm:col-span-3">
              <.input
                field={@form[:person_id]}
                type="select"
                label="Person"
                prompt="Select person..."
                options={Enum.map(@people, &{&1.full_name, &1.id})}
              />
            </div>
            <div class="sm:col-span-3">
              <.input field={@form[:title]} label="Title" />
            </div>
            <div class="sm:col-span-3">
              <.input field={@form[:department]} label="Department" />
            </div>
            <div class="col-span-full">
              <.input
                field={@form[:contact_roles]}
                type="select"
                multiple
                label="Contact Roles"
                options={contact_role_options()}
              />
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
    form = AshPhoenix.Form.validate(socket.assigns.form, params)
    {:noreply, assign(socket, form: to_form(form))}
  end

  @impl true
  def handle_event("save", %{"form" => params}, socket) do
    case AshPhoenix.Form.submit(socket.assigns.form, params: params) do
      {:ok, affiliation} ->
        {:noreply,
         socket
         |> put_flash(
           :info,
           "Affiliation #{if socket.assigns.affiliation, do: "updated", else: "created"}"
         )
         |> push_navigate(to: ~p"/operations/affiliations/#{affiliation}")}

      {:error, form} ->
        {:noreply, assign(socket, form: to_form(form))}
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
