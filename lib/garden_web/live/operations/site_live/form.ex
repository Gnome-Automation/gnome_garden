defmodule GnomeGardenWeb.Operations.SiteLive.Form do
  use GnomeGardenWeb, :live_view

  alias GnomeGarden.Operations

  @impl true
  def mount(params, _session, socket) do
    site = if id = params["id"], do: load_site!(id, socket.assigns.current_user)

    {:ok,
     socket
     |> assign(:site, site)
     |> assign(:organizations, load_organizations(socket.assigns.current_user))
     |> assign(:page_title, if(site, do: "Edit Site", else: "New Site"))
     |> assign_form(params)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.page max_width="max-w-5xl" class="pb-8">
      <.page_header eyebrow="Operations">
        {@page_title}
        <:subtitle>
          Create durable site records for physical facilities and digital operating environments.
        </:subtitle>
        <:actions>
          <.button navigate={~p"/operations/sites"}>
            <.icon name="hero-arrow-left" class="size-4" /> Back to sites
          </.button>
        </:actions>
      </.page_header>

      <.form for={@form} id="site-form" phx-change="validate" phx-submit="save" class="space-y-6">
        <.form_section
          title="Site Details"
          description="Tie the site to an organization and make the location explicit enough for delivery and service teams to use."
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
              <.input field={@form[:code]} label="Site Code" />
            </div>
            <div class="col-span-full">
              <.input field={@form[:name]} label="Name" required />
            </div>
            <div class="sm:col-span-3">
              <.input
                field={@form[:site_kind]}
                type="select"
                label="Site Kind"
                options={site_kind_options()}
              />
            </div>
            <div class="sm:col-span-3">
              <.input field={@form[:status]} type="select" label="Status" options={status_options()} />
            </div>
            <div class="col-span-full">
              <.input field={@form[:address1]} label="Address 1" />
            </div>
            <div class="col-span-full">
              <.input field={@form[:address2]} label="Address 2" />
            </div>
            <div class="sm:col-span-2">
              <.input field={@form[:city]} label="City" />
            </div>
            <div class="sm:col-span-2">
              <.input field={@form[:state]} label="State" />
            </div>
            <div class="sm:col-span-2">
              <.input field={@form[:postal_code]} label="Postal Code" />
            </div>
            <div class="sm:col-span-3">
              <.input field={@form[:country_code]} label="Country Code" />
            </div>
            <div class="sm:col-span-3">
              <.input field={@form[:timezone]} label="Timezone" />
            </div>
            <div class="col-span-full">
              <.input field={@form[:notes]} type="textarea" label="Notes" />
            </div>
          </div>
        </.form_section>

        <.section body_class="px-6 py-5 sm:px-7">
          <.form_actions
            cancel_path={~p"/operations/sites"}
            submit_label={if @site, do: "Update Site", else: "Create Site"}
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
      {:ok, site} ->
        {:noreply,
         socket
         |> put_flash(:info, "Site #{if socket.assigns.site, do: "updated", else: "created"}")
         |> push_navigate(to: ~p"/operations/sites/#{site}")}

      {:error, form} ->
        {:noreply, assign(socket, form: to_form(form))}
    end
  end

  defp assign_form(%{assigns: %{site: site, current_user: actor}} = socket, params) do
    form =
      if site do
        AshPhoenix.Form.for_update(site, :update, actor: actor, domain: Operations)
      else
        AshPhoenix.Form.for_create(
          Operations.Site,
          :create,
          actor: actor,
          domain: Operations,
          params: site_defaults(params)
        )
      end

    assign(socket, :form, to_form(form))
  end

  defp load_site!(id, actor) do
    case Operations.get_site(id, actor: actor) do
      {:ok, site} -> site
      {:error, error} -> raise "failed to load site #{id}: #{inspect(error)}"
    end
  end

  defp load_organizations(actor) do
    case Operations.list_organizations(actor: actor) do
      {:ok, organizations} -> Enum.sort_by(organizations, &String.downcase(&1.name || ""))
      {:error, error} -> raise "failed to load organizations: #{inspect(error)}"
    end
  end

  defp site_defaults(params) do
    case params["organization_id"] do
      nil -> %{}
      "" -> %{}
      organization_id -> %{"organization_id" => organization_id}
    end
  end

  defp site_kind_options do
    [
      {"Facility", :facility},
      {"Campus", :campus},
      {"Office", :office},
      {"Lab", :lab},
      {"Cloud", :cloud},
      {"Remote", :remote},
      {"Other", :other}
    ]
  end

  defp status_options do
    [
      {"Active", :active},
      {"Inactive", :inactive},
      {"Commissioning", :commissioning},
      {"Retired", :retired}
    ]
  end
end
