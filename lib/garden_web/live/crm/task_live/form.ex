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
    <.page max_width="max-w-5xl" class="pb-8">
      <.page_header eyebrow="CRM">
        {@page_title}
        <:subtitle>
          {if @task,
            do: "Update the task status, timing, and who or what it supports.",
            else: "Create a follow-up action and connect it to the right company or contact."}
        </:subtitle>
        <:actions>
          <.button navigate={~p"/crm/tasks"}>
            <.icon name="hero-arrow-left" class="size-4" /> Back to tasks
          </.button>
        </:actions>
      </.page_header>

      <.form for={@form} id="task-form" phx-change="validate" phx-submit="save" class="space-y-6">
        <.form_section
          title="Task Details"
          description="Set the work type, urgency, due date, and any narrative context."
        >
          <div class="grid grid-cols-1 gap-6 sm:grid-cols-6">
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
        </.form_section>

        <.form_section
          title="Associations"
          description="Attach the task to the right customer context so follow-ups stay visible."
        >
          <div class="grid grid-cols-1 gap-6 sm:grid-cols-6">
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
        </.form_section>

        <.section body_class="px-6 py-5 sm:px-7">
          <.form_actions
            cancel_path={~p"/crm/tasks"}
            submit_label={if @task, do: "Update Task", else: "Create Task"}
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
