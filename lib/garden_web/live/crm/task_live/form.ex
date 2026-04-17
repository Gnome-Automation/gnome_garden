defmodule GnomeGardenWeb.CRM.TaskLive.Form do
  use GnomeGardenWeb, :live_view

  alias GnomeGarden.CRM.Forms, as: CRMForms

  @impl true
  def mount(params, _session, socket) do
    task =
      if id = params["id"] do
        CRMForms.get_task!(id, actor: socket.assigns.current_user)
      else
        nil
      end

    companies = CRMForms.list_companies!(actor: socket.assigns.current_user)
    contacts = CRMForms.list_contacts!(actor: socket.assigns.current_user)

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
        CRMForms.form_to_update_task(task, actor: actor)
      else
        CRMForms.form_to_create_task(actor: actor)
      end

    assign(socket, form: to_form(form))
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.header>
      {@page_title}
    </.header>

    <.form for={@form} id="task-form" phx-change="validate" phx-submit="save">
      <div class="space-y-12">
        <div class="border-b border-gray-900/10 pb-12 dark:border-white/10">
          <h2 class="text-base/7 font-semibold text-gray-900 dark:text-white">Task Details</h2>
          <p class="mt-1 text-sm/6 text-gray-600 dark:text-gray-400">
            What needs to be done and when.
          </p>
          <div class="mt-10 grid grid-cols-1 gap-x-6 gap-y-8 sm:grid-cols-6">
            <div class="sm:col-span-4">
              <.input field={@form[:title]} label="Title" required />
            </div>
            <div class="sm:col-span-3">
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
            </div>
            <div class="sm:col-span-3">
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
            <div :if={@task} class="sm:col-span-3">
              <.input
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
            </div>
            <div class="sm:col-span-3">
              <.input field={@form[:due_at]} label="Due Date" type="datetime-local" />
            </div>
            <div class="col-span-full">
              <.input field={@form[:description]} type="textarea" label="Description" />
            </div>
          </div>
        </div>

        <div class="border-b border-gray-900/10 pb-12 dark:border-white/10">
          <h2 class="text-base/7 font-semibold text-gray-900 dark:text-white">Associations</h2>
          <p class="mt-1 text-sm/6 text-gray-600 dark:text-gray-400">
            Link this task to a company or contact.
          </p>
          <div class="mt-10 grid grid-cols-1 gap-x-6 gap-y-8 sm:grid-cols-6">
            <div class="sm:col-span-3">
              <.input
                field={@form[:company_id]}
                type="select"
                label="Company"
                prompt="Select company..."
                options={Enum.map(@companies, &{&1.name, &1.id})}
              />
            </div>
            <div class="sm:col-span-3">
              <.input
                field={@form[:contact_id]}
                type="select"
                label="Contact"
                prompt="Select contact..."
                options={Enum.map(@contacts, &{"#{&1.first_name} #{&1.last_name}", &1.id})}
              />
            </div>
          </div>
        </div>
      </div>

      <div class="mt-6 flex items-center justify-end gap-x-6">
        <.button type="button" navigate={~p"/crm/tasks"}>Cancel</.button>
        <.button type="submit" variant="primary" phx-disable-with="Saving...">Save</.button>
      </div>
    </.form>
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
         |> push_navigate(to: ~p"/crm/tasks/#{task}")}

      {:error, form} ->
        {:noreply, assign(socket, form: to_form(form))}
    end
  end
end
