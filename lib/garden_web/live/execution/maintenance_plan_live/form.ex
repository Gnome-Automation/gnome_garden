defmodule GnomeGardenWeb.Execution.MaintenancePlanLive.Form do
  use GnomeGardenWeb, :live_view

  alias GnomeGarden.Commercial
  alias GnomeGarden.Execution
  alias GnomeGarden.Operations

  @impl true
  def mount(params, _session, socket) do
    maintenance_plan =
      if id = params["id"] do
        load_maintenance_plan!(id, socket.assigns.current_user)
      end

    {:ok,
     socket
     |> assign(:maintenance_plan, maintenance_plan)
     |> assign(:organizations, load_organizations(socket.assigns.current_user))
     |> assign(:sites, load_sites(socket.assigns.current_user))
     |> assign(:managed_systems, load_managed_systems(socket.assigns.current_user))
     |> assign(:assets, load_assets(socket.assigns.current_user))
     |> assign(:agreements, load_agreements(socket.assigns.current_user))
     |> assign(
       :page_title,
       if(maintenance_plan, do: "Edit Maintenance Plan", else: "New Maintenance Plan")
     )
     |> assign_form(params)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.page max_width="max-w-5xl" class="pb-8">
      <.page_header eyebrow="Execution">
        {@page_title}
        <:subtitle>
          Define recurring preventive work with enough context to generate real execution records later.
        </:subtitle>
        <:actions>
          <.button navigate={~p"/execution/maintenance-plans"}>
            Back to maintenance plans
          </.button>
        </:actions>
      </.page_header>

      <.form
        for={@form}
        id="maintenance-plan-form"
        phx-change="validate"
        phx-submit="save"
        class="space-y-6"
      >
        <.form_section
          title="Maintenance Plan Details"
          description="Anchor the schedule to a real asset and define how often it should generate recurring work."
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
                field={@form[:agreement_id]}
                type="select"
                label="Agreement"
                prompt="Select agreement..."
                options={Enum.map(@agreements, &{agreement_label(&1), &1.id})}
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
                options={Enum.map(@managed_systems, &{managed_system_label(&1), &1.id})}
              />
            </div>
            <div class="sm:col-span-3">
              <.input
                field={@form[:asset_id]}
                type="select"
                label="Asset"
                prompt="Select asset..."
                options={Enum.map(@assets, &{asset_label(&1), &1.id})}
              />
            </div>
            <div class="sm:col-span-3">
              <.input field={@form[:name]} label="Name" required />
            </div>
            <div class="sm:col-span-2">
              <.input
                field={@form[:plan_type]}
                type="select"
                label="Plan Type"
                options={plan_type_options()}
              />
            </div>
            <div class="sm:col-span-2">
              <.input
                field={@form[:interval_unit]}
                type="select"
                label="Interval Unit"
                options={interval_unit_options()}
              />
            </div>
            <div class="sm:col-span-2">
              <.input field={@form[:interval_value]} label="Interval Value" type="number" />
            </div>
            <div class="sm:col-span-3">
              <.input field={@form[:next_due_on]} type="date" label="Next Due On" />
            </div>
            <div class="sm:col-span-3">
              <.input
                field={@form[:generation_lead_days]}
                label="Generation Lead Days"
                type="number"
              />
            </div>
            <div class="sm:col-span-3">
              <.input
                field={@form[:priority]}
                type="select"
                label="Priority"
                options={priority_options()}
              />
            </div>
            <div class="sm:col-span-3">
              <.input
                field={@form[:estimated_minutes]}
                label="Estimated Minutes"
                type="number"
              />
            </div>
            <div class="sm:col-span-3">
              <.input
                field={@form[:auto_create_work_orders]}
                type="checkbox"
                label="Auto Create Work Orders"
              />
            </div>
            <div class="sm:col-span-3">
              <.input field={@form[:billable]} type="checkbox" label="Billable" />
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
            cancel_path={~p"/execution/maintenance-plans"}
            submit_label={
              if @maintenance_plan, do: "Update Maintenance Plan", else: "Create Maintenance Plan"
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
      {:ok, maintenance_plan} ->
        {:noreply,
         socket
         |> put_flash(
           :info,
           "Maintenance plan #{if socket.assigns.maintenance_plan, do: "updated", else: "created"}"
         )
         |> push_navigate(to: ~p"/execution/maintenance-plans/#{maintenance_plan}")}

      {:error, form} ->
        {:noreply, assign(socket, form: to_form(form))}
    end
  end

  defp assign_form(
         %{assigns: %{maintenance_plan: maintenance_plan, current_user: actor}} = socket,
         params
       ) do
    form =
      if maintenance_plan do
        AshPhoenix.Form.for_update(
          maintenance_plan,
          :update,
          actor: actor,
          domain: Execution
        )
      else
        AshPhoenix.Form.for_create(
          Execution.MaintenancePlan,
          :create,
          actor: actor,
          domain: Execution,
          params: maintenance_plan_defaults(params)
        )
      end

    assign(socket, :form, to_form(form))
  end

  defp load_maintenance_plan!(id, actor) do
    case Execution.get_maintenance_plan(id, actor: actor) do
      {:ok, maintenance_plan} -> maintenance_plan
      {:error, error} -> raise "failed to load maintenance plan #{id}: #{inspect(error)}"
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

  defp load_assets(actor) do
    case Operations.list_assets(actor: actor, load: [:organization]) do
      {:ok, assets} -> Enum.sort_by(assets, &String.downcase(&1.name || ""))
      {:error, error} -> raise "failed to load assets: #{inspect(error)}"
    end
  end

  defp load_agreements(actor) do
    case Commercial.list_agreements(actor: actor, load: [:organization]) do
      {:ok, agreements} -> Enum.sort_by(agreements, &String.downcase(&1.name || ""))
      {:error, error} -> raise "failed to load agreements: #{inspect(error)}"
    end
  end

  defp maintenance_plan_defaults(params) do
    %{}
    |> maybe_put("organization_id", params["organization_id"])
    |> maybe_put("site_id", params["site_id"])
    |> maybe_put("managed_system_id", params["managed_system_id"])
    |> maybe_put("asset_id", params["asset_id"])
    |> maybe_put("agreement_id", params["agreement_id"])
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, _key, ""), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp agreement_label(agreement) do
    [agreement.name, agreement.organization && agreement.organization.name]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(" · ")
  end

  defp site_label(site) do
    [site.name, site.organization && site.organization.name]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(" · ")
  end

  defp managed_system_label(managed_system) do
    [managed_system.name, managed_system.organization && managed_system.organization.name]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(" · ")
  end

  defp asset_label(asset) do
    [asset.name, asset.organization && asset.organization.name]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(" · ")
  end

  defp plan_type_options do
    [
      {"Inspection", :inspection},
      {"Preventive Maintenance", :preventive_maintenance},
      {"Calibration", :calibration},
      {"Backup Validation", :backup_validation},
      {"Patching", :patching},
      {"Testing", :testing},
      {"Other", :other}
    ]
  end

  defp interval_unit_options do
    [{"Day", :day}, {"Week", :week}, {"Month", :month}, {"Quarter", :quarter}, {"Year", :year}]
  end

  defp priority_options do
    [{"Low", :low}, {"Normal", :normal}, {"High", :high}, {"Critical", :critical}]
  end
end
