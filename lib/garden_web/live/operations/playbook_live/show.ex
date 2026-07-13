defmodule GnomeGardenWeb.Operations.PlaybookLive.Show do
  use GnomeGardenWeb, :live_view

  import GnomeGardenWeb.Operations.Helpers, only: [format_atom: 1]

  alias GnomeGarden.Operations

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    playbook = load_playbook!(id, socket.assigns.current_user)

    if connected?(socket) do
      GnomeGardenWeb.Endpoint.subscribe("playbook_step:playbook:#{playbook.id}")
    end

    {:ok,
     socket
     |> assign(:page_title, playbook.name)
     |> assign(:playbook, playbook)
     |> assign(:team_members, load_team_members(socket.assigns.current_user))
     |> assign_steps()
     |> assign_step_form()}
  end

  @impl true
  def handle_event("validate_step", %{"form" => params}, socket) do
    form = AshPhoenix.Form.validate(socket.assigns.step_form, params)
    {:noreply, assign(socket, step_form: to_form(form))}
  end

  @impl true
  def handle_event("save_step", %{"form" => params}, socket) do
    case AshPhoenix.Form.submit(socket.assigns.step_form, params: params) do
      {:ok, _step} ->
        {:noreply,
         socket
         |> put_flash(:info, "Step added")
         |> assign_steps()
         |> assign_step_form()}

      {:error, form} ->
        {:noreply, assign(socket, step_form: to_form(form))}
    end
  end

  @impl true
  def handle_event("delete_step", %{"id" => id}, socket) do
    with {:ok, step} <- Operations.get_playbook_step(id, actor: socket.assigns.current_user),
         :ok <- Operations.delete_playbook_step(step, actor: socket.assigns.current_user) do
      {:noreply,
       socket
       |> put_flash(:info, "Step removed")
       |> assign_steps()
       |> assign_step_form()}
    else
      {:error, error} ->
        {:noreply, put_flash(socket, :error, "Could not remove step: #{inspect(error)}")}
    end
  end

  @impl true
  def handle_info(%{topic: "playbook_step:playbook:" <> _playbook_id}, socket) do
    {:noreply, assign_steps(socket)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.page max_width="max-w-4xl" class="pb-8">
      <.page_header eyebrow="Playbook">
        {@playbook.name}
        <:subtitle>
          <span class="inline-flex items-center gap-2">
            <.status_badge status={if @playbook.status == :active, do: :success, else: :default}>
              {format_atom(@playbook.status)}
            </.status_badge>
            <span :if={@playbook.description}>{@playbook.description}</span>
          </span>
        </:subtitle>
        <:actions>
          <.button navigate={~p"/operations/playbooks"}>
            Back
          </.button>
          <.button navigate={~p"/operations/playbooks/#{@playbook}/edit"}>
            Edit
          </.button>
        </:actions>
      </.page_header>

      <.section title="Steps" body_class="p-0">
        <div :if={@steps == []} class="p-4">
          <.empty_state
            icon="hero-list-bullet"
            title="No steps yet"
            description="Add ordered steps below; applying the playbook creates one task per step."
          />
        </div>
        <div :if={@steps != []} class="divide-y divide-zinc-200 dark:divide-white/10">
          <div :for={step <- @steps} class="flex items-start justify-between gap-3 px-4 py-3">
            <div class="min-w-0">
              <p class="font-medium text-base-content">
                <span class="mr-2 text-base-content/40">{step.position}.</span>{step.title}
              </p>
              <p class="mt-0.5 text-xs text-base-content/50">
                {format_atom(step.task_type)} · {format_atom(step.priority)} · {offset_label(
                  step.due_offset_days
                )} · {assignee_label(step, @team_members)}
              </p>
            </div>
            <.button phx-click="delete_step" phx-value-id={step.id}>
              Remove
            </.button>
          </div>
        </div>
      </.section>

      <.form
        for={@step_form}
        id="playbook-step-form"
        phx-change="validate_step"
        phx-submit="save_step"
        class="space-y-6"
      >
        <.form_section title="Add Step">
          <div class="grid grid-cols-1 gap-6 sm:grid-cols-6">
            <div class="sm:col-span-1">
              <.input field={@step_form[:position]} type="number" label="Position" min="1" />
            </div>
            <div class="sm:col-span-5">
              <.input field={@step_form[:title]} label="Title" required />
            </div>
            <div class="col-span-full">
              <.input field={@step_form[:description]} type="textarea" label="Description" />
            </div>
            <div class="sm:col-span-2">
              <.input
                field={@step_form[:task_type]}
                type="select"
                label="Type"
                options={task_type_options()}
              />
            </div>
            <div class="sm:col-span-2">
              <.input
                field={@step_form[:priority]}
                type="select"
                label="Priority"
                options={priority_options()}
              />
            </div>
            <div class="sm:col-span-2">
              <.input
                field={@step_form[:due_offset_days]}
                type="number"
                label="Due (days after apply)"
                min="0"
              />
            </div>
            <div class="sm:col-span-3">
              <.input
                field={@step_form[:assignee_strategy]}
                type="select"
                label="Assignee"
                options={[
                  {"Unassigned", :unassigned},
                  {"Whoever applies the playbook", :applier},
                  {"Specific team member", :specific}
                ]}
              />
            </div>
            <div class="sm:col-span-3">
              <.input
                field={@step_form[:assignee_team_member_id]}
                type="select"
                label="Specific member"
                prompt="None"
                options={Enum.map(@team_members, &{&1.display_name, &1.id})}
              />
            </div>
          </div>
        </.form_section>

        <.section body_class="px-6 py-5 sm:px-7">
          <.form_actions
            cancel_path={~p"/operations/playbooks"}
            submit_label="Add Step"
          />
        </.section>

        <.input field={@step_form[:playbook_id]} type="hidden" />
      </.form>
    </.page>
    """
  end

  defp assign_steps(socket) do
    case Operations.list_playbook_steps_for_playbook(socket.assigns.playbook.id,
           actor: socket.assigns.current_user
         ) do
      {:ok, steps} -> assign(socket, :steps, steps)
      {:error, error} -> raise "failed to load playbook steps: #{inspect(error)}"
    end
  end

  defp assign_step_form(socket) do
    next_position =
      case socket.assigns[:steps] do
        [] -> 1
        steps -> steps |> Enum.map(& &1.position) |> Enum.max() |> Kernel.+(1)
      end

    form =
      AshPhoenix.Form.for_create(Operations.PlaybookStep, :create,
        actor: socket.assigns.current_user,
        domain: Operations,
        params: %{
          "playbook_id" => socket.assigns.playbook.id,
          "position" => next_position
        }
      )

    assign(socket, :step_form, to_form(form))
  end

  defp offset_label(nil), do: "No due date"
  defp offset_label(0), do: "Due same day"
  defp offset_label(days), do: "Due +#{days}d"

  defp assignee_label(%{assignee_strategy: :specific} = step, team_members) do
    member = Enum.find(team_members, &(&1.id == step.assignee_team_member_id))
    if member, do: member.display_name, else: "Specific member"
  end

  defp assignee_label(%{assignee_strategy: :applier}, _members), do: "Applier"
  defp assignee_label(_step, _members), do: "Unassigned"

  defp task_type_options do
    [
      {"Review", :review},
      {"Research", :research},
      {"Call", :call},
      {"Email", :email},
      {"Evidence", :evidence},
      {"Proposal", :proposal},
      {"Finance", :finance},
      {"Source cleanup", :source_cleanup},
      {"Agent follow-up", :agent_followup},
      {"Other", :other}
    ]
  end

  defp priority_options do
    [{"Low", :low}, {"Normal", :normal}, {"High", :high}, {"Urgent", :urgent}]
  end

  defp load_playbook!(id, actor) do
    case Operations.get_playbook(id, actor: actor) do
      {:ok, playbook} -> playbook
      {:error, error} -> raise "failed to load playbook #{id}: #{inspect(error)}"
    end
  end

  defp load_team_members(actor) do
    case Operations.list_active_team_members(actor: actor) do
      {:ok, members} -> members
      {:error, _error} -> []
    end
  end
end
