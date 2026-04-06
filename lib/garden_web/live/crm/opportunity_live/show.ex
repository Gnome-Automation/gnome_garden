defmodule GnomeGardenWeb.CRM.OpportunityLive.Show do
  use GnomeGardenWeb, :live_view

  import GnomeGardenWeb.CRM.Helpers

  alias GnomeGarden.Sales

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    opportunity = Sales.get_opportunity!(id, actor: socket.assigns.current_user, load: [:company])

    {:ok,
     socket
     |> assign(:page_title, opportunity.name)
     |> assign(:opportunity, opportunity)
     |> assign(:closing, nil)}
  end

  @impl true
  def handle_event("advance", %{"action" => action_name}, socket) do
    opp = socket.assigns.opportunity
    action = String.to_existing_atom(action_name)

    case Ash.update(opp, %{}, action: action) do
      {:ok, updated} ->
        {:noreply,
         socket
         |> assign(:opportunity, Ash.load!(updated, [:company]))
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

  def handle_event("close_won", _, socket) do
    case Ash.update(socket.assigns.opportunity, %{}, action: :close_won) do
      {:ok, updated} ->
        {:noreply,
         socket
         |> assign(:opportunity, Ash.load!(updated, [:company]))
         |> assign(:closing, nil)
         |> put_flash(:info, "Opportunity won!")}

      {:error, error} ->
        {:noreply, put_flash(socket, :error, "Failed: #{inspect(error)}")}
    end
  end

  def handle_event("close_lost", %{"loss_reason" => reason}, socket) do
    case Ash.update(socket.assigns.opportunity, %{loss_reason: reason}, action: :close_lost) do
      {:ok, updated} ->
        {:noreply,
         socket
         |> assign(:opportunity, Ash.load!(updated, [:company]))
         |> assign(:closing, nil)
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
    <.header>
      {@opportunity.name}
      <:subtitle>
        <span :if={@opportunity.company}>
          <.link
            navigate={~p"/crm/companies/#{@opportunity.company}"}
            class="hover:text-emerald-600"
          >
            {@opportunity.company.name}
          </.link>
          <span class="text-zinc-400 mx-1">/</span>
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
    </.header>

    <%!-- Stage progression bar --%>
    <div class="mt-6">
      <div class="flex items-center gap-1">
        <div
          :for={{stage, idx} <- Enum.with_index(@stages)}
          class="flex items-center gap-1"
        >
          <div
            :if={idx > 0}
            class={[
              "h-0.5 w-6",
              if(stage_index(@opportunity.stage, @stages) >= idx,
                do: "bg-emerald-500",
                else: "bg-base-300"
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
                "bg-base-200 text-base-content/50"
            end
          ]}>
            <span :if={stage_index(@opportunity.stage, @stages) > idx} class="text-emerald-500">
              <.icon name="hero-check-mini" class="size-3.5" />
            </span>
            {format_stage(stage)}
          </div>
        </div>

        <%!-- Terminal indicator --%>
        <div :if={@closed?} class="flex items-center gap-1 ml-2">
          <div class="h-0.5 w-6 bg-base-300" />
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
    </div>

    <%!-- Action buttons --%>
    <div :if={!@closed?} class="mt-4 flex flex-wrap gap-2">
      <button
        :for={{label, action} <- @next_actions}
        phx-click="advance"
        phx-value-action={action}
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

    <%!-- Close modal --%>
    <div
      :if={@closing}
      class="fixed inset-0 z-50 flex items-center justify-center bg-black/50"
      phx-window-keydown="cancel_close"
      phx-key="Escape"
    >
      <div class="modal-box w-full max-w-sm bg-base-100 shadow-xl" phx-click-away="cancel_close">
        <%= if @closing == "won" do %>
          <h3 class="font-bold text-lg mb-4">Mark as Won</h3>
          <p class="text-sm text-zinc-500 mb-4">Congratulations! Mark this opportunity as won.</p>
          <div class="modal-action">
            <button phx-click="cancel_close" class="btn btn-ghost">Cancel</button>
            <button phx-click="close_won" class="btn btn-success">Confirm Won</button>
          </div>
        <% else %>
          <h3 class="font-bold text-lg mb-4">Mark as Lost</h3>
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
        <% end %>
      </div>
    </div>

    <%!-- Details grid --%>
    <div class="mt-8 grid grid-cols-1 gap-8 lg:grid-cols-2">
      <div>
        <.heading level={3}>Deal Information</.heading>
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
      </div>

      <div>
        <.heading level={3}>Timeline</.heading>
        <.properties>
          <.property name="Expected Close">
            {format_date(@opportunity.expected_close_date)}
          </.property>
          <.property :if={@opportunity.actual_close_date} name="Actual Close">
            {format_date(@opportunity.actual_close_date)}
          </.property>
          <.property name="Created">{format_datetime(@opportunity.inserted_at)}</.property>
        </.properties>
      </div>
    </div>

    <div :if={@opportunity.description} class="mt-8">
      <.heading level={3}>Description</.heading>
      <p class="mt-2 text-sm text-zinc-600 dark:text-zinc-400 whitespace-pre-wrap">
        {@opportunity.description}
      </p>
    </div>

    <div :if={@opportunity.loss_reason} class="mt-8">
      <.heading level={3}>Loss Reason</.heading>
      <p class="mt-2 text-sm text-error whitespace-pre-wrap">
        {@opportunity.loss_reason}
      </p>
    </div>
    """
  end

  # -- Workflow stage definitions --

  defp stages_for_workflow(:bid_response),
    do: [:discovery, :review, :qualification, :drafting, :submitted]

  defp stages_for_workflow(:outreach),
    do: [:discovery, :research, :outreach, :meeting, :qualification, :proposal, :negotiation]

  defp stages_for_workflow(:inbound),
    do: [:discovery, :qualification, :meeting, :proposal, :negotiation]

  defp stages_for_workflow(_),
    do: [:discovery, :qualification, :proposal, :negotiation]

  # -- Next valid actions for current state + workflow --

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

  defp all_transitions(:review) do
    [{"Qualify", :advance_to_qualification, :qualification}]
  end

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

  defp all_transitions(:drafting) do
    [{"Submit Response", :advance_to_submitted, :submitted}]
  end

  defp all_transitions(:proposal) do
    [{"Negotiate", :advance_to_negotiation, :negotiation}]
  end

  defp all_transitions(_), do: []

  # -- Helpers --

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
  defp format_workflow(w), do: w |> to_string() |> String.replace("_", " ") |> String.capitalize()

  defp format_weighted(%{amount: nil}), do: "-"
  defp format_weighted(%{amount: _amount, probability: nil}), do: "-"

  defp format_weighted(%{amount: amount, probability: prob}) do
    weighted = Decimal.mult(amount, Decimal.div(Decimal.new(prob), 100))
    "$#{Decimal.to_string(Decimal.round(weighted, 2))}"
  end
end
