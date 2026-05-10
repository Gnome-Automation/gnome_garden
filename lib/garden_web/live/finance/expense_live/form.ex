defmodule GnomeGardenWeb.Finance.ExpenseLive.Form do
  use GnomeGardenWeb, :live_view

  alias GnomeGarden.Commercial
  alias GnomeGarden.Execution
  alias GnomeGarden.Finance
  alias GnomeGarden.Operations

  @impl true
  def mount(params, _session, socket) do
    expense = if id = params["id"], do: load_expense!(id, socket.assigns.current_user)

    {:ok,
     socket
     |> assign(:expense, expense)
     |> assign(:organizations, load_organizations(socket.assigns.current_user))
     |> assign(:agreements, load_agreements(socket.assigns.current_user))
     |> assign(:projects, load_projects(socket.assigns.current_user))
     |> assign(:work_orders, load_work_orders(socket.assigns.current_user))
     |> assign(:team_members, load_team_members(socket.assigns.current_user))
     |> assign(:page_title, if(expense, do: "Edit Expense", else: "New Expense"))
     |> assign_form(params)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.page max_width="max-w-5xl" class="pb-8">
      <.page_header eyebrow="Finance">
        {@page_title}
        <:subtitle>
          Capture non-labor cost against the right organization and execution context before approvals happen.
        </:subtitle>
        <:actions>
          <.button navigate={~p"/finance/expenses"}>
            Back to expenses
          </.button>
        </:actions>
      </.page_header>

      <.form
        for={@form}
        id="expense-form"
        phx-change="validate"
        phx-submit="save"
        class="space-y-6"
      >
        <.form_section
          title="Expense Details"
          description="Tie the cost to the right customer, project, or service work record before it hits approvals and billing."
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
                field={@form[:incurred_by_team_member_id]}
                type="select"
                label="Incurred By"
                prompt="Select member..."
                options={Enum.map(@team_members, &{team_member_label(&1), &1.id})}
                required
              />
            </div>
            <div class="sm:col-span-2">
              <.input field={@form[:incurred_on]} type="date" label="Incurred On" required />
            </div>
            <div class="sm:col-span-2">
              <.input
                field={@form[:category]}
                type="select"
                label="Category"
                options={category_options()}
              />
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
                field={@form[:work_order_id]}
                type="select"
                label="Work Order"
                prompt="Select work order..."
                options={Enum.map(@work_orders, &{work_order_label(&1), &1.id})}
              />
            </div>
            <div class="sm:col-span-3">
              <.input field={@form[:vendor]} label="Vendor" />
            </div>
            <div class="sm:col-span-2">
              <.input field={@form[:amount]} type="number" step="0.01" label="Amount" required />
            </div>
            <div class="sm:col-span-4">
              <.input field={@form[:receipt_url]} label="Receipt URL" />
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
            cancel_path={~p"/finance/expenses"}
            submit_label={if @expense, do: "Update Expense", else: "Create Expense"}
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
      {:ok, expense} ->
        {:noreply,
         socket
         |> put_flash(
           :info,
           "Expense #{if socket.assigns.expense, do: "updated", else: "created"}"
         )
         |> push_navigate(to: ~p"/finance/expenses/#{expense}")}

      {:error, form} ->
        {:noreply, assign(socket, form: to_form(form))}
    end
  end

  defp assign_form(%{assigns: %{expense: expense, current_user: actor}} = socket, params) do
    form =
      if expense do
        AshPhoenix.Form.for_update(expense, :update, actor: actor, domain: Finance)
      else
        AshPhoenix.Form.for_create(
          Finance.Expense,
          :create,
          actor: actor,
          domain: Finance,
          params: expense_defaults(params, actor)
        )
      end

    assign(socket, :form, to_form(form))
  end

  defp load_expense!(id, actor) do
    case Finance.get_expense(id, actor: actor) do
      {:ok, expense} -> expense
      {:error, error} -> raise "failed to load expense #{id}: #{inspect(error)}"
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

  defp expense_defaults(params, actor) do
    %{}
    |> maybe_put("organization_id", params["organization_id"])
    |> maybe_put("agreement_id", params["agreement_id"])
    |> maybe_put("project_id", params["project_id"])
    |> maybe_put("work_order_id", params["work_order_id"])
    |> maybe_put(
      "incurred_by_team_member_id",
      params["incurred_by_team_member_id"] || Operations.current_team_member_id(actor)
    )
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, _key, ""), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

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

  defp work_order_label(work_order) do
    [work_order.title, work_order.reference_number]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(" · ")
  end

  defp team_member_label(team_member), do: team_member.display_name || "Team member"

  defp category_options do
    [
      {"Travel", :travel},
      {"Lodging", :lodging},
      {"Meals", :meals},
      {"Materials", :materials},
      {"Equipment", :equipment},
      {"Software", :software},
      {"Other", :other}
    ]
  end
end
