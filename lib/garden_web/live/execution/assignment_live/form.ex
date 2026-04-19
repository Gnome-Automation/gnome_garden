defmodule GnomeGardenWeb.Execution.AssignmentLive.Form do
  use GnomeGardenWeb, :live_view

  alias GnomeGarden.Accounts
  alias GnomeGarden.Execution
  alias GnomeGarden.Operations

  @impl true
  def mount(params, _session, socket) do
    assignment = if id = params["id"], do: load_assignment!(id, socket.assigns.current_user)
    selected_project_id = selected_project_id(assignment, params)

    {:ok,
     socket
     |> assign(:assignment, assignment)
     |> assign(:organizations, load_organizations(socket.assigns.current_user))
     |> assign(:projects, load_projects(socket.assigns.current_user))
     |> assign(:work_orders, load_work_orders(socket.assigns.current_user))
     |> assign(:users, load_users(socket.assigns.current_user))
     |> assign(:selected_project_id, selected_project_id)
     |> assign(
       :project_work_items,
       load_project_work_items(socket.assigns.current_user, selected_project_id)
     )
     |> assign(:page_title, if(assignment, do: "Edit Assignment", else: "New Assignment"))
     |> assign_form(params)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.page max_width="max-w-5xl" class="pb-8">
      <.page_header eyebrow="Execution">
        {@page_title}
        <:subtitle>
          Schedule the real owner, time window, and execution context before work starts consuming capacity.
        </:subtitle>
        <:actions>
          <.button navigate={back_path(@selected_project_id, @form[:work_order_id].value)}>
            <.icon name="hero-arrow-left" class="size-4" /> Back
          </.button>
        </:actions>
      </.page_header>

      <.form
        for={@form}
        id="assignment-form"
        phx-change="validate"
        phx-submit="save"
        class="space-y-6"
      >
        <.form_section
          title="Assignment Details"
          description="Tie the assignment to the right organization, execution context, and owner before it hits the calendar."
        >
          <div class="grid grid-cols-1 gap-6 sm:grid-cols-6">
            <div class="sm:col-span-3">
              <.input
                field={@form[:organization_id]}
                type="select"
                label="Organization"
                prompt="Select organization..."
                options={Enum.map(@organizations, &{&1.name, &1.id})}
                required
              />
            </div>
            <div class="sm:col-span-3">
              <.input
                field={@form[:assigned_user_id]}
                type="select"
                label="Assignee"
                prompt="Select user..."
                options={Enum.map(@users, &{&1.email, &1.id})}
                required
              />
            </div>
            <div class="col-span-full">
              <.input field={@form[:title]} label="Title" required />
            </div>
            <div class="sm:col-span-2">
              <.input
                field={@form[:project_id]}
                type="select"
                label="Project"
                prompt="No project"
                options={Enum.map(@projects, &{project_label(&1), &1.id})}
              />
            </div>
            <div class="sm:col-span-2">
              <.input
                field={@form[:work_item_id]}
                type="select"
                label="Work Item"
                prompt="No work item"
                options={Enum.map(@project_work_items, &{work_item_label(&1), &1.id})}
              />
            </div>
            <div class="sm:col-span-2">
              <.input
                field={@form[:work_order_id]}
                type="select"
                label="Work Order"
                prompt="No work order"
                options={Enum.map(@work_orders, &{work_order_label(&1), &1.id})}
              />
            </div>
            <div class="sm:col-span-2">
              <.input
                field={@form[:assignment_type]}
                type="select"
                label="Assignment Type"
                options={assignment_type_options()}
              />
            </div>
            <div class="sm:col-span-2">
              <.input
                field={@form[:location_mode]}
                type="select"
                label="Location Mode"
                options={location_mode_options()}
              />
            </div>
            <div class="sm:col-span-2">
              <.input field={@form[:billable]} type="checkbox" label="Billable" />
            </div>
            <div class="sm:col-span-3">
              <.input
                field={@form[:scheduled_start_at]}
                type="datetime-local"
                label="Scheduled Start"
                required
              />
            </div>
            <div class="sm:col-span-3">
              <.input field={@form[:scheduled_end_at]} type="datetime-local" label="Scheduled End" />
            </div>
            <div class="sm:col-span-2">
              <.input field={@form[:planned_minutes]} type="number" label="Planned Minutes" />
            </div>
            <div class="col-span-full">
              <.input field={@form[:notes]} type="textarea" label="Notes" />
            </div>
          </div>
        </.form_section>

        <.section body_class="px-6 py-5 sm:px-7">
          <.form_actions
            cancel_path={back_path(@selected_project_id, @form[:work_order_id].value)}
            submit_label={if @assignment, do: "Update Assignment", else: "Create Assignment"}
          />
        </.section>
      </.form>
    </.page>
    """
  end

  @impl true
  def handle_event("validate", %{"form" => params}, socket) do
    form = AshPhoenix.Form.validate(socket.assigns.form, params)
    selected_project_id = blank_to_nil(params["project_id"])

    {:noreply,
     socket
     |> assign(:selected_project_id, selected_project_id)
     |> assign(
       :project_work_items,
       load_project_work_items(socket.assigns.current_user, selected_project_id)
     )
     |> assign(:form, to_form(form))}
  end

  @impl true
  def handle_event("save", %{"form" => params}, socket) do
    case AshPhoenix.Form.submit(socket.assigns.form, params: params) do
      {:ok, assignment} ->
        {:noreply,
         socket
         |> put_flash(
           :info,
           "Assignment #{if socket.assigns.assignment, do: "updated", else: "created"}"
         )
         |> push_navigate(to: ~p"/execution/assignments/#{assignment}")}

      {:error, form} ->
        {:noreply, assign(socket, form: to_form(form))}
    end
  end

  defp assign_form(%{assigns: %{assignment: assignment, current_user: actor}} = socket, params) do
    form =
      if assignment do
        AshPhoenix.Form.for_update(assignment, :update, actor: actor, domain: Execution)
      else
        AshPhoenix.Form.for_create(
          Execution.Assignment,
          :create,
          actor: actor,
          domain: Execution,
          params: assignment_defaults(params, actor)
        )
      end

    assign(socket, :form, to_form(form))
  end

  defp load_assignment!(id, actor) do
    case Execution.get_assignment(id, actor: actor) do
      {:ok, assignment} -> assignment
      {:error, error} -> raise "failed to load assignment #{id}: #{inspect(error)}"
    end
  end

  defp load_organizations(actor) do
    case Operations.list_organizations(actor: actor) do
      {:ok, organizations} -> Enum.sort_by(organizations, &String.downcase(&1.name || ""))
      {:error, error} -> raise "failed to load organizations: #{inspect(error)}"
    end
  end

  defp load_projects(actor) do
    case Execution.list_projects(actor: actor) do
      {:ok, projects} -> Enum.sort_by(projects, &String.downcase(&1.name || ""))
      {:error, error} -> raise "failed to load projects: #{inspect(error)}"
    end
  end

  defp load_work_orders(actor) do
    case Execution.list_work_orders(actor: actor) do
      {:ok, work_orders} -> Enum.sort_by(work_orders, &String.downcase(&1.title || ""))
      {:error, error} -> raise "failed to load work orders: #{inspect(error)}"
    end
  end

  defp load_users(actor) do
    if is_nil(actor) do
      []
    else
      case Accounts.list_users(actor: actor) do
        {:ok, users} -> Enum.sort_by(users, &String.downcase(to_string(&1.email || "")))
        {:error, error} -> raise "failed to load users: #{inspect(error)}"
      end
    end
  end

  defp load_project_work_items(_actor, nil), do: []

  defp load_project_work_items(actor, project_id) do
    case Execution.list_work_items_for_project(project_id, actor: actor) do
      {:ok, work_items} ->
        Enum.sort_by(work_items, &{&1.sort_order, String.downcase(&1.title || "")})

      {:error, error} ->
        raise "failed to load work items for project #{project_id}: #{inspect(error)}"
    end
  end

  defp selected_project_id(nil, params), do: blank_to_nil(params["project_id"])
  defp selected_project_id(assignment, _params), do: assignment.project_id

  defp assignment_defaults(params, actor) do
    %{}
    |> maybe_put("organization_id", params["organization_id"])
    |> maybe_put("project_id", params["project_id"])
    |> maybe_put("work_item_id", params["work_item_id"])
    |> maybe_put("work_order_id", params["work_order_id"])
    |> maybe_put("assigned_user_id", params["assigned_user_id"])
    |> Map.put("assigned_by_user_id", actor && actor.id)
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, _key, ""), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp blank_to_nil(nil), do: nil
  defp blank_to_nil(""), do: nil
  defp blank_to_nil(value), do: value

  defp back_path(nil, nil), do: ~p"/execution/assignments"

  defp back_path(project_id, _work_order_id) when is_binary(project_id),
    do: ~p"/execution/projects/#{project_id}"

  defp back_path(_project_id, work_order_id) when is_binary(work_order_id),
    do: ~p"/execution/work-orders/#{work_order_id}"

  defp back_path(_project_id, _work_order_id), do: ~p"/execution/assignments"

  defp project_label(project) do
    [project.name, project.code]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(" · ")
  end

  defp work_item_label(work_item) do
    [work_item.title, work_item.code]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(" · ")
  end

  defp work_order_label(work_order) do
    [work_order.title, work_order.reference_number]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(" · ")
  end

  defp assignment_type_options do
    [
      {"Project Work", :project_work},
      {"Service Dispatch", :service_dispatch},
      {"Onsite Visit", :onsite_visit},
      {"Remote Session", :remote_session},
      {"Review", :review},
      {"Coordination", :coordination},
      {"Other", :other}
    ]
  end

  defp location_mode_options do
    [
      {"Onsite", :onsite},
      {"Remote", :remote},
      {"Hybrid", :hybrid}
    ]
  end
end
