defmodule GnomeGardenWeb.Finance.TimeEntryLive.Form do
  use GnomeGardenWeb, :live_view

  alias GnomeGarden.Commercial
  alias GnomeGarden.Execution
  alias GnomeGarden.Finance
  alias GnomeGarden.Operations

  @impl true
  def mount(params, _session, socket) do
    time_entry = if id = params["id"], do: load_time_entry!(id, socket.assigns.current_user)
    selected_project_id = selected_project_id(time_entry, params)

    {:ok,
     socket
     |> assign(:time_entry, time_entry)
     |> assign(:organizations, load_organizations(socket.assigns.current_user))
     |> assign(:agreements, load_agreements(socket.assigns.current_user))
     |> assign(:projects, load_projects(socket.assigns.current_user))
     |> assign(:work_orders, load_work_orders(socket.assigns.current_user))
     |> assign(:team_members, load_team_members(socket.assigns.current_user))
     |> assign(:selected_project_id, selected_project_id)
     |> assign(
       :project_work_items,
       load_project_work_items(socket.assigns.current_user, selected_project_id)
     )
     |> assign(:page_title, if(time_entry, do: "Edit Time Entry", else: "New Time Entry"))
     |> assign_form(params)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.page max_width="max-w-5xl" class="pb-8">
      <.page_header eyebrow="Finance">
        {@page_title}
        <:subtitle>
          Capture labor against the right commercial and execution context before approvals and invoice drafting happen.
        </:subtitle>
        <:actions>
          <.button navigate={~p"/finance/time-entries"}>
            Back to time entries
          </.button>
        </:actions>
      </.page_header>

      <.form
        for={@form}
        id="time-entry-form"
        phx-change="validate"
        phx-submit="save"
        class="space-y-6"
      >
        <.form_section
          title="Time Entry Details"
          description="Tie the labor record to the right member, customer context, and execution record."
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
                field={@form[:member_team_member_id]}
                type="select"
                label="Member"
                prompt="Select member..."
                options={Enum.map(@team_members, &{team_member_label(&1), &1.id})}
                required
              />
            </div>
            <div class="sm:col-span-2">
              <.input field={@form[:work_date]} type="date" label="Work Date" required />
            </div>
            <div class="sm:col-span-2">
              <.input field={@form[:minutes]} type="number" label="Minutes" required />
            </div>
            <div class="sm:col-span-2">
              <.input field={@form[:billable]} type="checkbox" label="Billable" />
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
            <div class="sm:col-span-3">
              <.input
                field={@form[:work_item_id]}
                type="select"
                label="Work Item"
                prompt="Select work item..."
                options={Enum.map(@project_work_items, &{work_item_label(&1), &1.id})}
              />
            </div>
            <div class="sm:col-span-3">
              <.input
                field={@form[:work_order_id]}
                type="select"
                label="Work Order"
                prompt="Select work order..."
                options={Enum.map(@work_orders, &{work_order_label(&1), &1.id})}
              />
            </div>
            <div class="sm:col-span-3">
              <.input field={@form[:bill_rate]} type="number" step="0.01" label="Bill Rate" />
            </div>
            <div class="sm:col-span-3">
              <.input field={@form[:cost_rate]} type="number" step="0.01" label="Cost Rate" />
            </div>
            <div class="col-span-full">
              <.input field={@form[:description]} type="textarea" label="Description" required />
            </div>
            <div class="col-span-full">
              <.input field={@form[:notes]} type="textarea" label="Notes" />
            </div>
          </div>
        </.form_section>

        <.section body_class="px-6 py-5 sm:px-7">
          <.form_actions
            cancel_path={~p"/finance/time-entries"}
            submit_label={if @time_entry, do: "Update Time Entry", else: "Create Time Entry"}
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
      {:ok, time_entry} ->
        {:noreply,
         socket
         |> put_flash(
           :info,
           "Time entry #{if socket.assigns.time_entry, do: "updated", else: "created"}"
         )
         |> push_navigate(to: ~p"/finance/time-entries/#{time_entry}")}

      {:error, form} ->
        {:noreply, assign(socket, form: to_form(form))}
    end
  end

  defp assign_form(%{assigns: %{time_entry: time_entry, current_user: actor}} = socket, params) do
    form =
      if time_entry do
        AshPhoenix.Form.for_update(time_entry, :update, actor: actor, domain: Finance)
      else
        AshPhoenix.Form.for_create(
          Finance.TimeEntry,
          :create,
          actor: actor,
          domain: Finance,
          params: time_entry_defaults(params, actor)
        )
      end

    assign(socket, :form, to_form(form))
  end

  defp load_time_entry!(id, actor) do
    case Finance.get_time_entry(id, actor: actor) do
      {:ok, time_entry} -> time_entry
      {:error, error} -> raise "failed to load time entry #{id}: #{inspect(error)}"
    end
  end

  defp load_organizations(actor) do
    case Operations.list_organizations(actor: actor) do
      {:ok, organizations} -> Enum.sort_by(organizations, &String.downcase(&1.name || ""))
      {:error, error} -> raise "failed to load organizations: #{inspect(error)}"
    end
  end

  defp load_agreements(actor) do
    case Commercial.list_agreements(actor: actor, load: [:organization]) do
      {:ok, agreements} -> Enum.sort_by(agreements, &String.downcase(agreement_label(&1)))
      {:error, error} -> raise "failed to load agreements: #{inspect(error)}"
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

  defp load_team_members(actor) do
    if is_nil(actor) do
      []
    else
      case Operations.list_active_team_members(actor: actor) do
        {:ok, team_members} ->
          Enum.sort_by(team_members, &String.downcase(team_member_label(&1)))

        {:error, error} ->
          raise "failed to load team members: #{inspect(error)}"
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
  defp selected_project_id(time_entry, _params), do: time_entry.project_id

  defp time_entry_defaults(params, actor) do
    %{}
    |> maybe_put("organization_id", params["organization_id"])
    |> maybe_put("agreement_id", params["agreement_id"])
    |> maybe_put("project_id", params["project_id"])
    |> maybe_put("work_item_id", params["work_item_id"])
    |> maybe_put("work_order_id", params["work_order_id"])
    |> maybe_put(
      "member_team_member_id",
      params["member_team_member_id"] || Operations.current_team_member_id(actor)
    )
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, _key, ""), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp blank_to_nil(nil), do: nil
  defp blank_to_nil(""), do: nil
  defp blank_to_nil(value), do: value

  defp agreement_label(agreement) do
    [agreement.name, agreement.organization && agreement.organization.name]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(" · ")
  end

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

  defp team_member_label(team_member), do: team_member.display_name || "Team member"
end
