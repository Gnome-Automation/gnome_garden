defmodule GnomeGardenWeb.Operations.TaskLive.Form do
  use GnomeGardenWeb, :live_view

  alias GnomeGarden.Operations

  @initial_param_fields ~w[
    title
    description
    due_at
    priority
    task_type
    origin_domain
    origin_resource
    origin_id
    origin_label
    origin_url
    owner_team_member_id
    organization_id
    person_id
    finding_id
    signal_id
    pursuit_id
    agent_run_id
    project_id
    work_item_id
    work_order_id
    bid_id
    procurement_source_id
  ]

  @impl true
  def mount(params, _session, socket) do
    task = if id = params["id"], do: load_task!(id, socket.assigns.current_user)

    {:ok,
     socket
     |> assign(:task, task)
     |> assign(:initial_params, if(task, do: %{}, else: initial_task_params(params)))
     |> assign(:cancel_path, cancel_path(task, params))
     |> assign(:organizations, load_organizations(socket.assigns.current_user))
     |> assign(:people, load_people(socket.assigns.current_user))
     |> assign(:team_members, load_team_members(socket.assigns.current_user))
     |> assign(:page_title, if(task, do: "Edit Task", else: "New Task"))
     |> assign_form()}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.page max_width="max-w-5xl" class="pb-8">
      <.page_header eyebrow="Operations">
        {@page_title}
        <:subtitle>
          Capture operator work from any part of the system without tying it to a single domain.
        </:subtitle>
        <:actions>
          <.button navigate={~p"/operations/tasks"}>
            Back to tasks
          </.button>
        </:actions>
      </.page_header>

      <.form for={@form} id="task-form" phx-change="validate" phx-submit="save" class="space-y-6">
        <.form_section title="Task Details">
          <div class="grid grid-cols-1 gap-6 sm:grid-cols-6">
            <div class="col-span-full">
              <.input field={@form[:title]} label="Title" required />
            </div>
            <div class="col-span-full">
              <.input field={@form[:description]} type="textarea" label="Description" />
            </div>
            <div class="sm:col-span-2">
              <.input
                field={@form[:task_type]}
                type="select"
                label="Type"
                options={task_type_options()}
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
              <.input field={@form[:due_at]} type="datetime-local" label="Due At" />
            </div>
          </div>
        </.form_section>

        <.form_section
          title="Origin"
          description="Use these fields to point the task back to the record or workflow that created it."
        >
          <div class="grid grid-cols-1 gap-6 sm:grid-cols-6">
            <div class="sm:col-span-2">
              <.input
                field={@form[:origin_domain]}
                type="select"
                label="Origin Domain"
                options={origin_domain_options()}
              />
            </div>
            <div class="sm:col-span-2">
              <.input field={@form[:origin_resource]} label="Origin Resource" />
            </div>
            <div class="sm:col-span-2">
              <.input field={@form[:origin_id]} label="Origin ID" />
            </div>
            <div class="sm:col-span-3">
              <.input field={@form[:origin_label]} label="Origin Label" />
            </div>
            <div class="sm:col-span-3">
              <.input field={@form[:origin_url]} label="Origin URL" />
            </div>
          </div>
        </.form_section>

        <.form_section title="Ownership And Links">
          <div class="grid grid-cols-1 gap-6 sm:grid-cols-6">
            <div class="sm:col-span-2">
              <.input
                field={@form[:owner_team_member_id]}
                type="select"
                label="Owner"
                prompt="Unassigned"
                options={Enum.map(@team_members, &{team_member_label(&1), &1.id})}
              />
            </div>
            <div class="sm:col-span-2">
              <.input
                field={@form[:organization_id]}
                type="select"
                label="Organization"
                prompt="None"
                options={Enum.map(@organizations, &{&1.name, &1.id})}
              />
            </div>
            <div class="sm:col-span-2">
              <.input
                field={@form[:person_id]}
                type="select"
                label="Person"
                prompt="None"
                options={Enum.map(@people, &{person_label(&1), &1.id})}
              />
            </div>
          </div>
        </.form_section>

        <.section body_class="px-6 py-5 sm:px-7">
          <.form_actions
            cancel_path={@cancel_path}
            submit_label={if @task, do: "Update Task", else: "Create Task"}
          />
        </.section>

        <.input field={@form[:finding_id]} type="hidden" />
        <.input field={@form[:signal_id]} type="hidden" />
        <.input field={@form[:pursuit_id]} type="hidden" />
        <.input field={@form[:agent_run_id]} type="hidden" />
        <.input field={@form[:project_id]} type="hidden" />
        <.input field={@form[:work_item_id]} type="hidden" />
        <.input field={@form[:work_order_id]} type="hidden" />
        <.input field={@form[:bid_id]} type="hidden" />
        <.input field={@form[:procurement_source_id]} type="hidden" />
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
      {:ok, task} ->
        {:noreply,
         socket
         |> put_flash(:info, "Task #{if socket.assigns.task, do: "updated", else: "created"}")
         |> push_navigate(to: ~p"/operations/tasks/#{task}")}

      {:error, form} ->
        {:noreply, assign(socket, form: to_form(form))}
    end
  end

  defp assign_form(%{assigns: %{task: task, current_user: actor}} = socket) do
    form =
      if task do
        AshPhoenix.Form.for_update(task, :update, actor: actor, domain: Operations)
      else
        AshPhoenix.Form.for_create(Operations.Task, :create,
          actor: actor,
          domain: Operations,
          params: socket.assigns.initial_params
        )
      end

    assign(socket, :form, to_form(form))
  end

  defp initial_task_params(params) do
    params
    |> Map.take(@initial_param_fields)
    |> Enum.reject(fn {_key, value} -> is_nil(value) or value == "" end)
    |> Map.new()
  end

  defp cancel_path(task, _params) when not is_nil(task), do: ~p"/operations/tasks/#{task}"

  defp cancel_path(_task, %{"return_to" => return_to}) do
    if local_path?(return_to), do: return_to, else: ~p"/operations/tasks"
  end

  defp cancel_path(_task, _params), do: ~p"/operations/tasks"

  defp local_path?("/" <> rest), do: not String.starts_with?(rest, "/")
  defp local_path?(_path), do: false

  defp load_task!(id, actor) do
    case Operations.get_task(id, actor: actor) do
      {:ok, task} -> task
      {:error, error} -> raise "failed to load task #{id}: #{inspect(error)}"
    end
  end

  defp load_organizations(actor) do
    case Operations.list_organizations(actor: actor) do
      {:ok, organizations} -> organizations
      {:error, _error} -> []
    end
  end

  defp load_people(actor) do
    case Operations.list_people(actor: actor, load: [:full_name]) do
      {:ok, people} -> people
      {:error, _error} -> []
    end
  end

  defp load_team_members(actor) do
    case Operations.list_active_team_members(actor: actor) do
      {:ok, team_members} -> team_members
      {:error, _error} -> []
    end
  end

  defp person_label(%{full_name: full_name}) when is_binary(full_name), do: full_name

  defp person_label(person),
    do: [person.first_name, person.last_name] |> Enum.reject(&is_nil/1) |> Enum.join(" ")

  defp team_member_label(%{display_name: display_name}) when is_binary(display_name),
    do: display_name

  defp team_member_label(team_member), do: "Team member #{team_member.id}"

  defp task_type_options do
    [
      {"Review", :review},
      {"Research", :research},
      {"Call", :call},
      {"Email", :email},
      {"Evidence", :evidence},
      {"Proposal", :proposal},
      {"Finance", :finance},
      {"Source Cleanup", :source_cleanup},
      {"Agent Followup", :agent_followup},
      {"Other", :other}
    ]
  end

  defp priority_options do
    [{"Low", :low}, {"Normal", :normal}, {"High", :high}, {"Urgent", :urgent}]
  end

  defp origin_domain_options do
    [
      {"Manual", :manual},
      {"Acquisition", :acquisition},
      {"Commercial", :commercial},
      {"Procurement", :procurement},
      {"Agents", :agents},
      {"Finance", :finance},
      {"Execution", :execution},
      {"Operations", :operations}
    ]
  end
end
