defmodule GnomeGardenWeb.Execution.WorkOrderLive.Form do
  use GnomeGardenWeb, :live_view

  alias GnomeGarden.Commercial
  alias GnomeGarden.Execution
  alias GnomeGarden.Operations

  @impl true
  def mount(params, _session, socket) do
    work_order = if id = params["id"], do: load_work_order!(id, socket.assigns.current_user)

    service_ticket =
      if is_nil(work_order),
        do: maybe_load_service_ticket(params["service_ticket_id"], socket.assigns.current_user)

    {:ok,
     socket
     |> assign(:work_order, work_order)
     |> assign(:service_ticket, service_ticket)
     |> assign(:organizations, load_organizations(socket.assigns.current_user))
     |> assign(:sites, load_sites(socket.assigns.current_user))
     |> assign(:managed_systems, load_managed_systems(socket.assigns.current_user))
     |> assign(:assets, load_assets(socket.assigns.current_user))
     |> assign(:service_tickets, load_service_tickets(socket.assigns.current_user))
     |> assign(:maintenance_plans, load_maintenance_plans(socket.assigns.current_user))
     |> assign(:agreements, load_agreements(socket.assigns.current_user))
     |> assign(:projects, load_projects(socket.assigns.current_user))
     |> assign(:page_title, if(work_order, do: "Edit Work Order", else: "New Work Order"))
     |> assign_form(params)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.page max_width="max-w-5xl" class="pb-8">
      <.page_header eyebrow="Execution">
        {@page_title}
        <:subtitle>
          Schedule execution against the right customer, asset, ticket, and commercial context before work starts.
        </:subtitle>
        <:actions>
          <.button navigate={~p"/execution/work-orders"}>
            <.icon name="hero-arrow-left" class="size-4" /> Back to work orders
          </.button>
        </:actions>
      </.page_header>

      <.section
        :if={@service_ticket}
        title="Source Service Ticket"
        description="This work order is being created from an existing service ticket."
      >
        <div class="rounded-2xl border border-zinc-200 bg-zinc-50/70 px-4 py-4 dark:border-white/10 dark:bg-white/[0.03]">
          <p class="font-medium text-zinc-900 dark:text-white">{@service_ticket.title}</p>
          <p class="text-sm text-zinc-500 dark:text-zinc-400">
            {@service_ticket.ticket_number || "No ticket number"} / {(@service_ticket.organization &&
                                                                        @service_ticket.organization.name) ||
              "No organization"}
          </p>
        </div>
      </.section>

      <.form
        for={@form}
        id="work-order-form"
        phx-change="validate"
        phx-submit="save"
        class="space-y-6"
      >
        <.form_section
          title="Work Order Details"
          description="Tie execution to the right customer, asset, and upstream service or commercial record."
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
              <.input field={@form[:reference_number]} label="Reference Number" />
            </div>
            <div class="col-span-full">
              <.input field={@form[:title]} label="Title" required />
            </div>
            <div class="sm:col-span-3">
              <.input
                field={@form[:service_ticket_id]}
                type="select"
                label="Service Ticket"
                prompt="Select ticket..."
                options={Enum.map(@service_tickets, &{service_ticket_label(&1), &1.id})}
              />
            </div>
            <div class="sm:col-span-3">
              <.input
                field={@form[:maintenance_plan_id]}
                type="select"
                label="Maintenance Plan"
                prompt="Select plan..."
                options={Enum.map(@maintenance_plans, &{maintenance_plan_label(&1), &1.id})}
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
                field={@form[:asset_id]}
                type="select"
                label="Asset"
                prompt="Select asset..."
                options={Enum.map(@assets, &{asset_label(&1), &1.id})}
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
                field={@form[:project_id]}
                type="select"
                label="Project"
                prompt="Select project..."
                options={Enum.map(@projects, &{project_label(&1), &1.id})}
              />
            </div>
            <div class="sm:col-span-2">
              <.input
                field={@form[:work_type]}
                type="select"
                label="Work Type"
                options={work_type_options()}
              />
            </div>
            <div class="sm:col-span-2">
              <.input
                field={@form[:priority]}
                type="select"
                label="Priority"
                options={priority_options()}
              />
            </div>
            <div class="sm:col-span-2">
              <.input field={@form[:billable]} type="checkbox" label="Billable" />
            </div>
            <div class="sm:col-span-3">
              <.input
                field={@form[:estimated_minutes]}
                label="Estimated Minutes"
                type="number"
              />
            </div>
            <div class="sm:col-span-3">
              <.input field={@form[:due_on]} type="date" label="Due On" />
            </div>
            <div class="sm:col-span-3">
              <.input
                field={@form[:scheduled_start_at]}
                type="datetime-local"
                label="Scheduled Start"
              />
            </div>
            <div class="sm:col-span-3">
              <.input
                field={@form[:scheduled_end_at]}
                type="datetime-local"
                label="Scheduled End"
              />
            </div>
            <div class="col-span-full">
              <.input field={@form[:description]} type="textarea" label="Description" />
            </div>
            <div class="col-span-full">
              <.input field={@form[:resolution_notes]} type="textarea" label="Resolution Notes" />
            </div>
          </div>
        </.form_section>

        <.section body_class="px-6 py-5 sm:px-7">
          <.form_actions
            cancel_path={~p"/execution/work-orders"}
            submit_label={if @work_order, do: "Update Work Order", else: "Create Work Order"}
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
      {:ok, work_order} ->
        {:noreply,
         socket
         |> put_flash(
           :info,
           "Work order #{if socket.assigns.work_order, do: "updated", else: "created"}"
         )
         |> push_navigate(to: ~p"/execution/work-orders/#{work_order}")}

      {:error, form} ->
        {:noreply, assign(socket, form: to_form(form))}
    end
  end

  defp assign_form(
         %{
           assigns: %{work_order: work_order, service_ticket: service_ticket, current_user: actor}
         } = socket,
         params
       ) do
    form =
      if work_order do
        AshPhoenix.Form.for_update(work_order, :update, actor: actor, domain: Execution)
      else
        AshPhoenix.Form.for_create(
          Execution.WorkOrder,
          :create,
          actor: actor,
          domain: Execution,
          params: work_order_defaults(params, service_ticket)
        )
      end

    assign(socket, :form, to_form(form))
  end

  defp load_work_order!(id, actor) do
    case Execution.get_work_order(id, actor: actor) do
      {:ok, work_order} -> work_order
      {:error, error} -> raise "failed to load work order #{id}: #{inspect(error)}"
    end
  end

  defp maybe_load_service_ticket(nil, _actor), do: nil
  defp maybe_load_service_ticket("", _actor), do: nil

  defp maybe_load_service_ticket(id, actor) do
    case Execution.get_service_ticket(id, actor: actor, load: [:organization]) do
      {:ok, service_ticket} -> service_ticket
      {:error, error} -> raise "failed to load service ticket #{id}: #{inspect(error)}"
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

  defp load_service_tickets(actor) do
    case Execution.list_service_tickets(actor: actor, load: [:organization]) do
      {:ok, service_tickets} -> Enum.sort_by(service_tickets, &String.downcase(&1.title || ""))
      {:error, error} -> raise "failed to load service tickets: #{inspect(error)}"
    end
  end

  defp load_maintenance_plans(actor) do
    case Execution.list_maintenance_plans(actor: actor, load: [:asset]) do
      {:ok, maintenance_plans} ->
        Enum.sort_by(maintenance_plans, &String.downcase(&1.name || ""))

      {:error, error} ->
        raise "failed to load maintenance plans: #{inspect(error)}"
    end
  end

  defp load_agreements(actor) do
    case Commercial.list_agreements(actor: actor, load: [:organization]) do
      {:ok, agreements} -> Enum.sort_by(agreements, &String.downcase(&1.name || ""))
      {:error, error} -> raise "failed to load agreements: #{inspect(error)}"
    end
  end

  defp load_projects(actor) do
    case Execution.list_projects(actor: actor, load: [:organization]) do
      {:ok, projects} -> Enum.sort_by(projects, &String.downcase(&1.name || ""))
      {:error, error} -> raise "failed to load projects: #{inspect(error)}"
    end
  end

  defp work_order_defaults(params, nil) do
    %{}
    |> maybe_put("organization_id", params["organization_id"])
    |> maybe_put("site_id", params["site_id"])
    |> maybe_put("managed_system_id", params["managed_system_id"])
    |> maybe_put("asset_id", params["asset_id"])
    |> maybe_put("service_ticket_id", params["service_ticket_id"])
    |> maybe_put("agreement_id", params["agreement_id"])
    |> maybe_put("project_id", params["project_id"])
  end

  defp work_order_defaults(params, service_ticket) do
    work_order_defaults(params, nil)
    |> Map.put_new("service_ticket_id", service_ticket.id)
    |> Map.put_new("organization_id", service_ticket.organization_id)
    |> maybe_put("site_id", service_ticket.site_id)
    |> maybe_put("managed_system_id", service_ticket.managed_system_id)
    |> maybe_put("asset_id", service_ticket.asset_id)
    |> maybe_put("agreement_id", service_ticket.agreement_id)
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

  defp service_ticket_label(service_ticket) do
    [service_ticket.title, service_ticket.organization && service_ticket.organization.name]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(" · ")
  end

  defp maintenance_plan_label(maintenance_plan) do
    [maintenance_plan.name, maintenance_plan.asset && maintenance_plan.asset.name]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(" · ")
  end

  defp agreement_label(agreement) do
    [agreement.name, agreement.organization && agreement.organization.name]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(" · ")
  end

  defp project_label(project) do
    [project.name, project.organization && project.organization.name]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(" · ")
  end

  defp work_type_options do
    [
      {"Service Call", :service_call},
      {"Inspection", :inspection},
      {"Preventive Maintenance", :preventive_maintenance},
      {"Commissioning", :commissioning},
      {"Support", :support},
      {"Warranty", :warranty},
      {"Other", :other}
    ]
  end

  defp priority_options do
    [{"Low", :low}, {"Normal", :normal}, {"High", :high}, {"Critical", :critical}]
  end
end
