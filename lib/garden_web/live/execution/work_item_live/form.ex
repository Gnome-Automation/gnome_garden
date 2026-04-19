defmodule GnomeGardenWeb.Execution.WorkItemLive.Form do
  use GnomeGardenWeb, :live_view

  alias GnomeGarden.Accounts
  alias GnomeGarden.Execution

  @impl true
  def mount(params, _session, socket) do
    work_item = if id = params["id"], do: load_work_item!(id, socket.assigns.current_user)
    selected_project_id = selected_project_id(work_item, params)

    {:ok,
     socket
     |> assign(:work_item, work_item)
     |> assign(:projects, load_projects(socket.assigns.current_user))
     |> assign(:users, load_users(socket.assigns.current_user))
     |> assign(:selected_project_id, selected_project_id)
     |> assign(
       :parent_work_items,
       load_parent_work_items(socket.assigns.current_user, selected_project_id, work_item)
     )
     |> assign(:page_title, if(work_item, do: "Edit Work Item", else: "New Work Item"))
     |> assign_form(params)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.page max_width="max-w-5xl" class="pb-8">
      <.page_header eyebrow="Execution">
        {@page_title}
        <:subtitle>
          Define the planning unit that delivery, scheduling, and operational finance will attach to.
        </:subtitle>
        <:actions>
          <.button navigate={back_path(@selected_project_id)}>
            <.icon name="hero-arrow-left" class="size-4" /> Back
          </.button>
        </:actions>
      </.page_header>

      <.form for={@form} id="work-item-form" phx-change="validate" phx-submit="save" class="space-y-6">
        <.form_section
          title="Work Item Details"
          description="Anchor the work item to the right project and owner before sequencing the actual execution work."
        >
          <div class="grid grid-cols-1 gap-6 sm:grid-cols-6">
            <div class="sm:col-span-3">
              <.input
                field={@form[:project_id]}
                type="select"
                label="Project"
                prompt="Select project..."
                options={Enum.map(@projects, &{project_label(&1), &1.id})}
                required
              />
            </div>
            <div class="sm:col-span-3">
              <.input
                field={@form[:parent_work_item_id]}
                type="select"
                label="Parent Work Item"
                prompt="No parent"
                options={Enum.map(@parent_work_items, &{parent_work_item_label(&1), &1.id})}
              />
            </div>
            <div class="sm:col-span-2">
              <.input field={@form[:code]} label="Code" />
            </div>
            <div class="sm:col-span-4">
              <.input field={@form[:title]} label="Title" required />
            </div>
            <div class="sm:col-span-2">
              <.input
                field={@form[:kind]}
                type="select"
                label="Kind"
                options={kind_options()}
              />
            </div>
            <div class="sm:col-span-2">
              <.input
                field={@form[:discipline]}
                type="select"
                label="Discipline"
                options={discipline_options()}
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
            <div class="sm:col-span-3">
              <.input
                field={@form[:owner_user_id]}
                type="select"
                label="Owner"
                prompt="Unassigned"
                options={Enum.map(@users, &{&1.email, &1.id})}
              />
            </div>
            <div class="sm:col-span-1">
              <.input field={@form[:sort_order]} label="Sort Order" type="number" />
            </div>
            <div class="sm:col-span-2">
              <.input field={@form[:estimate_minutes]} label="Estimate Minutes" type="number" />
            </div>
            <div class="sm:col-span-3">
              <.input field={@form[:due_on]} type="date" label="Due On" />
            </div>
            <div class="col-span-full">
              <.input field={@form[:description]} type="textarea" label="Description" />
            </div>
          </div>
        </.form_section>

        <.section body_class="px-6 py-5 sm:px-7">
          <.form_actions
            cancel_path={back_path(@selected_project_id)}
            submit_label={if @work_item, do: "Update Work Item", else: "Create Work Item"}
          />
        </.section>
      </.form>
    </.page>
    """
  end

  @impl true
  def handle_event("validate", %{"form" => params}, socket) do
    form = AshPhoenix.Form.validate(socket.assigns.form, params)
    selected_project_id = params["project_id"] || socket.assigns.selected_project_id

    {:noreply,
     socket
     |> assign(:selected_project_id, blank_to_nil(selected_project_id))
     |> assign(
       :parent_work_items,
       load_parent_work_items(
         socket.assigns.current_user,
         blank_to_nil(selected_project_id),
         socket.assigns.work_item
       )
     )
     |> assign(:form, to_form(form))}
  end

  @impl true
  def handle_event("save", %{"form" => params}, socket) do
    case AshPhoenix.Form.submit(socket.assigns.form, params: params) do
      {:ok, work_item} ->
        {:noreply,
         socket
         |> put_flash(
           :info,
           "Work item #{if socket.assigns.work_item, do: "updated", else: "created"}"
         )
         |> push_navigate(to: ~p"/execution/work-items/#{work_item}")}

      {:error, form} ->
        {:noreply, assign(socket, form: to_form(form))}
    end
  end

  defp assign_form(%{assigns: %{work_item: work_item, current_user: actor}} = socket, params) do
    form =
      if work_item do
        AshPhoenix.Form.for_update(work_item, :update, actor: actor, domain: Execution)
      else
        AshPhoenix.Form.for_create(
          Execution.WorkItem,
          :create,
          actor: actor,
          domain: Execution,
          params: work_item_defaults(params)
        )
      end

    assign(socket, :form, to_form(form))
  end

  defp load_work_item!(id, actor) do
    case Execution.get_work_item(id, actor: actor) do
      {:ok, work_item} -> work_item
      {:error, error} -> raise "failed to load work item #{id}: #{inspect(error)}"
    end
  end

  defp load_projects(actor) do
    case Execution.list_projects(actor: actor) do
      {:ok, projects} -> Enum.sort_by(projects, &String.downcase(&1.name || ""))
      {:error, error} -> raise "failed to load projects: #{inspect(error)}"
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

  defp load_parent_work_items(_actor, nil, _work_item), do: []

  defp load_parent_work_items(actor, project_id, work_item) do
    case Execution.list_work_items_for_project(
           project_id,
           actor: actor,
           load: [:status_variant, :priority_variant]
         ) do
      {:ok, work_items} ->
        current_id = work_item && work_item.id

        work_items
        |> Enum.reject(&(&1.id == current_id))
        |> Enum.sort_by(&{&1.sort_order, String.downcase(&1.title || "")})

      {:error, error} ->
        raise "failed to load parent work items for project #{project_id}: #{inspect(error)}"
    end
  end

  defp selected_project_id(nil, params), do: blank_to_nil(params["project_id"])
  defp selected_project_id(work_item, _params), do: work_item.project_id

  defp work_item_defaults(params) do
    %{}
    |> maybe_put("project_id", params["project_id"])
    |> maybe_put("parent_work_item_id", params["parent_work_item_id"])
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, _key, ""), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp blank_to_nil(nil), do: nil
  defp blank_to_nil(""), do: nil
  defp blank_to_nil(value), do: value

  defp back_path(nil), do: ~p"/execution/work-items"
  defp back_path(project_id), do: ~p"/execution/projects/#{project_id}"

  defp project_label(project) do
    [project.name, project.code]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(" · ")
  end

  defp parent_work_item_label(work_item) do
    [work_item.title, work_item.code, work_item.status |> to_string() |> String.replace("_", " ")]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(" · ")
  end

  defp kind_options do
    [
      {"Phase", :phase},
      {"Milestone", :milestone},
      {"Deliverable", :deliverable},
      {"Task", :task},
      {"Issue", :issue},
      {"Change Order", :change_order},
      {"Checklist", :checklist}
    ]
  end

  defp discipline_options do
    [
      {"Automation", :automation},
      {"PLC", :plc},
      {"HMI", :hmi},
      {"SCADA", :scada},
      {"Web", :web},
      {"Integration", :integration},
      {"Commissioning", :commissioning},
      {"Documentation", :documentation},
      {"Support", :support},
      {"Other", :other}
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
