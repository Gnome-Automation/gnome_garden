defmodule GnomeGardenWeb.Commercial.SignalLive.Show do
  use GnomeGardenWeb, :live_view

  import GnomeGardenWeb.Commercial.Helpers

  alias GnomeGarden.Acquisition
  alias GnomeGarden.Commercial

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    signal = load_signal!(id, socket.assigns.current_user)
    finding_id = load_finding_id(signal.id)

    {:ok,
     socket
     |> assign(:page_title, signal.title)
     |> assign(:finding_id, finding_id)
     |> assign(:signal, signal)}
  end

  @impl true
  def handle_event("transition", %{"action" => action}, socket) do
    signal = socket.assigns.signal

    case transition_signal(signal, String.to_existing_atom(action), socket.assigns.current_user) do
      {:ok, updated_signal} ->
        {:noreply,
         socket
         |> assign(:signal, load_signal!(updated_signal.id, socket.assigns.current_user))
         |> put_flash(:info, "Signal updated")}

      {:error, error} ->
        {:noreply, put_flash(socket, :error, "Could not update signal: #{inspect(error)}")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.page class="pb-8">
      <.page_header eyebrow="Commercial">
        {@signal.title}
        <:subtitle>
          <span class="inline-flex items-center gap-2">
            <.status_badge status={@signal.status_variant}>
              {format_atom(@signal.status)}
            </.status_badge>
            <span class="text-base-content/40">/</span>
            <span>{format_atom(@signal.signal_type)}</span>
          </span>
        </:subtitle>
        <:actions>
          <.button navigate={~p"/commercial/signals"}>
            Back
          </.button>
          <.button
            :if={@finding_id}
            navigate={~p"/acquisition/findings/#{@finding_id}"}
          >
            Open Intake Finding
          </.button>
          <.button
            :if={can_create_pursuit?(@signal)}
            navigate={~p"/commercial/pursuits/new?signal_id=#{@signal.id}"}
            variant="primary"
          >
            Create Pursuit
          </.button>
          <.button navigate={~p"/commercial/signals/#{@signal}/edit"}>
            Edit
          </.button>
        </:actions>
      </.page_header>

      <.section
        title="Review Actions"
        description="Move the intake item through review and convert it into pipeline only when it deserves follow-up."
      >
        <div class="flex flex-wrap gap-3">
          <.button
            :for={action <- signal_actions(@signal)}
            phx-click="transition"
            phx-value-action={action.action}
            variant={action.variant}
          >
            <.icon name={action.icon} class="size-4" /> {action.label}
          </.button>
        </div>
      </.section>

      <div class="grid gap-6 lg:grid-cols-2">
        <.section title="Signal Context">
          <div class="grid gap-5 sm:grid-cols-2">
            <.property_item label="Signal Type" value={format_atom(@signal.signal_type)} />
            <.property_item label="Source Channel" value={format_atom(@signal.source_channel)} />
            <.property_item label="External Ref" value={@signal.external_ref || "-"} />
            <.property_item
              label="Observed"
              value={format_datetime(@signal.observed_at || @signal.inserted_at)}
            />
            <.property_item label="Source URL" value={@signal.source_url || "-"} />
            <.property_item label="Created" value={format_datetime(@signal.inserted_at)} />
          </div>
        </.section>

        <.section title="Operating Context">
          <div class="grid gap-5 sm:grid-cols-2">
            <.property_item
              label="Organization"
              value={(@signal.organization && @signal.organization.name) || "-"}
            />
            <.property_item label="Site" value={(@signal.site && @signal.site.name) || "-"} />
            <.property_item
              label="Managed System"
              value={(@signal.managed_system && @signal.managed_system.name) || "-"}
            />
            <.property_item
              label="Linked Pursuits"
              value={Integer.to_string(length(@signal.pursuits || []))}
            />
          </div>
        </.section>
      </div>

      <.section
        :if={@signal.procurement_bid}
        title="Procurement Provenance"
        description="This signal came from the procurement console and should retain a clear link back to the raw bid intake record."
      >
        <div class="grid gap-5 sm:grid-cols-2">
          <.property_item label="Bid Title" value={@signal.procurement_bid.title} />
          <.property_item label="Bid Status" value={format_atom(@signal.procurement_bid.status)} />
          <.property_item label="Agency" value={@signal.procurement_bid.agency || "-"} />
          <.property_item
            label="Bid Due"
            value={format_datetime(@signal.procurement_bid.due_at)}
          />
          <.property_item
            label="Score Tier"
            value={format_score_tier(@signal.procurement_bid.score_tier)}
          />
          <.property_item
            label="Source Confidence"
            value={format_source_confidence(@signal.procurement_bid.score_source_confidence)}
          />
        </div>

        <div
          :if={
            @signal.procurement_bid.score_recommendation ||
              @signal.procurement_bid.score_risk_flags != []
          }
          class="mt-4 space-y-4"
        >
          <div
            :if={@signal.procurement_bid.score_recommendation}
            class="rounded-2xl border border-emerald-200 bg-emerald-50/70 px-4 py-4 text-sm text-emerald-900 dark:border-emerald-400/20 dark:bg-emerald-400/10 dark:text-emerald-100"
          >
            <p class="text-xs font-semibold uppercase tracking-[0.2em] text-primary">
              Procurement Recommendation
            </p>
            <p class="mt-2 leading-6">{@signal.procurement_bid.score_recommendation}</p>
          </div>

          <div :if={@signal.procurement_bid.score_risk_flags != []}>
            <p class="text-xs font-semibold uppercase tracking-[0.2em] text-base-content/40">
              Procurement Watchouts
            </p>
            <div class="mt-2 flex flex-wrap gap-2">
              <span
                :for={flag <- @signal.procurement_bid.score_risk_flags}
                class="badge badge-outline badge-sm border-amber-300 bg-white/70 text-amber-700 dark:border-amber-400/30 dark:bg-white/[0.03] dark:text-amber-200"
              >
                {flag}
              </span>
            </div>
          </div>
        </div>
      </.section>

      <.section
        :if={discovery_signal?(@signal, @finding_id)}
        title="Discovery Provenance"
        description="This signal came from a promoted discovery record and should retain the fit, intent, and watchouts that justified promotion."
      >
        <div class="grid gap-5 sm:grid-cols-2">
          <.property_item
            label="Discovery Program"
            value={metadata_value(@signal.metadata, :discovery_program_name) || "-"}
          />
          <.property_item
            label="Intake Finding"
            value={@finding_id || "-"}
          />
          <.property_item
            label="Fit Score"
            value={to_string(metadata_value(@signal.metadata, :fit_score) || "-")}
          />
          <.property_item
            label="Intent Score"
            value={to_string(metadata_value(@signal.metadata, :intent_score) || "-")}
          />
        </div>

        <div
          :if={
            metadata_value(@signal.metadata, :latest_evidence_summary) ||
              discovery_watchouts(@signal) != []
          }
          class="mt-4 space-y-4"
        >
          <div
            :if={metadata_value(@signal.metadata, :latest_evidence_summary)}
            class="rounded-2xl border border-sky-200 bg-sky-50/70 px-4 py-4 text-sm text-sky-900 dark:border-sky-400/20 dark:bg-sky-400/10 dark:text-sky-100"
          >
            <p class="text-xs font-semibold uppercase tracking-[0.2em] text-info">
              Discovery Summary
            </p>
            <p class="mt-2 leading-6">
              {metadata_value(@signal.metadata, :latest_evidence_summary)}
            </p>
          </div>

          <div :if={discovery_watchouts(@signal) != []}>
            <p class="text-xs font-semibold uppercase tracking-[0.2em] text-base-content/40">
              Discovery Watchouts
            </p>
            <div class="mt-2 flex flex-wrap gap-2">
              <span
                :for={flag <- discovery_watchouts(@signal)}
                class="badge badge-outline badge-sm border-amber-300 bg-white/70 text-amber-700 dark:border-amber-400/30 dark:bg-white/[0.03] dark:text-amber-200"
              >
                {flag}
              </span>
            </div>
          </div>

          <div :if={discovery_feedback(@signal)}>
            <p class="text-xs font-semibold uppercase tracking-[0.2em] text-base-content/40">
              Discovery Review Feedback
            </p>
            <p class="mt-2 text-sm leading-6 text-base-content/70">
              {format_discovery_feedback(discovery_feedback(@signal))}
            </p>
          </div>
        </div>
      </.section>

      <.section :if={@signal.description} title="Description">
        <p class="whitespace-pre-wrap text-sm leading-6 text-base-content/70">
          {@signal.description}
        </p>
      </.section>

      <.section :if={@signal.notes} title="Notes">
        <p class="whitespace-pre-wrap text-sm leading-6 text-base-content/70">
          {@signal.notes}
        </p>
      </.section>

      <.section
        title="Downstream Pursuits"
        description="Signals should only become pursuits after a clear accept-and-convert decision."
      >
        <div :if={Enum.empty?(@signal.pursuits || [])}>
          <.empty_state
            icon="hero-arrow-trending-up"
            title="No pursuits yet"
            description="Accept the signal, then convert it into a pursuit when someone is ready to own the follow-up."
          />
        </div>

        <div :if={!Enum.empty?(@signal.pursuits || [])} class="space-y-3">
          <.link
            :for={pursuit <- @signal.pursuits}
            navigate={~p"/commercial/pursuits/#{pursuit}"}
            class="flex items-center justify-between rounded-2xl border border-zinc-200 bg-zinc-50/70 px-4 py-4 transition hover:border-emerald-300 hover:bg-white dark:border-white/10 dark:bg-white/[0.03] dark:hover:border-emerald-400/40"
          >
            <div class="space-y-1">
              <p class="font-medium text-base-content">{pursuit.name}</p>
              <p class="text-sm text-base-content/50">
                {format_atom(pursuit.pursuit_type)}
              </p>
            </div>
            <.status_badge status={pursuit.stage_variant}>
              {format_atom(pursuit.stage)}
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

  defp load_signal!(id, actor) do
    case Commercial.get_signal(
           id,
           actor: actor,
           load: [
             :organization,
             :site,
             :managed_system,
             :status_variant,
             :procurement_bid,
             pursuits: [:stage_variant]
           ]
         ) do
      {:ok, signal} -> signal
      {:error, error} -> raise "failed to load signal #{id}: #{inspect(error)}"
    end
  end

  defp load_finding_id(signal_id) do
    case Acquisition.get_finding_by_signal(signal_id) do
      {:ok, finding} -> finding.id
      _ -> nil
    end
  end

  defp can_create_pursuit?(signal),
    do: signal.status == :accepted and Enum.empty?(signal.pursuits || [])

  defp format_score_tier(nil), do: "-"

  defp format_score_tier(tier) do
    tier
    |> to_string()
    |> String.upcase()
  end

  defp format_source_confidence(nil), do: "-"

  defp format_source_confidence(confidence) do
    confidence
    |> to_string()
    |> String.replace("_", " ")
    |> String.capitalize()
  end

  defp discovery_signal?(signal, finding_id) do
    signal.source_channel == :agent_discovery and not is_nil(finding_id)
  end

  defp discovery_watchouts(signal) do
    signal.metadata
    |> metadata_value(:market_focus)
    |> case do
      market_focus when is_map(market_focus) ->
        metadata_value(market_focus, :risk_flags) |> List.wrap()

      _ ->
        []
    end
  end

  defp discovery_feedback(signal) do
    metadata_value(signal.metadata, :discovery_feedback)
  end

  defp format_discovery_feedback(nil), do: "-"

  defp format_discovery_feedback(feedback) when is_map(feedback) do
    reason = metadata_value(feedback, :reason)
    reason_code = metadata_value(feedback, :reason_code)
    feedback_scope = metadata_value(feedback, :feedback_scope)

    [
      reason_code,
      reason,
      feedback_scope && "(#{String.replace(to_string(feedback_scope), "_", " ")})"
    ]
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.join(" ")
  end

  defp metadata_value(metadata, key) when is_map(metadata),
    do: Map.get(metadata, key) || Map.get(metadata, to_string(key))

  defp metadata_value(_metadata, _key), do: nil

  defp signal_actions(%{status: :new}) do
    [
      %{action: "start_review", label: "Start Review", icon: "hero-eye", variant: nil},
      %{action: "accept", label: "Accept", icon: "hero-check", variant: "primary"},
      %{action: "reject", label: "Reject", icon: "hero-x-mark", variant: nil},
      %{action: "archive", label: "Archive", icon: "hero-archive-box", variant: nil}
    ]
  end

  defp signal_actions(%{status: :reviewing}) do
    [
      %{action: "accept", label: "Accept", icon: "hero-check", variant: "primary"},
      %{action: "reject", label: "Reject", icon: "hero-x-mark", variant: nil},
      %{action: "archive", label: "Archive", icon: "hero-archive-box", variant: nil}
    ]
  end

  defp signal_actions(%{status: :accepted}) do
    [
      %{action: "archive", label: "Archive", icon: "hero-archive-box", variant: nil}
    ]
  end

  defp signal_actions(%{status: :rejected}) do
    [
      %{action: "reopen", label: "Reopen", icon: "hero-arrow-path", variant: "primary"},
      %{action: "archive", label: "Archive", icon: "hero-archive-box", variant: nil}
    ]
  end

  defp signal_actions(%{status: :archived}) do
    [
      %{action: "reopen", label: "Reopen", icon: "hero-arrow-path", variant: "primary"}
    ]
  end

  defp signal_actions(_signal), do: []

  defp transition_signal(signal, :start_review, actor),
    do: Commercial.review_signal(signal, actor: actor)

  defp transition_signal(signal, :accept, actor),
    do: Commercial.accept_signal(signal, actor: actor)

  defp transition_signal(signal, :reject, actor),
    do: Commercial.reject_signal(signal, %{}, actor: actor)

  defp transition_signal(signal, :archive, actor),
    do: Commercial.archive_signal(signal, actor: actor)

  defp transition_signal(signal, :reopen, actor),
    do: Commercial.reopen_signal(signal, actor: actor)
end
