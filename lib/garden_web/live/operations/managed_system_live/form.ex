defmodule GnomeGardenWeb.Operations.ManagedSystemLive.Form do
  use GnomeGardenWeb, :live_view

  alias GnomeGarden.Operations

  @impl true
  def mount(params, _session, socket) do
    managed_system =
      if id = params["id"] do
        load_managed_system!(id, socket.assigns.current_user)
      end

    {:ok,
     socket
     |> assign(:managed_system, managed_system)
     |> assign(:organizations, load_organizations(socket.assigns.current_user))
     |> assign(:sites, load_sites(socket.assigns.current_user))
     |> assign(
       :page_title,
       if(managed_system, do: "Edit Managed System", else: "New Managed System")
     )
     |> assign_form(params)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.page max_width="max-w-5xl" class="pb-8">
      <.page_header eyebrow="Operations">
        {@page_title}
        <:subtitle>
          Create system-level context for automation stacks, software platforms, and hybrid installations.
        </:subtitle>
        <:actions>
          <.button navigate={~p"/operations/managed-systems"}>
            Back to systems
          </.button>
        </:actions>
      </.page_header>

      <.form
        for={@form}
        id="managed-system-form"
        phx-change="validate"
        phx-submit="save"
        class="space-y-6"
      >
        <.form_section
          title="Managed System Details"
          description="Use managed systems to group assets and service history around the actual automation or software stack."
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
                field={@form[:site_id]}
                type="select"
                label="Site"
                prompt="Select site..."
                options={Enum.map(@sites, &{site_label(&1), &1.id})}
              />
            </div>
            <div class="sm:col-span-3">
              <.input field={@form[:code]} label="System Code" />
            </div>
            <div class="sm:col-span-3">
              <.input field={@form[:name]} label="Name" required />
            </div>
            <div class="sm:col-span-2">
              <.input
                field={@form[:system_type]}
                type="select"
                label="System Type"
                options={system_type_options()}
              />
            </div>
            <div class="sm:col-span-2">
              <.input
                field={@form[:delivery_mode]}
                type="select"
                label="Delivery Mode"
                options={delivery_mode_options()}
              />
            </div>
            <div class="sm:col-span-2">
              <.input
                field={@form[:lifecycle_status]}
                type="select"
                label="Lifecycle Status"
                options={lifecycle_status_options()}
              />
            </div>
            <div class="sm:col-span-3">
              <.input
                field={@form[:criticality]}
                type="select"
                label="Criticality"
                options={criticality_options()}
              />
            </div>
            <div class="sm:col-span-3">
              <.input field={@form[:vendor]} label="Vendor" />
            </div>
            <div class="sm:col-span-3">
              <.input field={@form[:platform]} label="Platform" />
            </div>
            <div class="col-span-full">
              <.input field={@form[:description]} type="textarea" label="Description" />
            </div>
            <div class="col-span-full">
              <.input field={@form[:notes]} type="textarea" label="Notes" />
            </div>
          </div>
        </.form_section>

        <.section body_class="px-6 py-5 sm:px-7">
          <.form_actions
            cancel_path={~p"/operations/managed-systems"}
            submit_label={
              if @managed_system, do: "Update Managed System", else: "Create Managed System"
            }
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
      {:ok, managed_system} ->
        {:noreply,
         socket
         |> put_flash(
           :info,
           "Managed system #{if socket.assigns.managed_system, do: "updated", else: "created"}"
         )
         |> push_navigate(to: ~p"/operations/managed-systems/#{managed_system}")}

      {:error, form} ->
        {:noreply, assign(socket, form: to_form(form))}
    end
  end

  defp assign_form(
         %{assigns: %{managed_system: managed_system, current_user: actor}} = socket,
         params
       ) do
    form =
      if managed_system do
        AshPhoenix.Form.for_update(managed_system, :update, actor: actor, domain: Operations)
      else
        AshPhoenix.Form.for_create(
          Operations.ManagedSystem,
          :create,
          actor: actor,
          domain: Operations,
          params: managed_system_defaults(params)
        )
      end

    assign(socket, :form, to_form(form))
  end

  defp load_managed_system!(id, actor) do
    case Operations.get_managed_system(id, actor: actor) do
      {:ok, managed_system} -> managed_system
      {:error, error} -> raise "failed to load managed system #{id}: #{inspect(error)}"
    end
  end

  defp load_organizations(actor) do
    case Operations.list_organizations(actor: actor) do
      {:ok, organizations} -> Enum.sort_by(organizations, &String.downcase(&1.name || ""))
      {:error, error} -> raise "failed to load organizations: #{inspect(error)}"
    end
  end

  defp load_sites(actor) do
    case Operations.list_sites(actor: actor, load: [:organization]) do
      {:ok, sites} -> Enum.sort_by(sites, &String.downcase(&1.name || ""))
      {:error, error} -> raise "failed to load sites: #{inspect(error)}"
    end
  end

  defp managed_system_defaults(params) do
    %{}
    |> maybe_put("organization_id", params["organization_id"])
    |> maybe_put("site_id", params["site_id"])
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, _key, ""), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp site_label(site) do
    [site.name, site.organization && site.organization.name]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(" · ")
  end

  defp system_type_options do
    [
      {"Automation", :automation},
      {"Software", :software},
      {"Integration", :integration},
      {"Network", :network},
      {"Hybrid", :hybrid},
      {"Service", :service},
      {"Other", :other}
    ]
  end

  defp delivery_mode_options do
    [{"Physical", :physical}, {"Digital", :digital}, {"Hybrid", :hybrid}]
  end

  defp lifecycle_status_options do
    [
      {"Prospective", :prospective},
      {"Active", :active},
      {"On Hold", :on_hold},
      {"Retired", :retired},
      {"Unsupported", :unsupported}
    ]
  end

  defp criticality_options do
    [{"Low", :low}, {"Normal", :normal}, {"High", :high}, {"Critical", :critical}]
  end
end
