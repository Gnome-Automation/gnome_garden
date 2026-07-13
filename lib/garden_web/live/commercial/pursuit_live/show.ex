defmodule GnomeGardenWeb.Commercial.PursuitLive.Show do
  use GnomeGardenWeb, :live_view

  import GnomeGardenWeb.Commercial.Helpers
  import GnomeGardenWeb.Components.OperationsUI, only: [playbook_runs_panel: 1]

  alias GnomeGarden.{Commercial, Operations}
  alias GnomeGardenWeb.Operations.TaskEntry
  alias GnomeGardenWeb.Operations.TaskPubSub

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    pursuit = load_pursuit!(id, socket.assigns.current_user)

    if connected?(socket) do
      TaskPubSub.subscribe_related(:pursuit, pursuit.id)
      GnomeGardenWeb.Endpoint.subscribe("playbook_run:pursuit:#{pursuit.id}")
    end

    {:ok,
     socket
     |> assign(:page_title, pursuit.name)
     |> assign(:pursuit, pursuit)
     |> assign_playbook_context()}
  end

  @impl true
  def handle_event("apply_playbook", %{"playbook_id" => playbook_id}, socket) do
    case Operations.apply_playbook(
           %{playbook_id: playbook_id, pursuit_id: socket.assigns.pursuit.id},
           actor: socket.assigns.current_user
         ) do
      {:ok, run} ->
        {:noreply,
         socket
         |> put_flash(:info, "Applied playbook: #{run.playbook_name}")
         |> assign_playbook_context()}

      {:error, error} ->
        {:noreply, put_flash(socket, :error, "Could not apply playbook: #{inspect(error)}")}
    end
  end

  @impl true
  def handle_event("transition", %{"action" => action}, socket) do
    pursuit = socket.assigns.pursuit

    case transition_pursuit(pursuit, String.to_existing_atom(action), socket.assigns.current_user) do
      {:ok, updated_pursuit} ->
        {:noreply,
         socket
         |> assign(:pursuit, load_pursuit!(updated_pursuit.id, socket.assigns.current_user))
         |> put_flash(:info, "Pursuit updated")}

      {:error, error} ->
        {:noreply, put_flash(socket, :error, "Could not update pursuit: #{inspect(error)}")}
    end
  end

  @impl true
  def handle_event("task_transition", %{"id" => task_id, "action" => action}, socket) do
    pursuit = socket.assigns.pursuit

    with {:ok, task} <- pursuit_task(pursuit, task_id),
         {:ok, _task} <- transition_task(task, action, socket.assigns.current_user) do
      {:noreply,
       socket
       |> assign(:pursuit, load_pursuit!(pursuit.id, socket.assigns.current_user))
       |> put_flash(:info, "Task updated")}
    else
      {:error, error} ->
        {:noreply, put_flash(socket, :error, "Could not update task: #{inspect(error)}")}
    end
  end

  @impl true
  def handle_event("create_quick_task", %{"kind" => kind}, socket) do
    pursuit = socket.assigns.pursuit

    case create_quick_task(pursuit, kind, socket.assigns.current_user) do
      {:ok, _task} ->
        {:noreply,
         socket
         |> assign(:pursuit, load_pursuit!(pursuit.id, socket.assigns.current_user))
         |> put_flash(:info, "Next-step task created")}

      {:error, error} ->
        {:noreply, put_flash(socket, :error, "Could not create task: #{inspect(error)}")}
    end
  end

  @impl true
  def handle_info(%{topic: "task:pursuit:" <> _pursuit_id}, socket) do
    {:noreply,
     socket
     |> assign(
       :pursuit,
       load_pursuit!(socket.assigns.pursuit.id, socket.assigns.current_user)
     )
     |> assign_playbook_context()}
  end

  @impl true
  def handle_info(%{topic: "playbook_run:pursuit:" <> _pursuit_id}, socket) do
    {:noreply, assign_playbook_context(socket)}
  end

  defp assign_playbook_context(socket) do
    actor = socket.assigns.current_user
    pursuit = socket.assigns.pursuit

    socket
    |> assign(:playbooks, list_active_playbooks(actor))
    |> assign(:playbook_runs, list_runs(pursuit.id, actor))
  end

  defp list_active_playbooks(actor) do
    case Operations.list_active_playbooks(actor: actor) do
      {:ok, playbooks} -> playbooks
      {:error, _error} -> []
    end
  end

  defp list_runs(pursuit_id, actor) do
    case Operations.list_playbook_runs_for_pursuit(pursuit_id, actor: actor) do
      {:ok, runs} -> runs
      {:error, error} -> raise "failed to load playbook runs: #{inspect(error)}"
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.page class="pb-8">
      <.page_header eyebrow="Commercial">
        {@pursuit.name}
        <:subtitle>
          <span class="inline-flex items-center gap-2">
            <.status_badge status={@pursuit.stage_variant}>
              {format_atom(@pursuit.stage)}
            </.status_badge>
            <span class="text-base-content/40">/</span>
            <span>
              {(@pursuit.organization && @pursuit.organization.name) || "No organization linked"}
            </span>
          </span>
        </:subtitle>
        <:actions>
          <.button navigate={~p"/commercial/pursuits"}>
            Back
          </.button>
          <.button
            :if={can_create_proposal?(@pursuit)}
            navigate={~p"/commercial/proposals/new?pursuit_id=#{@pursuit.id}"}
            variant="primary"
          >
            Create Proposal
          </.button>
          <.button navigate={~p"/commercial/pursuits/#{@pursuit}/edit"}>
            Edit
          </.button>
        </:actions>
      </.page_header>

      <.pursuit_next_steps pursuit={@pursuit} new_task_path={new_pursuit_task_path(@pursuit)} />

      <.playbook_runs_panel
        runs={@playbook_runs}
        playbooks={@playbooks}
        description="Apply a playbook to spawn this pursuit's standard task set."
      />

      <.section
        title="Stage Actions"
        description="Advance only with clear intent so the pipeline stays operationally meaningful."
      >
        <div class="flex flex-wrap gap-3">
          <.button
            :for={action <- pursuit_actions(@pursuit)}
            phx-click="transition"
            phx-value-action={action.action}
            variant={action.variant}
          >
            <.icon name={action.icon} class="size-4" /> {action.label}
          </.button>
        </div>
      </.section>

      <.section
        :if={referral_pursuit?(@pursuit)}
        title="Lead Workspace"
        description="Referral contacts, facilities, and suspected needs that should guide the next operator move."
      >
        <div class="grid gap-6 lg:grid-cols-2">
          <div>
            <p class="text-xs font-semibold uppercase tracking-[0.2em] text-base-content/40">
              Contacts
            </p>
            <div class="mt-3 space-y-3">
              <div
                :for={contact <- pursuit_contacts(@pursuit)}
                class="rounded-2xl border border-base-300/70 bg-base-100/70 px-4 py-3 dark:border-white/10 dark:bg-white/[0.03]"
              >
                <p class="font-medium text-base-content">{contact_name(contact)}</p>
                <p class="text-sm text-base-content/60">{to_string(contact.email || "No email")}</p>
                <p class="text-xs text-base-content/45">
                  {[contact.phone, contact.mobile] |> Enum.reject(&is_nil/1) |> Enum.join(" · ")}
                </p>
              </div>
              <.empty_state
                :if={pursuit_contacts(@pursuit) == []}
                icon="hero-user-group"
                title="No contacts linked"
                description="Add known stakeholders before deeper pursuit work."
              />
            </div>
          </div>

          <div>
            <p class="text-xs font-semibold uppercase tracking-[0.2em] text-base-content/40">
              Sites
            </p>
            <div class="mt-3 space-y-3">
              <div
                :for={site <- pursuit_sites(@pursuit)}
                class="rounded-2xl border border-base-300/70 bg-base-100/70 px-4 py-3 dark:border-white/10 dark:bg-white/[0.03]"
              >
                <p class="font-medium text-base-content">{site.name}</p>
                <p class="text-sm text-base-content/60">
                  {[site.city, site.state, site.postal_code]
                  |> Enum.reject(&is_nil/1)
                  |> Enum.join(", ")}
                </p>
              </div>
              <.empty_state
                :if={pursuit_sites(@pursuit) == []}
                icon="hero-building-office-2"
                title="No sites linked"
                description="Known facilities will appear here as they are added."
              />
            </div>
          </div>
        </div>

        <div
          :if={referral_suspected_needs(@pursuit) != []}
          class="mt-6 rounded-2xl border border-emerald-200 bg-emerald-50/70 px-4 py-4 dark:border-emerald-400/20 dark:bg-emerald-400/10"
        >
          <p class="text-xs font-semibold uppercase tracking-[0.2em] text-emerald-700 dark:text-emerald-200">
            Suspected Needs
          </p>
          <div class="mt-3 flex flex-wrap gap-2">
            <span
              :for={need <- referral_suspected_needs(@pursuit)}
              class="rounded-full bg-white/80 px-3 py-1 text-xs font-semibold text-emerald-800 shadow-sm dark:bg-white/10 dark:text-emerald-100"
            >
              {need}
            </span>
          </div>
        </div>
      </.section>

      <div class="grid gap-6 lg:grid-cols-2">
        <.section title="Commercial Snapshot">
          <div class="grid gap-5 sm:grid-cols-2">
            <.property_item label="Pursuit Type" value={format_atom(@pursuit.pursuit_type)} />
            <.property_item label="Priority" value={format_atom(@pursuit.priority)} />
            <.property_item label="Probability" value={"#{@pursuit.probability}%"} />
            <.property_item label="Target Value" value={format_amount(@pursuit.target_value)} />
            <.property_item label="Weighted Value" value={format_amount(@pursuit.weighted_value)} />
            <.property_item label="Expected Close" value={format_date(@pursuit.expected_close_on)} />
          </div>
        </.section>

        <.section title="Delivery Fit">
          <div class="grid gap-5 sm:grid-cols-2">
            <.property_item label="Delivery Model" value={format_atom(@pursuit.delivery_model)} />
            <.property_item label="Billing Model" value={format_atom(@pursuit.billing_model)} />
            <.property_item
              label="Source Signal"
              value={(@pursuit.signal && @pursuit.signal.title) || "-"}
            />
            <.property_item
              label="Proposal Count"
              value={Integer.to_string(@pursuit.proposal_count || 0)}
            />
          </div>
        </.section>
      </div>

      <.section :if={@pursuit.description} title="Description">
        <p class="whitespace-pre-wrap text-sm leading-6 text-base-content/70">
          {@pursuit.description}
        </p>
      </.section>

      <.section :if={@pursuit.notes} title="Notes">
        <p class="whitespace-pre-wrap text-sm leading-6 text-base-content/70">
          {@pursuit.notes}
        </p>
      </.section>

      <.section
        :if={@pursuit.signal}
        title="Signal Origin"
        description="Every pursuit should trace back to a concrete signal that justified the work."
      >
        <.link
          navigate={~p"/commercial/signals/#{@pursuit.signal}"}
          class="flex items-center justify-between rounded-2xl border border-zinc-200 bg-zinc-50/70 px-4 py-4 transition hover:border-emerald-300 hover:bg-white dark:border-white/10 dark:bg-white/[0.03] dark:hover:border-emerald-400/40"
        >
          <div class="space-y-1">
            <p class="font-medium text-base-content">{@pursuit.signal.title}</p>
            <p class="text-sm text-base-content/50">
              {format_atom(@pursuit.signal.signal_type)}
            </p>
          </div>
          <.status_badge status={@pursuit.signal.status_variant}>
            {format_atom(@pursuit.signal.status)}
          </.status_badge>
        </.link>
      </.section>

      <.section
        title="Proposals"
        description="Qualified and priced pursuits should become explicit proposal records before they become agreements."
      >
        <div :if={Enum.empty?(@pursuit.proposals || [])}>
          <.empty_state
            icon="hero-document-text"
            title="No proposals yet"
            description="Create the first proposal once this pursuit has enough scope and pricing clarity."
          />
        </div>

        <div :if={!Enum.empty?(@pursuit.proposals || [])} class="space-y-3">
          <.link
            :for={proposal <- @pursuit.proposals}
            navigate={~p"/commercial/proposals/#{proposal}"}
            class="flex items-center justify-between rounded-2xl border border-zinc-200 bg-zinc-50/70 px-4 py-4 transition hover:border-emerald-300 hover:bg-white dark:border-white/10 dark:bg-white/[0.03] dark:hover:border-emerald-400/40"
          >
            <div class="space-y-1">
              <p class="font-medium text-base-content">{proposal.name}</p>
              <p class="text-sm text-base-content/50">
                {proposal.proposal_number || "No proposal number"}
              </p>
            </div>
            <.status_badge status={proposal.status_variant}>
              {format_atom(proposal.status)}
            </.status_badge>
          </.link>
        </div>
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

  attr :pursuit, :map, required: true
  attr :new_task_path, :string, required: true

  defp pursuit_next_steps(assigns) do
    ~H"""
    <.section
      title="Pursuit Next Steps"
      description="Create and advance the human follow-up needed to keep this opportunity moving."
    >
      <:actions>
        <.button href={@new_task_path} variant="primary">
          New Task
        </.button>
      </:actions>
      <div class="grid gap-6 lg:grid-cols-[20rem,minmax(0,1fr)]">
        <div class="rounded-2xl border border-base-300/70 bg-base-100/70 p-4 dark:border-white/10 dark:bg-white/[0.03]">
          <p class="text-xs font-semibold uppercase tracking-[0.2em] text-base-content/40">
            Quick Tasks
          </p>
          <div class="mt-4 grid gap-2">
            <.button
              id="quick-task-research"
              phx-click="create_quick_task"
              phx-value-kind="research"
              class="justify-start"
            >
              <.icon name="hero-magnifying-glass" class="size-4" /> Research context
            </.button>
            <.button
              id="quick-task-email"
              phx-click="create_quick_task"
              phx-value-kind="email"
              class="justify-start"
            >
              <.icon name="hero-envelope" class="size-4" /> Draft follow-up email
            </.button>
            <.button
              id="quick-task-call"
              phx-click="create_quick_task"
              phx-value-kind="call"
              class="justify-start"
            >
              <.icon name="hero-phone" class="size-4" /> Confirm scope and timing
            </.button>
          </div>
        </div>

        <div class="space-y-3">
          <div
            :for={task <- pursuit_task_actions(@pursuit)}
            id={"pursuit-task-action-#{task.id}"}
            class="rounded-2xl border border-base-300/70 bg-base-100/70 p-4 dark:border-white/10 dark:bg-white/[0.03]"
          >
            <div class="flex flex-col gap-3 sm:flex-row sm:items-start sm:justify-between">
              <div class="min-w-0 space-y-2">
                <div class="flex flex-wrap items-center gap-2">
                  <.status_badge status={task.status_variant}>
                    {format_atom(task.status)}
                  </.status_badge>
                  <.status_badge status={task.priority_variant}>
                    {format_atom(task.priority)}
                  </.status_badge>
                  <span class="text-xs text-base-content/45">{format_atom(task.task_type)}</span>
                </div>
                <div>
                  <p class="font-medium text-base-content">{task.title}</p>
                  <p :if={task.description} class="mt-1 text-sm leading-5 text-base-content/60">
                    {task.description}
                  </p>
                </div>
              </div>

              <div class="flex shrink-0 flex-wrap gap-2">
                <.button
                  :if={task.status in [:pending, :blocked]}
                  id={"start-task-#{task.id}"}
                  phx-click="task_transition"
                  phx-value-id={task.id}
                  phx-value-action="start"
                  variant="primary"
                >
                  Start
                </.button>
                <.button
                  :if={task.status == :in_progress}
                  id={"complete-task-#{task.id}"}
                  phx-click="task_transition"
                  phx-value-id={task.id}
                  phx-value-action="complete"
                  variant="primary"
                >
                  Complete
                </.button>
                <.button
                  :if={task.status in [:pending, :in_progress]}
                  id={"block-task-#{task.id}"}
                  phx-click="task_transition"
                  phx-value-id={task.id}
                  phx-value-action="block"
                >
                  Block
                </.button>
                <.button
                  :if={task.status in [:completed, :cancelled]}
                  id={"reopen-task-#{task.id}"}
                  phx-click="task_transition"
                  phx-value-id={task.id}
                  phx-value-action="reopen"
                >
                  Reopen
                </.button>
              </div>
            </div>
          </div>

          <.empty_state
            :if={pursuit_task_actions(@pursuit) == []}
            icon="hero-check-circle"
            title="No pursuit tasks"
            description="Use a quick task or New Task when this pursuit needs an operator move."
          />
        </div>
      </div>
    </.section>
    """
  end

  defp load_pursuit!(id, actor) do
    case Commercial.get_pursuit_workspace(id, actor: actor) do
      {:ok, pursuit} -> pursuit
      {:error, error} -> raise "failed to load pursuit #{id}: #{inspect(error)}"
    end
  end

  defp pursuit_task_actions(%{tasks: tasks}) when is_list(tasks), do: tasks

  defp pursuit_task_actions(_pursuit), do: []

  defp pursuit_task(%{tasks: tasks}, task_id) when is_list(tasks) do
    case Enum.find(tasks, &(&1.id == task_id)) do
      nil -> {:error, :task_not_found}
      task -> {:ok, task}
    end
  end

  defp pursuit_task(_pursuit, _task_id), do: {:error, :task_not_found}

  defp transition_task(task, "start", actor), do: Operations.start_task(task, actor: actor)
  defp transition_task(task, "complete", actor), do: Operations.complete_task(task, actor: actor)
  defp transition_task(task, "reopen", actor), do: Operations.reopen_task(task, actor: actor)

  defp transition_task(task, "block", actor) do
    Operations.block_task(task, %{blocked_reason: "Blocked from pursuit workspace"}, actor: actor)
  end

  defp transition_task(_task, _action, _actor), do: {:error, :unknown_task_action}

  defp create_quick_task(pursuit, kind, actor) do
    with {:ok, quick_attrs} <- quick_task_attrs(pursuit, kind) do
      attrs =
        quick_attrs
        |> Enum.reject(fn {_key, value} -> is_nil(value) or value == "" end)
        |> Map.new()

      Operations.create_task_from_pursuit(attrs, actor: actor)
    end
  end

  defp quick_task_attrs(pursuit, "research") do
    {:ok,
     base_quick_task_attrs(pursuit, %{
       title: "Research context: #{pursuit.name}",
       description:
         "Collect likely controls, validation, facilities, and plant-floor context before the next outreach.",
       task_type: :research,
       priority: :normal
     })}
  end

  defp quick_task_attrs(pursuit, "email") do
    {:ok,
     base_quick_task_attrs(pursuit, %{
       title: "Draft follow-up email: #{pursuit.name}",
       description:
         "Draft a concise follow-up that confirms fit, suspected needs, and the next practical conversation.",
       task_type: :email,
       priority: :high
     })}
  end

  defp quick_task_attrs(pursuit, "call") do
    {:ok,
     base_quick_task_attrs(pursuit, %{
       title: "Confirm scope and timing: #{pursuit.name}",
       description:
         "Confirm active scope, timeline, decision process, and who should join the technical conversation.",
       task_type: :call,
       priority: :high
     })}
  end

  defp quick_task_attrs(_pursuit, _kind), do: {:error, :unknown_quick_task_kind}

  defp base_quick_task_attrs(pursuit, attrs) do
    Map.merge(attrs, %{
      pursuit_id: pursuit.id,
      signal_id: pursuit.signal_id,
      organization_id: pursuit.organization_id,
      origin_id: pursuit.id,
      origin_label: pursuit.name,
      origin_url: ~p"/commercial/pursuits/#{pursuit}"
    })
  end

  defp new_pursuit_task_path(pursuit) do
    TaskEntry.new_task_path(%{
      title: "Follow up: #{pursuit.name}",
      task_type: :proposal,
      origin_domain: :commercial,
      origin_resource: "pursuit",
      origin_id: pursuit.id,
      origin_label: pursuit.name,
      origin_url: ~p"/commercial/pursuits/#{pursuit}",
      pursuit_id: pursuit.id,
      signal_id: pursuit.signal_id,
      organization_id: pursuit.organization_id,
      return_to: ~p"/commercial/pursuits/#{pursuit}"
    })
  end

  defp can_create_proposal?(pursuit),
    do: pursuit.stage in [:qualified, :estimating, :proposed, :negotiating, :won, :reopened]

  defp referral_pursuit?(%{signal: signal}) when not is_nil(signal) do
    signal.source_channel == :referral or
      metadata_value(signal.metadata, :intake_kind) == "manual_referral"
  end

  defp referral_pursuit?(_pursuit), do: false

  defp pursuit_contacts(%{organization: %{people: people}}) when is_list(people), do: people
  defp pursuit_contacts(_pursuit), do: []

  defp pursuit_sites(%{organization: %{sites: sites}}) when is_list(sites), do: sites
  defp pursuit_sites(_pursuit), do: []

  defp referral_suspected_needs(%{signal: signal}) when not is_nil(signal) do
    signal.metadata
    |> metadata_value(:suspected_needs)
    |> List.wrap()
    |> Enum.reject(&is_nil/1)
  end

  defp referral_suspected_needs(_pursuit), do: []

  defp contact_name(contact) do
    case Map.get(contact, :full_name) do
      name when is_binary(name) and name != "" -> name
      _ -> to_string(contact.email || "Unknown contact")
    end
  end

  defp metadata_value(map, key) when is_map(map) do
    Map.get(map, key) || Map.get(map, to_string(key))
  end

  defp metadata_value(_map, _key), do: nil

  defp pursuit_actions(%{stage: :new}) do
    [
      %{action: "qualify", label: "Qualify", icon: "hero-check-badge", variant: "primary"},
      %{action: "archive", label: "Archive", icon: "hero-archive-box", variant: nil}
    ]
  end

  defp pursuit_actions(%{stage: :reopened}) do
    [
      %{action: "qualify", label: "Re-qualify", icon: "hero-check-badge", variant: "primary"},
      %{action: "archive", label: "Archive", icon: "hero-archive-box", variant: nil}
    ]
  end

  defp pursuit_actions(%{stage: :qualified}) do
    [
      %{action: "estimate", label: "Start Estimate", icon: "hero-calculator", variant: nil},
      %{
        action: "propose",
        label: "Move To Proposal",
        icon: "hero-document-check",
        variant: "primary"
      },
      %{action: "mark_lost", label: "Mark Lost", icon: "hero-x-circle", variant: nil}
    ]
  end

  defp pursuit_actions(%{stage: :estimating}) do
    [
      %{
        action: "propose",
        label: "Move To Proposal",
        icon: "hero-document-check",
        variant: "primary"
      },
      %{action: "mark_lost", label: "Mark Lost", icon: "hero-x-circle", variant: nil}
    ]
  end

  defp pursuit_actions(%{stage: :proposed}) do
    [
      %{
        action: "negotiate",
        label: "Enter Negotiation",
        icon: "hero-arrows-right-left",
        variant: nil
      },
      %{action: "mark_won", label: "Mark Won", icon: "hero-trophy", variant: "primary"},
      %{action: "mark_lost", label: "Mark Lost", icon: "hero-x-circle", variant: nil}
    ]
  end

  defp pursuit_actions(%{stage: :negotiating}) do
    [
      %{action: "mark_won", label: "Mark Won", icon: "hero-trophy", variant: "primary"},
      %{action: "mark_lost", label: "Mark Lost", icon: "hero-x-circle", variant: nil}
    ]
  end

  defp pursuit_actions(%{stage: :lost}) do
    [
      %{action: "reopen", label: "Reopen", icon: "hero-arrow-path", variant: "primary"},
      %{action: "archive", label: "Archive", icon: "hero-archive-box", variant: nil}
    ]
  end

  defp pursuit_actions(%{stage: :archived}) do
    [
      %{action: "reopen", label: "Reopen", icon: "hero-arrow-path", variant: "primary"}
    ]
  end

  defp pursuit_actions(_pursuit), do: []

  defp transition_pursuit(pursuit, :qualify, actor),
    do: Commercial.qualify_pursuit(pursuit, actor: actor)

  defp transition_pursuit(pursuit, :estimate, actor),
    do: Commercial.estimate_pursuit(pursuit, actor: actor)

  defp transition_pursuit(pursuit, :propose, actor),
    do: Commercial.propose_pursuit(pursuit, actor: actor)

  defp transition_pursuit(pursuit, :negotiate, actor),
    do: Commercial.negotiate_pursuit(pursuit, actor: actor)

  defp transition_pursuit(pursuit, :mark_won, actor),
    do: Commercial.win_pursuit(pursuit, actor: actor)

  defp transition_pursuit(pursuit, :mark_lost, actor),
    do: Commercial.lose_pursuit(pursuit, actor: actor)

  defp transition_pursuit(pursuit, :archive, actor),
    do: Commercial.archive_pursuit(pursuit, actor: actor)

  defp transition_pursuit(pursuit, :reopen, actor),
    do: Commercial.reopen_pursuit(pursuit, actor: actor)
end
