defmodule GnomeGardenWeb.Commercial.PursuitLive.Show do
  use GnomeGardenWeb, :live_view

  import GnomeGardenWeb.Components.OperationsUI, only: [related_tasks_panel: 1]
  import GnomeGardenWeb.Commercial.Helpers

  alias GnomeGarden.Commercial
  alias GnomeGardenWeb.Operations.TaskPubSub

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    pursuit = load_pursuit!(id, socket.assigns.current_user)

    if connected?(socket), do: TaskPubSub.subscribe_related(:pursuit, pursuit.id)

    {:ok,
     socket
     |> assign(:page_title, pursuit.name)
     |> assign(:pursuit, pursuit)}
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
  def handle_info(%{topic: "task:pursuit:" <> _pursuit_id}, socket) do
    {:noreply,
     assign(
       socket,
       :pursuit,
       load_pursuit!(socket.assigns.pursuit.id, socket.assigns.current_user)
     )}
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

      <.related_tasks_panel
        tasks={@pursuit.tasks || []}
        description="Operator follow-up linked to this pursuit."
        empty_description="Estimating, proposal, outreach, and close-plan tasks will appear here."
        new_task_path={new_pursuit_task_path(@pursuit)}
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

  defp load_pursuit!(id, actor) do
    case Commercial.get_pursuit_workspace(id, actor: actor) do
      {:ok, pursuit} -> pursuit
      {:error, error} -> raise "failed to load pursuit #{id}: #{inspect(error)}"
    end
  end

  defp new_pursuit_task_path(pursuit) do
    query =
      %{
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
      }
      |> Enum.reject(fn {_key, value} -> is_nil(value) or value == "" end)
      |> URI.encode_query()

    "/operations/tasks/new?#{query}"
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
