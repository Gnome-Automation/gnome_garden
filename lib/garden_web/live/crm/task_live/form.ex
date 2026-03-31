defmodule GnomeGardenWeb.CRM.TaskLive.Form do
  use GnomeGardenWeb, :live_view

  alias GnomeGarden.Sales

  @impl true
  def mount(params, _session, socket) do
    task =
      if id = params["id"] do
        Sales.get_task!(id, actor: socket.assigns.current_user)
      else
        nil
      end

    companies = Sales.list_companies!(actor: socket.assigns.current_user)
    contacts = Sales.list_contacts!(actor: socket.assigns.current_user)

    {:ok,
     socket
     |> assign(:task, task)
     |> assign(:companies, companies)
     |> assign(:contacts, contacts)
     |> assign(:page_title, if(task, do: "Edit #{task.title}", else: "New Task"))
     |> assign_form()}
  end

  defp assign_form(%{assigns: %{task: task, current_user: actor}} = socket) do
    form =
      if task do
        Sales.form_to_update_task(task, actor: actor)
      else
        Sales.form_to_create_task(actor: actor)
      end

    assign(socket, form: to_form(form))
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.header>
      {@page_title}
    </.header>

    <.form for={@form} id="task-form" phx-change="validate" phx-submit="save" class="space-y-6 max-w-2xl">
      <.input field={@form[:title]} label="Title" required />

      <.input field={@form[:description]} type="textarea" label="Description" />

      <div class="grid grid-cols-1 gap-6 sm:grid-cols-2">
        <.input
          field={@form[:task_type]}
          type="select"
          label="Type"
          prompt="Select type..."
          options={[
            {"Call", :call},
            {"Email", :email},
            {"Follow Up", :follow_up},
            {"Meeting", :meeting},
            {"Proposal", :proposal},
            {"Other", :other}
          ]}
        />
        <.input
          field={@form[:priority]}
          type="select"
          label="Priority"
          options={[
            {"Low", :low},
            {"Normal", :normal},
            {"High", :high},
            {"Urgent", :urgent}
          ]}
        />
      </div>

      <div class="grid grid-cols-1 gap-6 sm:grid-cols-2">
        <.input
          :if={@task}
          field={@form[:status]}
          type="select"
          label="Status"
          options={[
            {"Pending", :pending},
            {"In Progress", :in_progress},
            {"Completed", :completed},
            {"Cancelled", :cancelled}
          ]}
        />
        <.input field={@form[:due_at]} label="Due Date" type="datetime-local" />
      </div>

      <div class="grid grid-cols-1 gap-6 sm:grid-cols-2">
        <.input
          field={@form[:company_id]}
          type="select"
          label="Company"
          prompt="Select company..."
          options={Enum.map(@companies, &{&1.name, &1.id})}
        />
        <.input
          field={@form[:contact_id]}
          type="select"
          label="Contact"
          prompt="Select contact..."
          options={Enum.map(@contacts, &{"#{&1.first_name} #{&1.last_name}", &1.id})}
        />
      </div>

      <div class="flex gap-4 pt-4">
        <.button type="submit" variant="primary" phx-disable-with="Saving...">
          Save Task
        </.button>
        <.button type="button" navigate={~p"/crm/tasks"}>Cancel</.button>
      </div>
    </.form>
    """
  end

  @impl true
  def handle_event("validate", %{"form" => params}, socket) do
    form = AshPhoenix.Form.validate(socket.assigns.form.source, params)
    {:noreply, assign(socket, form: to_form(form))}
  end

  def handle_event("save", %{"form" => params}, socket) do
    case AshPhoenix.Form.submit(socket.assigns.form.source, params: params) do
      {:ok, task} ->
        {:noreply,
         socket
         |> put_flash(:info, "Task #{if socket.assigns.task, do: "updated", else: "created"}")
         |> push_navigate(to: ~p"/crm/tasks/#{task}")}

      {:error, form} ->
        {:noreply, assign(socket, form: to_form(form))}
    end
  end
end
