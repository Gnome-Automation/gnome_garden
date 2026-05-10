defmodule GnomeGardenWeb.Execution.AssignmentLive.Show do
  use GnomeGardenWeb, :live_view

  import GnomeGardenWeb.Execution.Helpers

  alias GnomeGarden.Execution

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    assignment = load_assignment!(id, socket.assigns.current_user)

    {:ok,
     socket
     |> assign(:page_title, assignment.title)
     |> assign(:assignment, assignment)}
  end

  @impl true
  def handle_event("transition", %{"action" => action}, socket) do
    assignment = socket.assigns.assignment

    case transition_assignment(
           assignment,
           String.to_existing_atom(action),
           socket.assigns.current_user
         ) do
      {:ok, updated_assignment} ->
        {:noreply,
         socket
         |> assign(
           :assignment,
           load_assignment!(updated_assignment.id, socket.assigns.current_user)
         )
         |> put_flash(:info, "Assignment updated")}

      {:error, error} ->
        {:noreply, put_flash(socket, :error, "Could not update assignment: #{inspect(error)}")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.page class="pb-8">
      <.page_header eyebrow="Execution">
        {@assignment.title}
        <:subtitle>
          <span class="inline-flex items-center gap-2">
            <.status_badge status={@assignment.status_variant}>
              {format_atom(@assignment.status)}
            </.status_badge>
            <span class="text-base-content/40">/</span>
            <span>{display_team_member(@assignment.assigned_team_member, "No assignee")}</span>
          </span>
        </:subtitle>
        <:actions>
          <.button navigate={~p"/execution/assignments"}>
            Back
          </.button>
          <.button
            :if={@assignment.work_item}
            navigate={~p"/execution/work-items/#{@assignment.work_item}"}
          >
            Work Item
          </.button>
          <.button
            :if={@assignment.work_order}
            navigate={~p"/execution/work-orders/#{@assignment.work_order}"}
          >
            Work Order
          </.button>
          <.button navigate={~p"/execution/assignments/#{@assignment}/edit"}>
            Edit
          </.button>
        </:actions>
      </.page_header>

      <.section
        title="Assignment Actions"
        description="Keep dispatch commitments explicit so actual execution, time capture, and customer expectations stay aligned."
      >
        <div class="flex flex-wrap gap-3">
          <.button
            :for={action <- assignment_actions(@assignment)}
            phx-click="transition"
            phx-value-action={action.action}
            variant={action.variant}
          >
            <.icon name={action.icon} class="size-4" /> {action.label}
          </.button>
        </div>
      </.section>

      <div class="grid gap-6 lg:grid-cols-2">
        <.section title="Scheduling Snapshot">
          <div class="grid gap-5 sm:grid-cols-2">
            <.property_item label="Assignment Type" value={format_atom(@assignment.assignment_type)} />
            <.property_item label="Location Mode" value={format_atom(@assignment.location_mode)} />
            <.property_item
              label="Assignee"
              value={display_team_member(@assignment.assigned_team_member)}
            />
            <.property_item
              label="Assigned By"
              value={display_team_member(@assignment.assigned_by_team_member)}
            />
            <.property_item
              label="Scheduled Start"
              value={format_datetime(@assignment.scheduled_start_at)}
            />
            <.property_item
              label="Scheduled End"
              value={format_datetime(@assignment.scheduled_end_at)}
            />
            <.property_item label="Actual Start" value={format_datetime(@assignment.actual_start_at)} />
            <.property_item label="Actual End" value={format_datetime(@assignment.actual_end_at)} />
            <.property_item
              label="Planned Minutes"
              value={format_minutes(@assignment.planned_minutes)}
            />
            <.property_item
              label="Billable"
              value={if(@assignment.billable, do: "Yes", else: "No")}
            />
          </div>
        </.section>

        <.section title="Execution Context">
          <div class="grid gap-5 sm:grid-cols-2">
            <.property_item
              label="Organization"
              value={(@assignment.organization && @assignment.organization.name) || "-"}
            />
            <.property_item
              label="Project"
              value={(@assignment.project && @assignment.project.name) || "-"}
            />
            <.property_item
              label="Work Item"
              value={(@assignment.work_item && @assignment.work_item.title) || "-"}
            />
            <.property_item
              label="Work Order"
              value={(@assignment.work_order && @assignment.work_order.title) || "-"}
            />
          </div>
        </.section>
      </div>

      <.section :if={@assignment.notes} title="Notes">
        <p class="whitespace-pre-wrap text-sm leading-6 text-base-content/70">
          {@assignment.notes}
        </p>
      </.section>
    </.page>
    """
  end

  attr :label, :string, required: true
  attr :value, :string, required: true

  defp property_item(assigns) do
    ~H"""
    <div class="space-y-1">
      <p class="text-xs font-semibold uppercase tracking-[0.2em] text-base-content/40">
        {@label}
      </p>
      <p class="text-sm font-medium text-base-content">{@value}</p>
    </div>
    """
  end

  defp load_assignment!(id, actor) do
    case Execution.get_assignment(
           id,
           actor: actor,
           load: [
             :status_variant,
             assigned_team_member: [],
             assigned_by_team_member: [],
             organization: [],
             project: [],
             work_item: [],
             work_order: []
           ]
         ) do
      {:ok, assignment} -> assignment
      {:error, error} -> raise "failed to load assignment #{id}: #{inspect(error)}"
    end
  end

  defp assignment_actions(%{status: :planned}) do
    [
      %{action: "confirm", label: "Confirm", icon: "hero-check-badge", variant: nil},
      %{action: "start", label: "Start", icon: "hero-play", variant: "primary"},
      %{action: "cancel", label: "Cancel", icon: "hero-x-circle", variant: nil}
    ]
  end

  defp assignment_actions(%{status: :confirmed}) do
    [
      %{action: "start", label: "Start", icon: "hero-play", variant: "primary"},
      %{action: "complete", label: "Complete", icon: "hero-check", variant: nil},
      %{action: "cancel", label: "Cancel", icon: "hero-x-circle", variant: nil}
    ]
  end

  defp assignment_actions(%{status: :in_progress}) do
    [
      %{action: "complete", label: "Complete", icon: "hero-check", variant: "primary"},
      %{action: "cancel", label: "Cancel", icon: "hero-x-circle", variant: nil}
    ]
  end

  defp assignment_actions(%{status: :completed}) do
    [
      %{action: "reopen", label: "Reopen", icon: "hero-arrow-path", variant: "primary"}
    ]
  end

  defp assignment_actions(%{status: :cancelled}) do
    [
      %{action: "reopen", label: "Reopen", icon: "hero-arrow-path", variant: "primary"}
    ]
  end

  defp assignment_actions(_assignment), do: []

  defp transition_assignment(assignment, :confirm, actor),
    do: Execution.confirm_assignment(assignment, actor: actor)

  defp transition_assignment(assignment, :start, actor),
    do: Execution.start_assignment(assignment, actor: actor)

  defp transition_assignment(assignment, :complete, actor),
    do: Execution.complete_assignment(assignment, actor: actor)

  defp transition_assignment(assignment, :cancel, actor),
    do: Execution.cancel_assignment(assignment, actor: actor)

  defp transition_assignment(assignment, :reopen, actor),
    do: Execution.reopen_assignment(assignment, actor: actor)
end
