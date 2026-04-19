defmodule GnomeGardenWeb.Execution.ProjectLive.Form do
  use GnomeGardenWeb, :live_view

  import GnomeGardenWeb.Execution.Helpers

  alias GnomeGarden.Commercial
  alias GnomeGarden.Execution
  alias GnomeGarden.Operations

  @impl true
  def mount(params, _session, socket) do
    project = if id = params["id"], do: load_project!(id, socket.assigns.current_user)

    agreement =
      if is_nil(project) and params["agreement_id"] do
        load_agreement!(params["agreement_id"], socket.assigns.current_user)
      end

    {:ok,
     socket
     |> assign(:project, project)
     |> assign(:agreement, agreement)
     |> assign(:organizations, load_organizations(socket.assigns.current_user))
     |> assign(:agreements, load_agreements(socket.assigns.current_user))
     |> assign(:page_title, page_title(project, agreement))
     |> assign_form()}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.page max_width="max-w-5xl" class="pb-8">
      <.page_header eyebrow="Execution">
        {@page_title}
        <:subtitle>
          Keep projects anchored to the right commercial agreement and delivery mode before execution starts.
        </:subtitle>
        <:actions>
          <.button navigate={~p"/execution/projects"}>
            <.icon name="hero-arrow-left" class="size-4" /> Back to projects
          </.button>
        </:actions>
      </.page_header>

      <.section
        :if={@agreement}
        title="Source Agreement"
        description="This project is being created from an active agreement. Confirm the scope, schedule, and budget before work begins."
      >
        <div class="flex items-center justify-between rounded-2xl border border-zinc-200 bg-zinc-50/70 px-4 py-4 dark:border-white/10 dark:bg-white/[0.03]">
          <div class="space-y-1">
            <p class="font-medium text-zinc-900 dark:text-white">{@agreement.name}</p>
            <p class="text-sm text-zinc-500 dark:text-zinc-400">
              {@agreement.reference_number || "No reference"} / {(@agreement.organization &&
                                                                    @agreement.organization.name) ||
                "No organization linked"}
            </p>
          </div>
          <.status_badge status={@agreement.status_variant}>
            {format_atom(@agreement.status)}
          </.status_badge>
        </div>
      </.section>

      <.form for={@form} id="project-form" phx-change="validate" phx-submit="save" class="space-y-6">
        <.form_section
          title="Project Details"
          description="Define the delivery container that work items, assignments, service work, and billing context will attach to."
        >
          <div class="grid grid-cols-1 gap-6 sm:grid-cols-6">
            <div class="sm:col-span-3">
              <.input field={@form[:code]} label="Project Code" />
            </div>
            <div class="sm:col-span-3">
              <.input field={@form[:name]} label="Name" required />
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
                :if={is_nil(@agreement)}
                field={@form[:agreement_id]}
                type="select"
                label="Agreement"
                prompt="Select agreement..."
                options={Enum.map(@agreements, &{&1.name, &1.id})}
              />
            </div>
            <div :if={!is_nil(@agreement)} class="sm:col-span-3">
              <div class="space-y-2">
                <label class="block text-sm/6 font-medium text-gray-900 dark:text-white">
                  Agreement
                </label>
                <div class="rounded-2xl border border-zinc-200 bg-zinc-50/70 px-4 py-3 text-sm text-zinc-600 dark:border-white/10 dark:bg-white/[0.03] dark:text-zinc-300">
                  {@agreement.name}
                </div>
              </div>
            </div>
            <div class="sm:col-span-3">
              <.input
                field={@form[:project_type]}
                type="select"
                label="Project Type"
                options={project_type_options()}
              />
            </div>
            <div class="sm:col-span-3">
              <.input
                field={@form[:delivery_mode]}
                type="select"
                label="Delivery Mode"
                options={delivery_mode_options()}
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
              <.input field={@form[:start_on]} type="date" label="Start On" />
            </div>
            <div class="sm:col-span-3">
              <.input field={@form[:target_end_on]} type="date" label="Target End" />
            </div>
            <div class="sm:col-span-3">
              <.input field={@form[:budget_hours]} label="Budget Hours" type="number" step="0.01" />
            </div>
            <div class="sm:col-span-3">
              <.input field={@form[:budget_amount]} label="Budget Amount" type="number" step="0.01" />
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
            cancel_path={~p"/execution/projects"}
            submit_label={if @project, do: "Update Project", else: "Create Project"}
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
      {:ok, project} ->
        {:noreply,
         socket
         |> put_flash(
           :info,
           "Project #{if socket.assigns.project, do: "updated", else: "created"}"
         )
         |> push_navigate(to: ~p"/execution/projects/#{project}")}

      {:error, form} ->
        {:noreply, assign(socket, form: to_form(form))}
    end
  end

  defp assign_form(
         %{assigns: %{project: project, agreement: agreement, current_user: actor}} = socket
       ) do
    form =
      cond do
        project ->
          AshPhoenix.Form.for_update(project, :update, actor: actor, domain: Execution)

        agreement ->
          AshPhoenix.Form.for_create(
            Execution.Project,
            :create_from_agreement,
            actor: actor,
            domain: Execution,
            params: project_defaults_from_agreement(agreement),
            prepare_source: fn changeset ->
              Ash.Changeset.set_argument(changeset, :agreement_id, agreement.id)
            end
          )

        true ->
          AshPhoenix.Form.for_create(Execution.Project, :create, actor: actor, domain: Execution)
      end

    assign(socket, :form, to_form(form))
  end

  defp load_project!(id, actor) do
    case Execution.get_project(id, actor: actor) do
      {:ok, project} -> project
      {:error, error} -> raise "failed to load project #{id}: #{inspect(error)}"
    end
  end

  defp load_agreement!(id, actor) do
    case Commercial.get_agreement(id, actor: actor, load: [:organization, :status_variant]) do
      {:ok, agreement} -> agreement
      {:error, error} -> raise "failed to load agreement #{id}: #{inspect(error)}"
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

  defp project_defaults_from_agreement(agreement) do
    %{
      "agreement_id" => agreement.id,
      "organization_id" => agreement.organization_id,
      "name" => agreement.name,
      "start_on" => agreement.start_on,
      "target_end_on" => agreement.end_on,
      "budget_amount" => agreement.contract_value,
      "notes" => agreement.notes
    }
  end

  defp page_title(project, _agreement) when not is_nil(project), do: "Edit Project"
  defp page_title(nil, agreement) when not is_nil(agreement), do: "New Project From Agreement"
  defp page_title(nil, nil), do: "New Project"

  defp project_type_options do
    [
      {"Implementation", :implementation},
      {"Upgrade", :upgrade},
      {"Integration", :integration},
      {"Commissioning", :commissioning},
      {"Software Delivery", :software_delivery},
      {"Internal", :internal},
      {"Other", :other}
    ]
  end

  defp delivery_mode_options do
    [
      {"Physical", :physical},
      {"Digital", :digital},
      {"Hybrid", :hybrid}
    ]
  end

  defp priority_options do
    [
      {"Low", :low},
      {"Normal", :normal},
      {"High", :high},
      {"Critical", :critical}
    ]
  end
end
