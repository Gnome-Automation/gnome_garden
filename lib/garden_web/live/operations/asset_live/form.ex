defmodule GnomeGardenWeb.Operations.AssetLive.Form do
  use GnomeGardenWeb, :live_view

  alias GnomeGarden.Operations

  @impl true
  def mount(params, _session, socket) do
    asset = if id = params["id"], do: load_asset!(id, socket.assigns.current_user)

    {:ok,
     socket
     |> assign(:asset, asset)
     |> assign(:organizations, load_organizations(socket.assigns.current_user))
     |> assign(:sites, load_sites(socket.assigns.current_user))
     |> assign(:managed_systems, load_managed_systems(socket.assigns.current_user))
     |> assign(:assets, load_parent_assets(socket.assigns.current_user, asset))
     |> assign(:page_title, if(asset, do: "Edit Asset", else: "New Asset"))
     |> assign_form(params)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.page max_width="max-w-5xl" class="pb-8">
      <.page_header eyebrow="Operations">
        {@page_title}
        <:subtitle>
          Capture the installed or managed components that downstream service and maintenance work depends on.
        </:subtitle>
        <:actions>
          <.button navigate={~p"/operations/assets"}>
            Back to assets
          </.button>
        </:actions>
      </.page_header>

      <.form for={@form} id="asset-form" phx-change="validate" phx-submit="save" class="space-y-6">
        <.form_section
          title="Asset Details"
          description="Define where the asset lives, how it should be classified, and the identifiers that service teams will use."
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
              <.input
                field={@form[:managed_system_id]}
                type="select"
                label="Managed System"
                prompt="Select system..."
                options={Enum.map(@managed_systems, &{system_label(&1), &1.id})}
              />
            </div>
            <div class="sm:col-span-3">
              <.input
                field={@form[:parent_asset_id]}
                type="select"
                label="Parent Asset"
                prompt="Select parent asset..."
                options={Enum.map(@assets, &{asset_label(&1), &1.id})}
              />
            </div>
            <div class="sm:col-span-3">
              <.input field={@form[:asset_tag]} label="Asset Tag" />
            </div>
            <div class="sm:col-span-3">
              <.input field={@form[:name]} label="Name" required />
            </div>
            <div class="sm:col-span-2">
              <.input
                field={@form[:asset_type]}
                type="select"
                label="Asset Type"
                options={asset_type_options()}
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
            <div class="sm:col-span-2">
              <.input
                field={@form[:criticality]}
                type="select"
                label="Criticality"
                options={criticality_options()}
              />
            </div>
            <div class="sm:col-span-2">
              <.input field={@form[:vendor]} label="Vendor" />
            </div>
            <div class="sm:col-span-2">
              <.input field={@form[:model_number]} label="Model Number" />
            </div>
            <div class="sm:col-span-3">
              <.input field={@form[:serial_number]} label="Serial Number" />
            </div>
            <div class="sm:col-span-3">
              <.input field={@form[:installed_on]} type="date" label="Installed On" />
            </div>
            <div class="sm:col-span-3">
              <.input field={@form[:commissioned_on]} type="date" label="Commissioned On" />
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
            cancel_path={~p"/operations/assets"}
            submit_label={if @asset, do: "Update Asset", else: "Create Asset"}
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
      {:ok, asset} ->
        {:noreply,
         socket
         |> put_flash(:info, "Asset #{if socket.assigns.asset, do: "updated", else: "created"}")
         |> push_navigate(to: ~p"/operations/assets/#{asset}")}

      {:error, form} ->
        {:noreply, assign(socket, form: to_form(form))}
    end
  end

  defp assign_form(%{assigns: %{asset: asset, current_user: actor}} = socket, params) do
    form =
      if asset do
        AshPhoenix.Form.for_update(asset, :update, actor: actor, domain: Operations)
      else
        AshPhoenix.Form.for_create(
          Operations.Asset,
          :create,
          actor: actor,
          domain: Operations,
          params: asset_defaults(params)
        )
      end

    assign(socket, :form, to_form(form))
  end

  defp load_asset!(id, actor) do
    case Operations.get_asset(id, actor: actor) do
      {:ok, asset} -> asset
      {:error, error} -> raise "failed to load asset #{id}: #{inspect(error)}"
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

  defp load_managed_systems(actor) do
    case Operations.list_managed_systems(actor: actor, load: [:organization]) do
      {:ok, systems} -> Enum.sort_by(systems, &String.downcase(&1.name || ""))
      {:error, error} -> raise "failed to load managed systems: #{inspect(error)}"
    end
  end

  defp load_parent_assets(actor, nil) do
    case Operations.list_assets(actor: actor, load: [:organization]) do
      {:ok, assets} -> Enum.sort_by(assets, &String.downcase(&1.name || ""))
      {:error, error} -> raise "failed to load assets: #{inspect(error)}"
    end
  end

  defp load_parent_assets(actor, asset) do
    case Operations.list_assets(actor: actor, load: [:organization]) do
      {:ok, assets} ->
        assets
        |> Enum.reject(&(&1.id == asset.id))
        |> Enum.sort_by(&String.downcase(&1.name || ""))

      {:error, error} ->
        raise "failed to load assets: #{inspect(error)}"
    end
  end

  defp asset_defaults(params) do
    %{}
    |> maybe_put("organization_id", params["organization_id"])
    |> maybe_put("site_id", params["site_id"])
    |> maybe_put("managed_system_id", params["managed_system_id"])
    |> maybe_put("parent_asset_id", params["parent_asset_id"])
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, _key, ""), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp site_label(site) do
    [site.name, site.organization && site.organization.name]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(" · ")
  end

  defp system_label(system) do
    [system.name, system.organization && system.organization.name]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(" · ")
  end

  defp asset_label(asset) do
    [asset.name, asset.organization && asset.organization.name]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(" · ")
  end

  defp asset_type_options do
    [
      {"Controller", :controller},
      {"Panel", :panel},
      {"Sensor", :sensor},
      {"Actuator", :actuator},
      {"Server", :server},
      {"Network", :network},
      {"Application", :application},
      {"Integration", :integration},
      {"Other", :other}
    ]
  end

  defp delivery_mode_options do
    [{"Physical", :physical}, {"Digital", :digital}, {"Hybrid", :hybrid}]
  end

  defp lifecycle_status_options do
    [
      {"Planned", :planned},
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
