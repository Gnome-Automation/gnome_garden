defmodule GnomeGardenWeb.Commercial.PursuitLive.Show do
  use GnomeGardenWeb, :live_view

  import GnomeGardenWeb.Commercial.Helpers

  alias GnomeGarden.Commercial

  @impl true
  def mount(%{"id" => id} = params, _session, socket) do
    pursuit = load_pursuit!(id, socket.assigns.current_user)

    {:ok,
     socket
     |> assign(:page_title, pursuit.name)
     |> assign(:pursuit, pursuit)
     |> assign(:return_to, params["return_to"] || ~p"/commercial/pursuits")}
  end

  @impl true
  def handle_event("delete", _params, socket) do
    case Commercial.delete_pursuit(socket.assigns.pursuit, actor: socket.assigns.current_user) do
      :ok ->
        {:noreply, socket |> put_flash(:info, "Pursuit deleted") |> push_navigate(to: ~p"/commercial/pursuits")}
      {:error, error} ->
        {:noreply, put_flash(socket, :error, "Could not delete pursuit: #{inspect(error)}")}
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
          <.button navigate={@return_to}>
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

      <.section
        title="Pursuit Status"
        description={pursuit_status_description(@pursuit)}
      >
        <div class="flex flex-wrap gap-3">
          <.button
            :for={action <- pursuit_actions(@pursuit)}
            phx-click="transition"
            phx-value-action={action.action}
            variant={action.variant}
            title={action.title}
          >
            <.icon name={action.icon} class="size-4" /> {action.label}
          </.button>
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

  defp load_pursuit!(id, actor) do
    case Commercial.get_pursuit(
           id,
           actor: actor,
           load: [
             :organization,
             :weighted_value,
             :proposal_count,
             :stage_variant,
             proposals: [:status_variant],
             signal: [:status_variant]
           ]
         ) do
      {:ok, pursuit} -> pursuit
      {:error, error} -> raise "failed to load pursuit #{id}: #{inspect(error)}"
    end
  end

  defp can_create_proposal?(pursuit),
    do: pursuit.stage in [:qualified, :estimating, :proposed, :negotiating, :won, :reopened]

  defp pursuit_actions(%{stage: :new}) do
    [
      %{action: "qualify", label: "Qualify", icon: "hero-check-badge", variant: "primary", title: "Mark this pursuit as qualified — confirms it's worth pursuing"},
      %{action: "archive", label: "Archive", icon: "hero-archive-box", variant: nil, title: "Archive this pursuit — removes it from active view without deleting it"}
    ]
  end

  defp pursuit_actions(%{stage: :reopened}) do
    [
      %{action: "qualify", label: "Re-qualify", icon: "hero-check-badge", variant: "primary", title: "Re-qualify this pursuit and move it back into the active pipeline"},
      %{action: "archive", label: "Archive", icon: "hero-archive-box", variant: nil, title: "Archive this pursuit"}
    ]
  end

  defp pursuit_actions(%{stage: :qualified}) do
    [
      %{action: "estimate", label: "Start Estimate", icon: "hero-calculator", variant: nil, title: "Begin scoping and estimating the work before writing a proposal"},
      %{action: "propose", label: "Move To Proposal", icon: "hero-document-check", variant: "primary", title: "Create a formal proposal document for this pursuit"},
      %{action: "mark_lost", label: "Mark Lost", icon: "hero-x-circle", variant: nil, title: "Record that this opportunity was not won"}
    ]
  end

  defp pursuit_actions(%{stage: :estimating}) do
    [
      %{action: "propose", label: "Move To Proposal", icon: "hero-document-check", variant: "primary", title: "Estimation complete — create a formal proposal document"},
      %{action: "mark_lost", label: "Mark Lost", icon: "hero-x-circle", variant: nil, title: "Record that this opportunity was not won"}
    ]
  end

  defp pursuit_actions(%{stage: :proposed}) do
    [
      %{action: "negotiate", label: "Enter Negotiation", icon: "hero-arrows-right-left", variant: nil, title: "Move into active negotiation with the client before closing"},
      %{action: "mark_won", label: "Mark Won", icon: "hero-trophy", variant: "primary", title: "Record this pursuit as won — you can then create an agreement"},
      %{action: "mark_lost", label: "Mark Lost", icon: "hero-x-circle", variant: nil, title: "Record that this opportunity was not won"}
    ]
  end

  defp pursuit_actions(%{stage: :negotiating}) do
    [
      %{action: "mark_won", label: "Mark Won", icon: "hero-trophy", variant: "primary", title: "Record this pursuit as won — you can then create an agreement"},
      %{action: "mark_lost", label: "Mark Lost", icon: "hero-x-circle", variant: nil, title: "Record that this opportunity was not won"}
    ]
  end

  defp pursuit_actions(%{stage: :lost}) do
    [
      %{action: "reopen", label: "Reopen", icon: "hero-arrow-path", variant: "primary", title: "Reopen this pursuit — the opportunity may still be recoverable"},
      %{action: "archive", label: "Archive", icon: "hero-archive-box", variant: nil, title: "Archive this pursuit and remove it from active view"}
    ]
  end

  defp pursuit_actions(%{stage: :archived}) do
    [
      %{action: "reopen", label: "Reopen", icon: "hero-arrow-path", variant: "primary", title: "Bring this pursuit back into the active pipeline"}
    ]
  end

  defp pursuit_actions(_pursuit), do: []

  defp pursuit_status_description(%{stage: :new}),
    do: "New — qualify this pursuit to confirm it's worth chasing before investing more time."

  defp pursuit_status_description(%{stage: :reopened}),
    do: "Reopened — re-evaluate and qualify again to move this back into the active pipeline."

  defp pursuit_status_description(%{stage: :qualified}),
    do: "Qualified — you've confirmed this is worth pursuing. Estimate the scope and value next."

  defp pursuit_status_description(%{stage: :estimating}),
    do: "Estimating — scope and pricing are being worked out. Create a proposal when ready."

  defp pursuit_status_description(%{stage: :proposed}),
    do: "Proposed — a priced offer has been sent. Move to negotiation or mark won/lost based on the outcome."

  defp pursuit_status_description(%{stage: :negotiating}),
    do: "Negotiating — terms are being discussed. Mark won once agreed, or lost if it falls through."

  defp pursuit_status_description(%{stage: :won}),
    do: "Won — great news. Create an agreement to formalize the commitment and start delivery."

  defp pursuit_status_description(%{stage: :lost}),
    do: "Lost — the deal didn't close. Archive it to clean up the pipeline, or reopen if circumstances change."

  defp pursuit_status_description(%{stage: :archived}),
    do: "Archived — this pursuit is no longer active. Delete it if it was created by mistake."

  defp pursuit_status_description(_), do: "Manage this pursuit through the pipeline below."

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
