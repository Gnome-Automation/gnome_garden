defmodule GnomeGardenWeb.Commercial.ChangeOrderLive.Form do
  use GnomeGardenWeb, :live_view

  alias GnomeGarden.Commercial
  alias GnomeGarden.Execution
  alias GnomeGarden.Operations

  @impl true
  def mount(params, _session, socket) do
    change_order =
      if id = params["id"] do
        load_change_order!(id, socket.assigns.current_user)
      end

    agreement =
      if is_nil(change_order) and params["agreement_id"] do
        load_agreement!(params["agreement_id"], socket.assigns.current_user)
      end

    project =
      if is_nil(change_order) and params["project_id"] do
        load_project!(params["project_id"], socket.assigns.current_user)
      end

    {:ok,
     socket
     |> assign(:change_order, change_order)
     |> assign(:agreement, agreement)
     |> assign(:project, project)
     |> assign(:organizations, load_organizations(socket.assigns.current_user))
     |> assign(:agreements, load_agreements(socket.assigns.current_user))
     |> assign(:projects, load_projects(socket.assigns.current_user))
     |> assign(:page_title, page_title(change_order, agreement, project))
     |> assign_form()}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.page max_width="max-w-5xl" class="pb-8">
      <.page_header eyebrow="Commercial">
        {@page_title}
        <:subtitle>
          Capture post-award commercial deltas without mutating the original contract history.
        </:subtitle>
        <:actions>
          <.button navigate={~p"/commercial/change-orders"}>
            <.icon name="hero-arrow-left" class="size-4" /> Back to change orders
          </.button>
        </:actions>
      </.page_header>

      <.section
        :if={@agreement || @project}
        title="Source Context"
        description="This change order is being anchored to existing awarded work."
      >
        <div class="grid gap-4 lg:grid-cols-2">
          <div
            :if={@agreement}
            class="rounded-2xl border border-zinc-200 bg-zinc-50/70 px-4 py-4 dark:border-white/10 dark:bg-white/[0.03]"
          >
            <p class="font-medium text-zinc-900 dark:text-white">{@agreement.name}</p>
            <p class="text-sm text-zinc-500 dark:text-zinc-400">
              Agreement · {@agreement.reference_number || "No reference"}
            </p>
          </div>
          <div
            :if={@project}
            class="rounded-2xl border border-zinc-200 bg-zinc-50/70 px-4 py-4 dark:border-white/10 dark:bg-white/[0.03]"
          >
            <p class="font-medium text-zinc-900 dark:text-white">{@project.name}</p>
            <p class="text-sm text-zinc-500 dark:text-zinc-400">
              Project · {@project.code || "No code"}
            </p>
          </div>
        </div>
      </.section>

      <.form
        for={@form}
        id="change-order-form"
        phx-change="validate"
        phx-submit="save"
        class="space-y-6"
      >
        <.form_section
          title="Change Order Details"
          description="Define the amendment identity, contract link, change type, and schedule impact."
        >
          <div class="grid grid-cols-1 gap-6 sm:grid-cols-6">
            <div class="sm:col-span-3">
              <.input field={@form[:change_order_number]} label="Change Order Number" required />
            </div>
            <div class="sm:col-span-3">
              <.input field={@form[:title]} label="Title" required />
            </div>
            <div class="sm:col-span-3">
              <.input
                field={@form[:agreement_id]}
                type="select"
                label="Agreement"
                prompt="Select agreement..."
                options={Enum.map(@agreements, &{&1.name, &1.id})}
              />
            </div>
            <div class="sm:col-span-3">
              <.input
                field={@form[:project_id]}
                type="select"
                label="Project"
                prompt="Select project..."
                options={Enum.map(@projects, &{&1.name, &1.id})}
              />
            </div>
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
                field={@form[:change_type]}
                type="select"
                label="Change Type"
                options={change_type_options()}
              />
            </div>
            <div class="sm:col-span-3">
              <.input
                field={@form[:pricing_model]}
                type="select"
                label="Pricing Model"
                options={pricing_model_options()}
              />
            </div>
            <div class="sm:col-span-3">
              <.input field={@form[:requested_on]} type="date" label="Requested On" />
            </div>
            <div class="sm:col-span-3">
              <.input field={@form[:effective_on]} type="date" label="Effective On" />
            </div>
            <div class="sm:col-span-3">
              <.input
                field={@form[:schedule_impact_days]}
                label="Schedule Impact Days"
                type="number"
              />
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
            cancel_path={~p"/commercial/change-orders"}
            submit_label={if @change_order, do: "Update Change Order", else: "Create Change Order"}
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
      {:ok, change_order} ->
        {:noreply,
         socket
         |> put_flash(
           :info,
           "Change order #{if socket.assigns.change_order, do: "updated", else: "created"}"
         )
         |> push_navigate(to: ~p"/commercial/change-orders/#{change_order}")}

      {:error, form} ->
        {:noreply, assign(socket, form: to_form(form))}
    end
  end

  defp assign_form(
         %{
           assigns: %{
             change_order: change_order,
             agreement: agreement,
             project: project,
             current_user: actor
           }
         } = socket
       ) do
    form =
      cond do
        change_order ->
          AshPhoenix.Form.for_update(change_order, :update, actor: actor, domain: Commercial)

        true ->
          AshPhoenix.Form.for_create(
            Commercial.ChangeOrder,
            :create,
            actor: actor,
            domain: Commercial,
            params: change_order_defaults(agreement, project)
          )
      end

    assign(socket, :form, to_form(form))
  end

  defp load_change_order!(id, actor) do
    case Commercial.get_change_order(id, actor: actor) do
      {:ok, change_order} -> change_order
      {:error, error} -> raise "failed to load change order #{id}: #{inspect(error)}"
    end
  end

  defp load_agreement!(id, actor) do
    case Commercial.get_agreement(id, actor: actor) do
      {:ok, agreement} -> agreement
      {:error, error} -> raise "failed to load agreement #{id}: #{inspect(error)}"
    end
  end

  defp load_project!(id, actor) do
    case Execution.get_project(id, actor: actor) do
      {:ok, project} -> project
      {:error, error} -> raise "failed to load project #{id}: #{inspect(error)}"
    end
  end

  defp load_organizations(actor) do
    case Operations.list_organizations(actor: actor) do
      {:ok, organizations} -> Enum.sort_by(organizations, &String.downcase(&1.name || ""))
      {:error, error} -> raise "failed to load organizations: #{inspect(error)}"
    end
  end

  defp load_agreements(actor) do
    case Commercial.list_agreements(actor: actor) do
      {:ok, agreements} -> Enum.sort_by(agreements, &String.downcase(&1.name || ""))
      {:error, error} -> raise "failed to load agreements: #{inspect(error)}"
    end
  end

  defp load_projects(actor) do
    case Execution.list_projects(actor: actor) do
      {:ok, projects} -> Enum.sort_by(projects, &String.downcase(&1.name || ""))
      {:error, error} -> raise "failed to load projects: #{inspect(error)}"
    end
  end

  defp change_order_defaults(agreement, project) do
    base = %{}

    base =
      if agreement do
        base
        |> Map.put("agreement_id", agreement.id)
        |> Map.put("organization_id", agreement.organization_id)
      else
        base
      end

    if project do
      base
      |> Map.put("project_id", project.id)
      |> Map.put_new("organization_id", project.organization_id)
    else
      base
    end
  end

  defp page_title(change_order, _agreement, _project) when not is_nil(change_order),
    do: "Edit Change Order"

  defp page_title(nil, agreement, _project) when not is_nil(agreement),
    do: "New Change Order For Agreement"

  defp page_title(nil, nil, project) when not is_nil(project),
    do: "New Change Order For Project"

  defp page_title(nil, nil, nil), do: "New Change Order"

  defp change_type_options do
    [
      {"Scope Addition", :scope_addition},
      {"Scope Reduction", :scope_reduction},
      {"Substitution", :substitution},
      {"Schedule Change", :schedule_change},
      {"Rate Change", :rate_change},
      {"Allowance Draw", :allowance_draw},
      {"Other", :other}
    ]
  end

  defp pricing_model_options do
    [
      {"Fixed Fee", :fixed_fee},
      {"Time & Materials", :time_and_materials},
      {"Retainer", :retainer},
      {"Milestone", :milestone},
      {"Unit", :unit},
      {"Mixed", :mixed}
    ]
  end
end
