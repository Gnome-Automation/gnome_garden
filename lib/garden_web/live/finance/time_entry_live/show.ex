defmodule GnomeGardenWeb.Finance.TimeEntryLive.Show do
  use GnomeGardenWeb, :live_view

  import GnomeGardenWeb.Finance.Helpers

  alias GnomeGarden.Finance

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    time_entry = load_time_entry!(id, socket.assigns.current_user)

    {:ok,
     socket
     |> assign(:page_title, "Time Entry")
     |> assign(:time_entry, time_entry)}
  end

  @impl true
  def handle_event("transition", %{"action" => action}, socket) do
    time_entry = socket.assigns.time_entry
    actor = socket.assigns.current_user

    case transition_time_entry(time_entry, String.to_existing_atom(action), actor) do
      {:ok, updated_time_entry} ->
        {:noreply,
         socket
         |> assign(:time_entry, load_time_entry!(updated_time_entry.id, actor))
         |> put_flash(:info, "Time entry updated")}

      {:error, error} ->
        {:noreply, put_flash(socket, :error, "Could not update time entry: #{inspect(error)}")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.page class="pb-8">
      <.page_header eyebrow="Finance">
        Time Entry
        <:subtitle>
          <span class="inline-flex items-center gap-2">
            <.status_badge status={@time_entry.status_variant}>
              {format_atom(@time_entry.status)}
            </.status_badge>
            <span class="text-zinc-400 dark:text-zinc-500">/</span>
            <span>{format_date(@time_entry.work_date)}</span>
          </span>
        </:subtitle>
        <:actions>
          <.button navigate={~p"/finance/time-entries"}>
            <.icon name="hero-arrow-left" class="size-4" /> Back
          </.button>
          <.button :if={@time_entry.project} navigate={~p"/execution/projects/#{@time_entry.project}"}>
            <.icon name="hero-wrench-screwdriver" class="size-4" /> Project
          </.button>
          <.button
            :if={@time_entry.work_order}
            navigate={~p"/execution/work-orders/#{@time_entry.work_order}"}
          >
            <.icon name="hero-wrench-screwdriver" class="size-4" /> Work Order
          </.button>
          <.button navigate={~p"/finance/time-entries/#{@time_entry}/edit"}>
            <.icon name="hero-pencil-square" class="size-4" /> Edit
          </.button>
        </:actions>
      </.page_header>

      <.section
        title="Time Entry Actions"
        description="Advance labor rows explicitly so approvals, billing, and entitlement usage stay grounded in real review decisions."
      >
        <div class="flex flex-wrap gap-3">
          <.button
            :for={action <- time_entry_actions(@time_entry)}
            phx-click="transition"
            phx-value-action={action.action}
            variant={action.variant}
          >
            <.icon name={action.icon} class="size-4" /> {action.label}
          </.button>
        </div>
      </.section>

      <div class="grid gap-6 lg:grid-cols-2">
        <.section title="Entry Snapshot">
          <div class="grid gap-5 sm:grid-cols-2">
            <.property_item label="Work Date" value={format_date(@time_entry.work_date)} />
            <.property_item label="Minutes" value={format_minutes(@time_entry.minutes)} />
            <.property_item label="Member" value={display_email(@time_entry.member_user)} />
            <.property_item label="Approved By" value={display_email(@time_entry.approved_by_user)} />
            <.property_item
              label="Billable"
              value={if(@time_entry.billable, do: "Yes", else: "No")}
            />
            <.property_item label="Bill Rate" value={format_amount(@time_entry.bill_rate)} />
            <.property_item label="Cost Rate" value={format_amount(@time_entry.cost_rate)} />
            <.property_item label="Approved At" value={format_datetime(@time_entry.approved_at)} />
            <.property_item label="Billed At" value={format_datetime(@time_entry.billed_at)} />
            <.property_item
              label="Entitlement Usage"
              value={Integer.to_string(@time_entry.entitlement_usage_count || 0)}
            />
          </div>
        </.section>

        <.section title="Operational Context">
          <div class="grid gap-5 sm:grid-cols-2">
            <.property_item
              label="Organization"
              value={(@time_entry.organization && @time_entry.organization.name) || "-"}
            />
            <.property_item
              label="Agreement"
              value={(@time_entry.agreement && @time_entry.agreement.name) || "-"}
            />
            <.property_item
              label="Project"
              value={(@time_entry.project && @time_entry.project.name) || "-"}
            />
            <.property_item
              label="Work Item"
              value={(@time_entry.work_item && @time_entry.work_item.title) || "-"}
            />
            <.property_item
              label="Work Order"
              value={(@time_entry.work_order && @time_entry.work_order.title) || "-"}
            />
          </div>
        </.section>
      </div>

      <.section title="Description">
        <p class="whitespace-pre-wrap text-sm leading-6 text-zinc-600 dark:text-zinc-300">
          {@time_entry.description}
        </p>
      </.section>

      <.section :if={@time_entry.notes} title="Notes">
        <p class="whitespace-pre-wrap text-sm leading-6 text-zinc-600 dark:text-zinc-300">
          {@time_entry.notes}
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
      <p class="text-xs font-semibold uppercase tracking-[0.2em] text-zinc-400 dark:text-zinc-500">
        {@label}
      </p>
      <p class="text-sm font-medium text-zinc-900 dark:text-white">{@value}</p>
    </div>
    """
  end

  defp load_time_entry!(id, actor) do
    user_loads =
      if actor do
        [member_user: [], approved_by_user: []]
      else
        []
      end

    case Finance.get_time_entry(
           id,
           actor: actor,
           load:
             [
               :status_variant,
               :entitlement_usage_count,
               organization: [],
               agreement: [],
               project: [],
               work_item: [],
               work_order: []
             ] ++ user_loads
         ) do
      {:ok, time_entry} -> time_entry
      {:error, error} -> raise "failed to load time entry #{id}: #{inspect(error)}"
    end
  end

  defp time_entry_actions(%{status: :draft}) do
    [
      %{action: "submit", label: "Submit", icon: "hero-paper-airplane", variant: "primary"}
    ]
  end

  defp time_entry_actions(%{status: :submitted}) do
    [
      %{action: "approve", label: "Approve", icon: "hero-check-badge", variant: "primary"},
      %{action: "reject", label: "Reject", icon: "hero-x-circle", variant: nil}
    ]
  end

  defp time_entry_actions(%{status: :approved}) do
    [
      %{action: "mark_billed", label: "Mark Billed", icon: "hero-banknotes", variant: "primary"},
      %{action: "reopen", label: "Reopen", icon: "hero-arrow-path", variant: nil}
    ]
  end

  defp time_entry_actions(%{status: :rejected}) do
    [
      %{action: "reopen", label: "Reopen", icon: "hero-arrow-path", variant: "primary"}
    ]
  end

  defp time_entry_actions(_time_entry), do: []

  defp transition_time_entry(time_entry, :submit, actor),
    do: Finance.submit_time_entry(time_entry, actor: actor)

  defp transition_time_entry(time_entry, :approve, actor) do
    params =
      if actor do
        %{approved_by_user_id: actor.id}
      else
        %{}
      end

    Finance.approve_time_entry(time_entry, params, actor: actor)
  end

  defp transition_time_entry(time_entry, :reject, actor),
    do: Finance.reject_time_entry(time_entry, actor: actor)

  defp transition_time_entry(time_entry, :mark_billed, actor),
    do: Finance.bill_time_entry(time_entry, actor: actor)

  defp transition_time_entry(time_entry, :reopen, actor),
    do: Finance.reopen_time_entry(time_entry, actor: actor)
end
