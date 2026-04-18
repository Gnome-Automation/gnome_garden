defmodule GnomeGardenWeb.CRM.OpportunityLive.Show do
  use GnomeGardenWeb, :live_view

  import GnomeGardenWeb.CRM.Helpers

  alias GnomeGarden.CRM.PipelineEvents
  alias GnomeGarden.Sales

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    opportunity = Sales.get_opportunity!(id, actor: socket.assigns.current_user, load: [:company])

    {:ok,
     socket
     |> assign(:page_title, opportunity.name)
     |> assign(:opportunity, opportunity)
     |> assign(:closing, nil)
     |> assign(:advancing, nil)
     |> assign(:events, load_events(opportunity.id))}
  end

  @impl true
  def handle_event("open_advance", %{"action" => action_name, "label" => label}, socket) do
    {:noreply, assign(socket, :advancing, %{action: action_name, label: label})}
  end

  def handle_event("cancel_advance", _, socket) do
    {:noreply, assign(socket, :advancing, nil)}
  end

  def handle_event("submit_advance", %{"notes" => notes}, socket) do
    opp = socket.assigns.opportunity
    %{action: action_name} = socket.assigns.advancing
    action = String.to_existing_atom(action_name)
    from_stage = opp.stage

    case Ash.update(opp, %{}, action: action) do
      {:ok, updated} ->
        PipelineEvents.log(
          %{
            event_type: :stage_advanced,
            subject_type: "opportunity",
            subject_id: opp.id,
            summary: "#{format_stage(from_stage)} -> #{format_stage(updated.stage)}",
            reason: notes,
            from_state: to_string(from_stage),
            to_state: to_string(updated.stage),
            opportunity_id: opp.id,
            company_id: opp.company_id,
            actor_id: socket.assigns.current_user && socket.assigns.current_user.id
          },
          actor: socket.assigns.current_user
        )

        {:noreply,
         socket
         |> assign(:opportunity, Ash.load!(updated, [:company]))
         |> assign(:advancing, nil)
         |> assign(:events, load_events(opp.id))
         |> put_flash(:info, "Advanced to #{format_stage(updated.stage)}")}

      {:error, error} ->
        {:noreply, put_flash(socket, :error, "Cannot advance: #{inspect(error)}")}
    end
  end

  def handle_event("open_close", %{"type" => type}, socket) do
    {:noreply, assign(socket, :closing, type)}
  end

  def handle_event("cancel_close", _, socket) do
    {:noreply, assign(socket, :closing, nil)}
  end

  def handle_event("close_won", %{"notes" => notes}, socket) do
    opp = socket.assigns.opportunity

    case Ash.update(opp, %{}, action: :close_won) do
      {:ok, updated} ->
        PipelineEvents.log(
          %{
            event_type: :closed_won,
            subject_type: "opportunity",
            subject_id: opp.id,
            summary: "Won - #{opp.name}",
            reason: notes,
            from_state: to_string(opp.stage),
            to_state: "closed_won",
            opportunity_id: opp.id,
            company_id: opp.company_id,
            actor_id: socket.assigns.current_user && socket.assigns.current_user.id
          },
          actor: socket.assigns.current_user
        )

        {:noreply,
         socket
         |> assign(:opportunity, Ash.load!(updated, [:company]))
         |> assign(:closing, nil)
         |> assign(:events, load_events(opp.id))
         |> put_flash(:info, "Opportunity won!")}

      {:error, error} ->
        {:noreply, put_flash(socket, :error, "Failed: #{inspect(error)}")}
    end
  end

  def handle_event("close_won", _params, socket) do
    handle_event("close_won", %{"notes" => ""}, socket)
  end

  def handle_event("close_lost", %{"loss_reason" => reason} = params, socket) do
    opp = socket.assigns.opportunity
    notes = params["notes"] || ""

    case Ash.update(opp, %{loss_reason: reason}, action: :close_lost) do
      {:ok, updated} ->
        PipelineEvents.log(
          %{
            event_type: :closed_lost,
            subject_type: "opportunity",
            subject_id: opp.id,
            summary: "Lost - #{opp.name}",
            reason: reason,
            from_state: to_string(opp.stage),
            to_state: "closed_lost",
            opportunity_id: opp.id,
            company_id: opp.company_id,
            actor_id: socket.assigns.current_user && socket.assigns.current_user.id,
            metadata: %{notes: notes}
          },
          actor: socket.assigns.current_user
        )

        {:noreply,
         socket
         |> assign(:opportunity, Ash.load!(updated, [:company]))
         |> assign(:closing, nil)
         |> assign(:events, load_events(opp.id))
         |> put_flash(:info, "Opportunity closed")}

      {:error, error} ->
        {:noreply, put_flash(socket, :error, "Failed: #{inspect(error)}")}
    end
  end

  @impl true
  def render(assigns) do
    assigns =
      assigns
      |> assign(:stages, stages_for_workflow(assigns.opportunity.workflow))
      |> assign(:next_actions, next_actions(assigns.opportunity))
      |> assign(:closed?, assigns.opportunity.stage in [:closed_won, :closed_lost])

    ~H"""
    <.page class="pb-8">
      <.page_header eyebrow="CRM">
        {@opportunity.name}
        <:subtitle>
          <span :if={@opportunity.company}>
            <.link
              navigate={~p"/crm/companies/#{@opportunity.company}"}
              class="hover:text-emerald-600"
            >
              {@opportunity.company.name}
            </.link>
            <span class="mx-1 text-zinc-400">/</span>
          </span>
          <span class="badge badge-sm badge-outline">{format_workflow(@opportunity.workflow)}</span>
        </:subtitle>
        <:actions>
          <.button navigate={~p"/crm/opportunities"}>
            <.icon name="hero-arrow-left" class="size-4" /> Back
          </.button>
          <.button variant="primary" navigate={~p"/crm/opportunities/#{@opportunity}/edit"}>
            <.icon name="hero-pencil-square" class="size-4" /> Edit
          </.button>
        </:actions>
      </.page_header>

      <.section
        title="Pipeline Progress"
        description="Move the deal through the current workflow and record the outcome."
      >
        <.opportunity_progress opportunity={@opportunity} stages={@stages} closed?={@closed?} />
        <.opportunity_actions :if={!@closed?} next_actions={@next_actions} />
      </.section>

      <.advance_dialog
        advancing={@advancing}
        opportunity={@opportunity}
      />
      <.close_won_dialog closing={@closing} />
      <.close_lost_dialog closing={@closing} />

      <div class="grid grid-cols-1 gap-6 lg:grid-cols-2">
        <.section title="Deal Information">
          <.properties>
            <.property name="Stage">
              <.status_badge status={opportunity_stage(@opportunity.stage)}>
                {format_stage(@opportunity.stage)}
              </.status_badge>
            </.property>
            <.property name="Workflow">{format_workflow(@opportunity.workflow)}</.property>
            <.property name="Amount">{format_amount(@opportunity.amount)}</.property>
            <.property name="Probability">{@opportunity.probability || 0}%</.property>
            <.property name="Weighted Value">{format_weighted(@opportunity)}</.property>
            <.property name="Source">{format_atom(@opportunity.source)}</.property>
          </.properties>
        </.section>

        <.section title="Timeline">
          <.properties>
            <.property name="Expected Close">
              {format_date(@opportunity.expected_close_date)}
            </.property>
            <.property :if={@opportunity.actual_close_date} name="Actual Close">
              {format_date(@opportunity.actual_close_date)}
            </.property>
            <.property name="Created">{format_datetime(@opportunity.inserted_at)}</.property>
          </.properties>
        </.section>
      </div>

      <.section :if={@opportunity.description} title="Description">
        <p class="whitespace-pre-wrap text-sm text-zinc-600 dark:text-zinc-400">
          {@opportunity.description}
        </p>
      </.section>

      <.section :if={@opportunity.loss_reason} title="Loss Reason">
        <p class="whitespace-pre-wrap text-sm text-error">
          {@opportunity.loss_reason}
        </p>
      </.section>

      <.opportunity_activity events={@events} />
    </.page>
    """
  end

  attr :opportunity, :map, required: true
  attr :stages, :list, required: true
  attr :closed?, :boolean, required: true

  defp opportunity_progress(assigns) do
    ~H"""
    <div class="flex flex-wrap items-center gap-2">
      <div :for={{stage, idx} <- Enum.with_index(@stages)} class="flex items-center gap-2">
        <div
          :if={idx > 0}
          class={[
            "h-0.5 w-6 rounded-full",
            if(stage_index(@opportunity.stage, @stages) >= idx,
              do: "bg-emerald-500",
              else: "bg-zinc-300 dark:bg-white/10"
            )
          ]}
        />
        <div class={[
          "flex items-center gap-1.5 rounded-full px-3 py-1 text-xs font-medium transition",
          cond do
            @opportunity.stage == stage ->
              "bg-emerald-600 text-white"

            stage_index(@opportunity.stage, @stages) > idx ->
              "bg-emerald-100 text-emerald-700 dark:bg-emerald-900/30 dark:text-emerald-300"

            true ->
              "bg-zinc-100 text-zinc-500 dark:bg-white/[0.05] dark:text-zinc-400"
          end
        ]}>
          <span :if={stage_index(@opportunity.stage, @stages) > idx} class="text-emerald-500">
            <.icon name="hero-check-mini" class="size-3.5" />
          </span>
          {format_stage(stage)}
        </div>
      </div>

      <div :if={@closed?} class="ml-2 flex items-center gap-2">
        <div class="h-0.5 w-6 rounded-full bg-zinc-300 dark:bg-white/10" />
        <div class={[
          "rounded-full px-3 py-1 text-xs font-bold",
          if(@opportunity.stage == :closed_won,
            do: "bg-success text-success-content",
            else: "bg-error text-error-content"
          )
        ]}>
          {if @opportunity.stage == :closed_won, do: "WON", else: "LOST"}
        </div>
      </div>
    </div>
    """
  end

  attr :next_actions, :list, required: true

  defp opportunity_actions(assigns) do
    ~H"""
    <div class="mt-5 flex flex-wrap gap-2">
      <button
        :for={{label, action} <- @next_actions}
        phx-click="open_advance"
        phx-value-action={action}
        phx-value-label={label}
        class="btn btn-sm btn-primary"
      >
        <.icon name="hero-arrow-right-mini" class="size-4" />
        {label}
      </button>

      <div class="flex-1" />

      <button phx-click="open_close" phx-value-type="won" class="btn btn-sm btn-success btn-outline">
        Won
      </button>
      <button phx-click="open_close" phx-value-type="lost" class="btn btn-sm btn-error btn-outline">
        Lost
      </button>
    </div>
    """
  end

  attr :advancing, :map, default: nil
  attr :opportunity, :map, required: true

  defp advance_dialog(assigns) do
    ~H"""
    <dialog :if={@advancing} id="advance-dialog" class="modal" phx-hook="ShowModal">
      <div class="modal-box">
        <h3 class="mb-2 text-lg font-bold">{@advancing.label}</h3>
        <p class="mb-4 text-sm text-zinc-500">
          Moving from {format_stage(@opportunity.stage)} to the next stage.
        </p>
        <form phx-submit="submit_advance">
          <.input
            name="notes"
            value=""
            label="Notes (optional)"
            type="textarea"
            placeholder="What's happening at this stage? Any context for the team?"
          />
          <div class="modal-action">
            <button type="button" phx-click="cancel_advance" class="btn btn-ghost">Cancel</button>
            <button type="submit" class="btn btn-primary">Advance</button>
          </div>
        </form>
      </div>
      <form method="dialog" class="modal-backdrop">
        <button phx-click="cancel_advance">close</button>
      </form>
    </dialog>
    """
  end

  attr :closing, :string, default: nil

  defp close_won_dialog(assigns) do
    ~H"""
    <dialog :if={@closing == "won"} id="close-won-dialog" class="modal" phx-hook="ShowModal">
      <div class="modal-box">
        <h3 class="mb-4 text-lg font-bold">Mark as Won</h3>
        <p class="mb-4 text-sm text-zinc-500">Confirm the win and record any final notes.</p>
        <form phx-submit="close_won">
          <.input
            name="notes"
            value=""
            label="Notes (optional)"
            type="textarea"
            placeholder="Any details about the win?"
          />
          <div class="modal-action">
            <button type="button" phx-click="cancel_close" class="btn btn-ghost">Cancel</button>
            <button type="submit" class="btn btn-success">Confirm Won</button>
          </div>
        </form>
      </div>
      <form method="dialog" class="modal-backdrop">
        <button phx-click="cancel_close">close</button>
      </form>
    </dialog>
    """
  end

  attr :closing, :string, default: nil

  defp close_lost_dialog(assigns) do
    ~H"""
    <dialog :if={@closing == "lost"} id="close-lost-dialog" class="modal" phx-hook="ShowModal">
      <div class="modal-box">
        <h3 class="mb-4 text-lg font-bold">Mark as Lost</h3>
        <form phx-submit="close_lost">
          <.input
            name="loss_reason"
            value=""
            label="Why did we lose this?"
            type="textarea"
            required
          />
          <div class="modal-action">
            <button type="button" phx-click="cancel_close" class="btn btn-ghost">Cancel</button>
            <button type="submit" class="btn btn-error">Confirm Lost</button>
          </div>
        </form>
      </div>
      <form method="dialog" class="modal-backdrop">
        <button phx-click="cancel_close">close</button>
      </form>
    </dialog>
    """
  end

  attr :events, :list, required: true

  defp opportunity_activity(assigns) do
    ~H"""
    <.section title="Activity" description="A timeline of stage changes and pursuit events.">
      <div :if={@events == []}>
        <.empty_state
          title="No activity yet"
          description="Pipeline events will appear as the opportunity advances."
          icon="hero-clock"
        />
      </div>
      <div :if={@events != []} class="space-y-3">
        <div
          :for={event <- @events}
          class="flex gap-3 rounded-3xl border border-zinc-200/80 bg-white px-5 py-4 text-sm dark:border-white/10 dark:bg-white/[0.03]"
        >
          <div class="mt-0.5 shrink-0">
            <span class={event_icon_class(event.event_type)} />
          </div>
          <div class="min-w-0 flex-1">
            <div class="font-medium text-zinc-900 dark:text-white">{event.summary}</div>
            <div
              :if={event.reason && event.reason != ""}
              class="mt-0.5 text-zinc-600 dark:text-zinc-400"
            >
              {event.reason}
            </div>
            <div class="mt-0.5 text-xs text-zinc-400">
              {Calendar.strftime(event.inserted_at, "%b %d, %Y at %H:%M")}
            </div>
          </div>
        </div>
      </div>
    </.section>
    """
  end

  defp event_icon_class(:pursued), do: "inline-block mt-1 size-2 rounded-full bg-success"
  defp event_icon_class(:stage_advanced), do: "inline-block mt-1 size-2 rounded-full bg-primary"
  defp event_icon_class(:closed_won), do: "inline-block mt-1 size-2 rounded-full bg-success"
  defp event_icon_class(:closed_lost), do: "inline-block mt-1 size-2 rounded-full bg-error"
  defp event_icon_class(:parked), do: "inline-block mt-1 size-2 rounded-full bg-warning"
  defp event_icon_class(:passed), do: "inline-block mt-1 size-2 rounded-full bg-error"
  defp event_icon_class(_), do: "inline-block mt-1 size-2 rounded-full bg-base-300"

  defp load_events(opportunity_id) do
    require Ash.Query

    GnomeGarden.Sales.Event
    |> Ash.Query.filter(opportunity_id == ^opportunity_id)
    |> Ash.Query.sort(inserted_at: :desc)
    |> Ash.read!()
  end

  defp stages_for_workflow(:bid_response),
    do: [:discovery, :review, :qualification, :drafting, :submitted]

  defp stages_for_workflow(:outreach),
    do: [:discovery, :research, :outreach, :meeting, :qualification, :proposal, :negotiation]

  defp stages_for_workflow(:inbound),
    do: [:discovery, :qualification, :meeting, :proposal, :negotiation]

  defp stages_for_workflow(_),
    do: [:discovery, :qualification, :proposal, :negotiation]

  defp next_actions(opportunity) do
    workflow = opportunity.workflow
    stage = opportunity.stage
    valid_stages = MapSet.new(stages_for_workflow(workflow))

    all_transitions(stage)
    |> Enum.filter(fn {_label, _action, target} -> MapSet.member?(valid_stages, target) end)
    |> Enum.map(fn {label, action, _target} -> {label, action} end)
  end

  defp all_transitions(:discovery) do
    [
      {"Review Docs", :advance_to_review, :review},
      {"Research", :advance_to_research, :research},
      {"Qualify", :advance_to_qualification, :qualification}
    ]
  end

  defp all_transitions(:review), do: [{"Qualify", :advance_to_qualification, :qualification}]

  defp all_transitions(:research) do
    [
      {"Begin Outreach", :advance_to_outreach, :outreach},
      {"Qualify", :advance_to_qualification, :qualification}
    ]
  end

  defp all_transitions(:outreach) do
    [
      {"Schedule Meeting", :advance_to_meeting, :meeting},
      {"Qualify", :advance_to_qualification, :qualification}
    ]
  end

  defp all_transitions(:meeting) do
    [
      {"Qualify", :advance_to_qualification, :qualification},
      {"Send Proposal", :advance_to_proposal, :proposal}
    ]
  end

  defp all_transitions(:qualification) do
    [
      {"Draft Response", :advance_to_drafting, :drafting},
      {"Schedule Meeting", :advance_to_meeting, :meeting},
      {"Send Proposal", :advance_to_proposal, :proposal}
    ]
  end

  defp all_transitions(:drafting), do: [{"Submit Response", :advance_to_submitted, :submitted}]
  defp all_transitions(:proposal), do: [{"Negotiate", :advance_to_negotiation, :negotiation}]
  defp all_transitions(_), do: []

  defp stage_index(current, stages) do
    Enum.find_index(stages, &(&1 == current)) || -1
  end

  defp format_stage(stage) do
    stage |> to_string() |> String.replace("_", " ") |> String.capitalize()
  end

  defp format_workflow(nil), do: "-"
  defp format_workflow(:bid_response), do: "Bid Response"
  defp format_workflow(:outreach), do: "Outreach"
  defp format_workflow(:inbound), do: "Inbound"

  defp format_workflow(workflow),
    do: workflow |> to_string() |> String.replace("_", " ") |> String.capitalize()

  defp format_weighted(%{amount: nil}), do: "-"
  defp format_weighted(%{amount: _amount, probability: nil}), do: "-"

  defp format_weighted(%{amount: amount, probability: prob}) do
    weighted = Decimal.mult(amount, Decimal.div(Decimal.new(prob), 100))
    "$#{Decimal.to_string(Decimal.round(weighted, 2))}"
  end
end
