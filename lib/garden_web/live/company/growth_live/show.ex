defmodule GnomeGardenWeb.Company.GrowthLive.Show do
  use GnomeGardenWeb, :live_view

  import GnomeGardenWeb.Components.OperationsUI,
    only: [related_tasks_panel: 1, playbook_runs_panel: 1]

  import GnomeGardenWeb.Operations.Helpers, only: [format_atom: 1, format_datetime: 1]

  alias GnomeGarden.Company
  alias GnomeGarden.Operations
  alias GnomeGardenWeb.Operations.TaskEntry
  alias GnomeGardenWeb.Operations.TaskPubSub

  # Plain transitions execute immediately; decision transitions (hold,
  # achieve, decline) first prompt for the notes that become the permanent
  # record — they are the only actions that can capture them.
  @plain_transitions [
    {"evaluate", :idea, "Evaluate"},
    {"plan", :idea, "Plan"},
    {"plan", :evaluating, "Plan"},
    {"start", :planned, "Start"},
    {"resume", :on_hold, "Resume"},
    {"reconsider", :declined, "Reconsider"}
  ]

  @decision_transitions [
    {"hold", [:evaluating, :planned, :in_progress], "Hold",
     "Why is this on hold, and what unblocks it?"},
    {"achieve", [:in_progress], "Mark Achieved", "What was the outcome?"},
    {"decline", [:idea, :evaluating, :planned, :on_hold], "Decline",
     "Why is Gnome passing on this?"}
  ]

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    initiative = load_initiative!(id, socket.assigns.current_user)

    if connected?(socket) do
      TaskPubSub.subscribe_related(:company_growth_initiative, initiative.id)
      GnomeGardenWeb.Endpoint.subscribe("growth_initiative_evidence:initiative:#{initiative.id}")
      GnomeGardenWeb.Endpoint.subscribe("playbook_run:growth_initiative:#{initiative.id}")
    end

    {:ok,
     socket
     |> assign(:page_title, initiative.title)
     |> assign(:initiative, initiative)
     |> assign(:pending_decision, nil)
     |> assign_related()
     |> assign_evidence_form()}
  end

  @impl true
  def handle_event("transition", %{"action" => action}, socket) do
    initiative = socket.assigns.initiative
    actor = socket.assigns.current_user

    result =
      case action do
        "evaluate" -> Company.evaluate_growth_initiative(initiative, actor: actor)
        "plan" -> Company.plan_growth_initiative(initiative, %{}, actor: actor)
        "start" -> Company.start_growth_initiative(initiative, actor: actor)
        "resume" -> Company.resume_growth_initiative(initiative, actor: actor)
        "reconsider" -> Company.reconsider_growth_initiative(initiative, actor: actor)
      end

    case result do
      {:ok, updated} ->
        {:noreply,
         socket
         |> put_flash(:info, "Initiative updated")
         |> assign(:initiative, load_initiative!(updated.id, actor))}

      {:error, error} ->
        {:noreply, put_flash(socket, :error, "Could not update initiative: #{inspect(error)}")}
    end
  end

  @impl true
  def handle_event("request_decision", %{"action" => action}, socket) do
    {:noreply, assign(socket, :pending_decision, action)}
  end

  @impl true
  def handle_event("cancel_decision", _params, socket) do
    {:noreply, assign(socket, :pending_decision, nil)}
  end

  @impl true
  def handle_event("confirm_decision", %{"notes" => notes}, socket) do
    initiative = socket.assigns.initiative
    actor = socket.assigns.current_user

    result =
      case socket.assigns.pending_decision do
        "hold" ->
          Company.hold_growth_initiative(initiative, %{decision_notes: notes}, actor: actor)

        "achieve" ->
          Company.achieve_growth_initiative(initiative, %{outcome_notes: notes}, actor: actor)

        "decline" ->
          Company.decline_growth_initiative(initiative, %{decision_notes: notes}, actor: actor)
      end

    case result do
      {:ok, updated} ->
        {:noreply,
         socket
         |> put_flash(:info, "Decision recorded")
         |> assign(:pending_decision, nil)
         |> assign(:initiative, load_initiative!(updated.id, actor))}

      {:error, error} ->
        {:noreply, put_flash(socket, :error, "Could not record decision: #{inspect(error)}")}
    end
  end

  @impl true
  def handle_event("validate_evidence", %{"form" => params}, socket) do
    form = AshPhoenix.Form.validate(socket.assigns.evidence_form, params)
    {:noreply, assign(socket, evidence_form: to_form(form))}
  end

  @impl true
  def handle_event("add_evidence", %{"form" => params}, socket) do
    params = Map.put(params, "growth_initiative_id", socket.assigns.initiative.id)

    case AshPhoenix.Form.submit(socket.assigns.evidence_form, params: params) do
      {:ok, _evidence} ->
        {:noreply,
         socket
         |> put_flash(:info, "Evidence recorded")
         |> assign_related()
         |> assign_evidence_form()}

      {:error, form} ->
        {:noreply, assign(socket, evidence_form: to_form(form))}
    end
  end

  @impl true
  def handle_event("apply_playbook", %{"playbook_id" => playbook_id}, socket) do
    case Operations.apply_playbook(
           %{
             playbook_id: playbook_id,
             company_growth_initiative_id: socket.assigns.initiative.id
           },
           actor: socket.assigns.current_user
         ) do
      {:ok, run} ->
        {:noreply,
         socket
         |> put_flash(:info, "Applied playbook: #{run.playbook_name}")
         |> assign_related()}

      {:error, error} ->
        {:noreply, put_flash(socket, :error, "Could not apply playbook: #{inspect(error)}")}
    end
  end

  @impl true
  def handle_info(%{topic: "task:company_growth_initiative:" <> _id}, socket) do
    {:noreply, assign_related(socket)}
  end

  @impl true
  def handle_info(%{topic: "growth_initiative_evidence:initiative:" <> _id}, socket) do
    {:noreply, assign_related(socket)}
  end

  @impl true
  def handle_info(%{topic: "playbook_run:growth_initiative:" <> _id}, socket) do
    {:noreply, assign_related(socket)}
  end

  @impl true
  def render(assigns) do
    assigns =
      assigns
      |> assign(:plain_transitions, @plain_transitions)
      |> assign(:decision_transitions, @decision_transitions)

    ~H"""
    <.page max_width="max-w-5xl" class="pb-8">
      <.page_header eyebrow="Company Growth">
        {@initiative.title}
        <:subtitle>
          <span class="inline-flex items-center gap-2">
            <.status_badge status={@initiative.status_variant}>
              {format_atom(@initiative.status)}
            </.status_badge>
            <span>{format_atom(@initiative.category)}</span>
            <span :if={@initiative.target_date}>· target {@initiative.target_date}</span>
          </span>
        </:subtitle>
        <:actions>
          <.button navigate={~p"/company/growth"}>
            Back
          </.button>
          <.button
            :if={@initiative.status not in [:achieved, :declined]}
            navigate={~p"/company/growth/#{@initiative}/edit"}
          >
            Edit
          </.button>
          <.button
            :for={{action, from, label} <- @plain_transitions}
            :if={@initiative.status == from}
            phx-click="transition"
            phx-value-action={action}
            variant={if(action in ["start", "plan"], do: "primary")}
          >
            {label}
          </.button>
          <.button
            :for={{action, from_states, label, _prompt} <- @decision_transitions}
            :if={@initiative.status in from_states}
            phx-click="request_decision"
            phx-value-action={action}
            variant={if(action == "achieve", do: "primary")}
          >
            {label}
          </.button>
        </:actions>
      </.page_header>

      <.section
        :for={{action, _from, label, prompt} <- @decision_transitions}
        :if={@pending_decision == action}
        title={label}
        description={prompt}
      >
        <form id="decision-form" phx-submit="confirm_decision" class="space-y-4">
          <textarea
            id="decision-notes"
            name="notes"
            rows="3"
            required
            class="block w-full rounded-md bg-white px-3 py-1.5 text-sm text-gray-900 outline-1 -outline-offset-1 outline-gray-300 focus:outline-2 focus:-outline-offset-2 focus:outline-emerald-600 dark:bg-white/5 dark:text-white dark:outline-white/10"
          ></textarea>
          <div class="flex items-center gap-3">
            <.button type="submit" variant="primary">Confirm {label}</.button>
            <.button type="button" phx-click="cancel_decision">Cancel</.button>
          </div>
        </form>
      </.section>

      <div class="grid gap-6 lg:grid-cols-2">
        <.section title="Why">
          <p class="whitespace-pre-wrap text-sm leading-6 text-base-content/70">
            {@initiative.description || "No description yet."}
          </p>
          <.properties>
            <.property name="Expected benefit">{@initiative.expected_benefit || "-"}</.property>
            <.property name="Effort estimate">{@initiative.effort_estimate || "-"}</.property>
            <.property name="Owner">
              {(@initiative.owner_team_member && @initiative.owner_team_member.display_name) ||
                "Unassigned"}
            </.property>
          </.properties>
        </.section>

        <.section title="Decision Record">
          <.properties>
            <.property name="Captured">{format_datetime(@initiative.inserted_at)}</.property>
            <.property name="Achieved">{format_datetime(@initiative.achieved_at)}</.property>
            <.property name="Declined">{format_datetime(@initiative.declined_at)}</.property>
            <.property name="Decision notes">{@initiative.decision_notes || "-"}</.property>
            <.property name="Outcome notes">{@initiative.outcome_notes || "-"}</.property>
          </.properties>
        </.section>
      </div>

      <.section
        :if={@linked_source}
        title="Source Activation"
        description="Activated means the source's own derived state — first successful scan, not account creation."
      >
        <.properties>
          <.property name="Source">{@linked_source.name}</.property>
          <.property name="Onboarding state">
            <.status_badge status={
              if(@linked_source.onboarding_state == :active, do: :success, else: :warning)
            }>
              {format_atom(@linked_source.onboarding_state)}
            </.status_badge>
          </.property>
          <.property name="Last scanned">
            {format_datetime(@linked_source.last_scanned_at)}
          </.property>
        </.properties>
      </.section>

      <.section
        title="Evidence"
        description="Which bids exposed this gap — what they required versus what Gnome had."
        body_class="p-0"
      >
        <div :if={@evidence == []} class="p-4">
          <.empty_state
            icon="hero-document-magnifying-glass"
            title="No evidence linked"
            description="Link the bids that motivated this initiative."
          />
        </div>
        <div :if={@evidence != []} class="divide-y divide-zinc-200 dark:divide-white/10">
          <div :for={item <- @evidence} class="px-4 py-3">
            <div class="flex flex-wrap items-center gap-2 text-xs">
              <.tag color={:amber}>{format_atom(item.gap_category)}</.tag>
              <span class="text-base-content/50">{format_atom(item.confidence)} confidence</span>
              <span :if={item.bid} class="text-base-content/60">bid: {item.bid.title}</span>
            </div>
            <p :if={item.quoted_requirement} class="mt-1 text-sm text-base-content/80">
              "{item.quoted_requirement}"
            </p>
            <p :if={item.observed_value || item.required_value} class="text-xs text-base-content/50">
              have {item.observed_value || "?"} · need {item.required_value || "?"}
            </p>
            <p :if={item.note} class="text-xs text-base-content/60">{item.note}</p>
          </div>
        </div>

        <div class="border-t border-zinc-200 p-4 dark:border-white/10">
          <.form
            for={@evidence_form}
            id="evidence-form"
            phx-change="validate_evidence"
            phx-submit="add_evidence"
            class="grid grid-cols-1 gap-4 sm:grid-cols-6"
          >
            <div class="sm:col-span-2">
              <.input
                field={@evidence_form[:gap_category]}
                type="select"
                label="Gap"
                options={gap_options()}
              />
            </div>
            <div class="sm:col-span-2">
              <.input
                field={@evidence_form[:bid_id]}
                type="select"
                label="Bid"
                prompt="None"
                options={Enum.map(@recent_bids, &{&1.title, &1.id})}
              />
            </div>
            <div class="sm:col-span-2">
              <.input
                field={@evidence_form[:confidence]}
                type="select"
                label="Confidence"
                options={[{"Low", :low}, {"Medium", :medium}, {"High", :high}]}
              />
            </div>
            <div class="sm:col-span-3">
              <.input field={@evidence_form[:quoted_requirement]} label="Quoted requirement" />
            </div>
            <div class="sm:col-span-3">
              <.input field={@evidence_form[:note]} label="Note" />
            </div>
            <div class="sm:col-span-3">
              <.input field={@evidence_form[:observed_value]} label="What Gnome had" />
            </div>
            <div class="sm:col-span-3">
              <.input field={@evidence_form[:required_value]} label="What the bid required" />
            </div>
            <div class="col-span-full">
              <.button type="submit">Add Evidence</.button>
            </div>
          </.form>
        </div>
      </.section>

      <.related_tasks_panel
        tasks={@related_tasks}
        description="Execution work delivering this initiative."
        empty_description="Create tasks or apply a playbook to start delivery."
        new_task_path={new_initiative_task_path(@initiative)}
      />

      <.playbook_runs_panel
        runs={@playbook_runs}
        playbooks={@playbooks}
        description="Apply a playbook to spawn this initiative's task set."
      />
    </.page>
    """
  end

  defp assign_related(socket) do
    actor = socket.assigns.current_user
    initiative = socket.assigns.initiative

    {:ok, evidence} = Company.list_growth_initiative_evidence(initiative.id, actor: actor)

    {:ok, tasks} =
      Operations.list_tasks_by_growth_initiative(initiative.id,
        actor: actor,
        load: [:status_variant, :priority_variant]
      )

    {:ok, runs} = Operations.list_playbook_runs_for_growth_initiative(initiative.id, actor: actor)

    playbooks =
      case Operations.list_active_playbooks(actor: actor) do
        {:ok, playbooks} -> playbooks
        {:error, _error} -> []
      end

    # Closed bids included deliberately: lost and rejected bids are exactly
    # the receipts this evidence workflow captures.
    {:ok, recent_bids} = GnomeGarden.Procurement.list_recent_bids_for_evidence(actor: actor)

    socket
    |> assign(:evidence, evidence)
    |> assign(:related_tasks, tasks)
    |> assign(:playbook_runs, runs)
    |> assign(:playbooks, playbooks)
    |> assign(:recent_bids, recent_bids)
    |> assign(:linked_source, load_linked_source(initiative, actor))
  end

  defp assign_evidence_form(socket) do
    form =
      AshPhoenix.Form.for_create(Company.GrowthInitiativeEvidence, :create,
        actor: socket.assigns.current_user,
        domain: Company,
        params: %{"growth_initiative_id" => socket.assigns.initiative.id}
      )

    assign(socket, :evidence_form, to_form(form))
  end

  defp new_initiative_task_path(initiative) do
    TaskEntry.new_task_path(%{
      title: "#{initiative.title}: ",
      task_type: :other,
      origin_domain: :operations,
      origin_resource: "growth_initiative",
      origin_id: initiative.id,
      origin_label: initiative.title,
      origin_url: "/company/growth/#{initiative.id}",
      company_growth_initiative_id: initiative.id,
      return_to: "/company/growth/#{initiative.id}"
    })
  end

  defp load_linked_source(%{procurement_source_id: nil}, _actor), do: nil

  defp load_linked_source(%{procurement_source_id: source_id}, actor) do
    case GnomeGarden.Procurement.get_procurement_source(source_id,
           actor: actor,
           load: [:onboarding_state]
         ) do
      {:ok, source} -> source
      {:error, _error} -> nil
    end
  end

  defp gap_options do
    [
      {"Missing certification", :missing_certification},
      {"Bond capacity", :bond_capacity},
      {"License class", :license_class},
      {"Insurance limit", :insurance_limit},
      {"Tech platform", :tech_platform},
      {"Other", :other}
    ]
  end

  defp load_initiative!(id, actor) do
    case Company.get_growth_initiative(id,
           actor: actor,
           load: [:status_variant, :owner_team_member, :evidence_count]
         ) do
      {:ok, initiative} -> initiative
      {:error, error} -> raise "failed to load growth initiative #{id}: #{inspect(error)}"
    end
  end
end
