defmodule GnomeGardenWeb.Commercial.ProposalLive.Show do
  use GnomeGardenWeb, :live_view

  import GnomeGardenWeb.Commercial.Helpers

  alias GnomeGarden.Commercial

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    proposal = load_proposal!(id, socket.assigns.current_user)

    {:ok,
     socket
     |> assign(:page_title, proposal.name)
     |> assign(:proposal, proposal)}
  end

  @impl true
  def handle_event("transition", %{"action" => action}, socket) do
    proposal = socket.assigns.proposal

    case transition_proposal(
           proposal,
           String.to_existing_atom(action),
           socket.assigns.current_user
         ) do
      {:ok, updated_proposal} ->
        {:noreply,
         socket
         |> assign(:proposal, load_proposal!(updated_proposal.id, socket.assigns.current_user))
         |> put_flash(:info, "Proposal updated")}

      {:error, error} ->
        {:noreply, put_flash(socket, :error, "Could not update proposal: #{inspect(error)}")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.page class="pb-8">
      <.page_header eyebrow="Commercial">
        {@proposal.name}
        <:subtitle>
          <span class="inline-flex items-center gap-2">
            <.status_badge status={@proposal.status_variant}>
              {format_atom(@proposal.status)}
            </.status_badge>
            <span class="text-zinc-400 dark:text-zinc-500">/</span>
            <span>{@proposal.proposal_number}</span>
          </span>
        </:subtitle>
        <:actions>
          <.button navigate={~p"/commercial/proposals"}>
            <.icon name="hero-arrow-left" class="size-4" /> Back
          </.button>
          <.button
            :if={can_create_agreement?(@proposal)}
            navigate={~p"/commercial/agreements/new?proposal_id=#{@proposal.id}"}
            variant="primary"
          >
            <.icon name="hero-document-check" class="size-4" /> Create Agreement
          </.button>
          <.button navigate={~p"/commercial/proposals/#{@proposal}/edit"}>
            <.icon name="hero-pencil-square" class="size-4" /> Edit
          </.button>
        </:actions>
      </.page_header>

      <.section
        title="Proposal Actions"
        description="Issue, accept, reject, or reopen priced offers explicitly so downstream agreements stay trustworthy."
      >
        <div class="flex flex-wrap gap-3">
          <.button
            :for={action <- proposal_actions(@proposal)}
            phx-click="transition"
            phx-value-action={action.action}
            variant={action.variant}
          >
            <.icon name={action.icon} class="size-4" /> {action.label}
          </.button>
        </div>
      </.section>

      <div class="grid gap-6 lg:grid-cols-2">
        <.section title="Commercial Snapshot">
          <div class="grid gap-5 sm:grid-cols-2">
            <.property_item label="Revision" value={"Rev #{@proposal.revision_number}"} />
            <.property_item label="Pricing Model" value={format_atom(@proposal.pricing_model)} />
            <.property_item label="Delivery Model" value={format_atom(@proposal.delivery_model)} />
            <.property_item label="Valid Until" value={format_date(@proposal.valid_until_on)} />
            <.property_item label="Issued On" value={format_date(@proposal.issued_on)} />
            <.property_item label="Accepted On" value={format_date(@proposal.accepted_on)} />
          </div>
        </.section>

        <.section title="Commercial Context">
          <div class="grid gap-5 sm:grid-cols-2">
            <.property_item
              label="Pursuit"
              value={(@proposal.pursuit && @proposal.pursuit.name) || "-"}
            />
            <.property_item
              label="Organization"
              value={(@proposal.organization && @proposal.organization.name) || "-"}
            />
            <.property_item label="Lines" value={Integer.to_string(@proposal.line_count || 0)} />
            <.property_item label="Quoted Value" value={format_amount(@proposal.total_amount)} />
            <.property_item
              label="Agreements"
              value={Integer.to_string(@proposal.agreement_count || 0)}
            />
            <.property_item label="Currency" value={@proposal.currency_code || "-"} />
          </div>
        </.section>
      </div>

      <.section :if={@proposal.description} title="Description">
        <p class="whitespace-pre-wrap text-sm leading-6 text-zinc-600 dark:text-zinc-300">
          {@proposal.description}
        </p>
      </.section>

      <.section :if={@proposal.notes} title="Notes">
        <p class="whitespace-pre-wrap text-sm leading-6 text-zinc-600 dark:text-zinc-300">
          {@proposal.notes}
        </p>
      </.section>

      <.section
        title="Proposal Lines"
        description="Scope and pricing details rolled up into this offer."
      >
        <div :if={Enum.empty?(@proposal.proposal_lines || [])}>
          <.empty_state
            icon="hero-list-bullet"
            title="No proposal lines yet"
            description="Proposal lines can be added next to capture engineering, software, hardware, and service scope."
          />
        </div>

        <div :if={!Enum.empty?(@proposal.proposal_lines || [])} class="space-y-3">
          <div
            :for={line <- @proposal.proposal_lines}
            class="flex items-start justify-between rounded-2xl border border-zinc-200 bg-zinc-50/70 px-4 py-4 dark:border-white/10 dark:bg-white/[0.03]"
          >
            <div class="space-y-1">
              <p class="font-medium text-zinc-900 dark:text-white">
                {line.line_number}. {line.description}
              </p>
              <p class="text-sm text-zinc-500 dark:text-zinc-400">
                {format_atom(line.line_kind)} · Qty {Decimal.to_string(line.quantity)}
              </p>
            </div>
            <div class="text-right text-sm text-zinc-600 dark:text-zinc-300">
              <p>{format_amount(line.line_total)}</p>
              <p class="text-xs text-zinc-400 dark:text-zinc-500">
                {format_amount(line.unit_price)} each
              </p>
            </div>
          </div>
        </div>
      </.section>

      <.section
        title="Downstream Agreements"
        description="Accepted proposals should become explicit agreements instead of silently mutating into delivery work."
      >
        <div :if={Enum.empty?(@proposal.agreements || [])}>
          <.empty_state
            icon="hero-document-check"
            title="No agreements yet"
            description="Once this proposal is accepted, create an agreement to lock in the commercial commitment."
          />
        </div>

        <div :if={!Enum.empty?(@proposal.agreements || [])} class="space-y-3">
          <.link
            :for={agreement <- @proposal.agreements}
            navigate={~p"/commercial/agreements/#{agreement}"}
            class="flex items-center justify-between rounded-2xl border border-zinc-200 bg-zinc-50/70 px-4 py-4 transition hover:border-emerald-300 hover:bg-white dark:border-white/10 dark:bg-white/[0.03] dark:hover:border-emerald-400/40"
          >
            <div class="space-y-1">
              <p class="font-medium text-zinc-900 dark:text-white">{agreement.name}</p>
              <p class="text-sm text-zinc-500 dark:text-zinc-400">
                {agreement.reference_number || "No reference number"}
              </p>
            </div>
            <.status_badge status={agreement.status_variant}>
              {format_atom(agreement.status)}
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
      <p class="text-xs font-semibold uppercase tracking-[0.2em] text-zinc-400 dark:text-zinc-500">
        {@label}
      </p>
      <p class="text-sm font-medium text-zinc-900 dark:text-white">{@value}</p>
    </div>
    """
  end

  defp load_proposal!(id, actor) do
    case Commercial.get_proposal(
           id,
           actor: actor,
           load: [
             :status_variant,
             :line_count,
             :agreement_count,
             :total_amount,
             pursuit: [],
             organization: [],
             proposal_lines: [],
             agreements: [:status_variant]
           ]
         ) do
      {:ok, proposal} -> proposal
      {:error, error} -> raise "failed to load proposal #{id}: #{inspect(error)}"
    end
  end

  defp can_create_agreement?(proposal),
    do: proposal.status == :accepted

  defp proposal_actions(%{status: :draft}) do
    [
      %{action: "issue", label: "Issue", icon: "hero-paper-airplane", variant: "primary"},
      %{action: "supersede", label: "Supersede", icon: "hero-arrow-path", variant: nil}
    ]
  end

  defp proposal_actions(%{status: :issued}) do
    [
      %{action: "accept", label: "Accept", icon: "hero-check-badge", variant: "primary"},
      %{action: "reject", label: "Reject", icon: "hero-x-circle", variant: nil},
      %{action: "expire", label: "Expire", icon: "hero-clock", variant: nil}
    ]
  end

  defp proposal_actions(%{status: :rejected}) do
    [
      %{action: "issue", label: "Reissue", icon: "hero-paper-airplane", variant: "primary"},
      %{action: "reopen", label: "Reopen Draft", icon: "hero-arrow-path", variant: nil}
    ]
  end

  defp proposal_actions(%{status: :expired}) do
    [
      %{action: "issue", label: "Reissue", icon: "hero-paper-airplane", variant: "primary"},
      %{action: "reopen", label: "Reopen Draft", icon: "hero-arrow-path", variant: nil}
    ]
  end

  defp proposal_actions(%{status: :superseded}) do
    [
      %{action: "reopen", label: "Reopen Draft", icon: "hero-arrow-path", variant: "primary"}
    ]
  end

  defp proposal_actions(_proposal), do: []

  defp transition_proposal(proposal, :issue, actor),
    do: Commercial.issue_proposal(proposal, actor: actor)

  defp transition_proposal(proposal, :accept, actor),
    do: Commercial.accept_proposal(proposal, actor: actor)

  defp transition_proposal(proposal, :reject, actor),
    do: Commercial.reject_proposal(proposal, actor: actor)

  defp transition_proposal(proposal, :expire, actor),
    do: Commercial.expire_proposal(proposal, actor: actor)

  defp transition_proposal(proposal, :supersede, actor),
    do: Commercial.supersede_proposal(proposal, actor: actor)

  defp transition_proposal(proposal, :reopen, actor),
    do: Commercial.reopen_proposal(proposal, actor: actor)
end
