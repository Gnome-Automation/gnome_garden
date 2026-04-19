defmodule GnomeGardenWeb.Commercial.TargetAccountLive.Show do
  use GnomeGardenWeb, :live_view

  import GnomeGardenWeb.Commercial.Helpers

  alias GnomeGarden.Commercial

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    target_account = load_target_account!(id, socket.assigns.current_user)
    observations = load_observations(id, socket.assigns.current_user)

    {:ok,
     socket
     |> assign(:page_title, target_account.name)
     |> assign(:target_account, target_account)
     |> assign(:observations, observations)}
  end

  @impl true
  def handle_event("transition", %{"action" => action}, socket) do
    target_account = socket.assigns.target_account

    case transition_target_account(
           target_account,
           String.to_existing_atom(action),
           socket.assigns.current_user
         ) do
      {:ok, updated_target_account} ->
        refreshed_target_account =
          load_target_account!(updated_target_account.id, socket.assigns.current_user)

        {:noreply,
         socket
         |> assign(:target_account, refreshed_target_account)
         |> assign(
           :observations,
           load_observations(updated_target_account.id, socket.assigns.current_user)
         )
         |> put_flash(:info, "Target account updated")}

      {:error, error} ->
        {:noreply,
         put_flash(socket, :error, "Could not update target account: #{inspect(error)}")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.page class="pb-8">
      <.page_header eyebrow="Commercial">
        {@target_account.name}
        <:subtitle>
          <span class="inline-flex items-center gap-2">
            <.status_badge status={@target_account.status_variant}>
              {format_atom(@target_account.status)}
            </.status_badge>
            <span class="text-zinc-400 dark:text-zinc-500">/</span>
            <span>{@target_account.website_domain || "No website domain"}</span>
          </span>
        </:subtitle>
        <:actions>
          <.button navigate={~p"/commercial/targets"}>
            <.icon name="hero-arrow-left" class="size-4" /> Back
          </.button>
          <.button navigate={
            ~p"/commercial/observations/new?target_account_id=#{@target_account.id}&discovery_program_id=#{@target_account.discovery_program_id}"
          }>
            <.icon name="hero-plus" class="size-4" /> New Observation
          </.button>
          <.button
            :if={@target_account.promoted_signal}
            navigate={~p"/commercial/signals/#{@target_account.promoted_signal}"}
            variant="primary"
          >
            <.icon name="hero-inbox-stack" class="size-4" /> Open Signal
          </.button>
          <.button navigate={~p"/commercial/targets/#{@target_account}/edit"}>
            <.icon name="hero-pencil-square" class="size-4" /> Edit
          </.button>
        </:actions>
      </.page_header>

      <.section
        title="Review Actions"
        description="Promote only the target accounts that deserve real commercial attention."
      >
        <div class="flex flex-wrap gap-3">
          <.button
            :for={action <- target_actions(@target_account)}
            phx-click="transition"
            phx-value-action={action.action}
            variant={action.variant}
          >
            <.icon name={action.icon} class="size-4" /> {action.label}
          </.button>
        </div>
      </.section>

      <div class="grid gap-6 lg:grid-cols-2">
        <.section title="Target Context">
          <div class="grid gap-5 sm:grid-cols-2">
            <.property_item label="Website" value={@target_account.website || "-"} />
            <.property_item label="Domain" value={@target_account.website_domain || "-"} />
            <.property_item label="Location" value={@target_account.location || "-"} />
            <.property_item label="Region" value={@target_account.region || "-"} />
            <.property_item label="Industry" value={@target_account.industry || "-"} />
            <.property_item
              label="Discovery Program"
              value={
                (@target_account.discovery_program && @target_account.discovery_program.name) || "-"
              }
            />
            <.property_item
              label="Organization"
              value={(@target_account.organization && @target_account.organization.name) || "-"}
            />
          </div>
        </.section>

        <.section title="Scoring">
          <div class="grid gap-5 sm:grid-cols-2">
            <.property_item label="Fit Score" value={Integer.to_string(@target_account.fit_score)} />
            <.property_item
              label="Intent Score"
              value={Integer.to_string(@target_account.intent_score)}
            />
            <.property_item
              label="Observation Count"
              value={Integer.to_string(@target_account.observation_count)}
            />
            <.property_item
              label="Latest Observed"
              value={format_datetime(@target_account.latest_observed_at)}
            />
          </div>
        </.section>
      </div>

      <.section :if={@target_account.notes} title="Notes">
        <p class="whitespace-pre-wrap text-sm leading-6 text-zinc-600 dark:text-zinc-300">
          {@target_account.notes}
        </p>
      </.section>

      <.section
        title="Observations"
        description="Raw evidence stays attached here so the signal inbox only gets promoted, human-approved accounts."
      >
        <div :if={Enum.empty?(@observations)}>
          <.empty_state
            icon="hero-document-magnifying-glass"
            title="No observations yet"
            description="Scanners and operators can attach evidence here before the target becomes a signal."
          />
        </div>

        <div :if={!Enum.empty?(@observations)} class="space-y-3">
          <div
            :for={observation <- @observations}
            class="rounded-2xl border border-zinc-200 bg-zinc-50/70 px-4 py-4 dark:border-white/10 dark:bg-white/[0.03]"
          >
            <div class="flex flex-wrap items-start justify-between gap-3">
              <div class="space-y-2">
                <div class="flex flex-wrap gap-2">
                  <.tag color={:zinc}>{format_atom(observation.observation_type)}</.tag>
                  <.tag color={:sky}>{format_atom(observation.source_channel)}</.tag>
                  <.status_badge status={observation.confidence_variant}>
                    Confidence {observation.confidence_score}
                  </.status_badge>
                </div>
                <p class="font-medium text-zinc-900 dark:text-white">{observation.summary}</p>
                <p class="text-xs text-zinc-400 dark:text-zinc-500">
                  {format_datetime(observation.observed_at || observation.inserted_at)}
                </p>
              </div>
              <.link
                :if={observation.source_url}
                href={observation.source_url}
                target="_blank"
                class="text-sm font-medium text-emerald-600 hover:text-emerald-500 dark:text-emerald-300"
              >
                Source
              </.link>
              <.link
                navigate={~p"/commercial/observations/#{observation}"}
                class="text-sm font-medium text-sky-600 hover:text-sky-500 dark:text-sky-300"
              >
                Details
              </.link>
            </div>

            <p
              :if={observation.raw_excerpt}
              class="mt-3 text-sm leading-6 text-zinc-600 dark:text-zinc-300"
            >
              {observation.raw_excerpt}
            </p>
          </div>
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
      <div class="flex flex-wrap items-center gap-2">
        <p class="text-sm font-medium text-zinc-900 dark:text-white">{@value}</p>
      </div>
    </div>
    """
  end

  defp load_target_account!(id, actor) do
    case Commercial.get_target_account(
           id,
           actor: actor,
           load: [
             :organization,
             :discovery_program,
             :promoted_signal,
             :status_variant,
             :observation_count,
             :latest_observed_at
           ]
         ) do
      {:ok, target_account} -> target_account
      {:error, error} -> raise "failed to load target account #{id}: #{inspect(error)}"
    end
  end

  defp load_observations(id, actor) do
    case Commercial.list_target_observations_for_target_account(
           id,
           actor: actor,
           load: [:confidence_variant]
         ) do
      {:ok, observations} -> observations
      {:error, error} -> raise "failed to load target observations: #{inspect(error)}"
    end
  end

  defp target_actions(%{status: :new}) do
    [
      %{action: "start_review", label: "Start Review", icon: "hero-eye", variant: nil},
      %{
        action: "promote_to_signal",
        label: "Promote To Signal",
        icon: "hero-arrow-up-right",
        variant: "primary"
      },
      %{action: "reject", label: "Reject", icon: "hero-x-mark", variant: nil},
      %{action: "archive", label: "Archive", icon: "hero-archive-box", variant: nil}
    ]
  end

  defp target_actions(%{status: :reviewing}) do
    [
      %{
        action: "promote_to_signal",
        label: "Promote To Signal",
        icon: "hero-arrow-up-right",
        variant: "primary"
      },
      %{action: "reject", label: "Reject", icon: "hero-x-mark", variant: nil},
      %{action: "archive", label: "Archive", icon: "hero-archive-box", variant: nil}
    ]
  end

  defp target_actions(%{status: :promoted}) do
    [
      %{action: "archive", label: "Archive", icon: "hero-archive-box", variant: nil}
    ]
  end

  defp target_actions(%{status: :rejected}) do
    [
      %{action: "reopen", label: "Reopen", icon: "hero-arrow-path", variant: "primary"},
      %{action: "archive", label: "Archive", icon: "hero-archive-box", variant: nil}
    ]
  end

  defp target_actions(%{status: :archived}) do
    [
      %{action: "reopen", label: "Reopen", icon: "hero-arrow-path", variant: "primary"}
    ]
  end

  defp target_actions(_target_account), do: []

  defp transition_target_account(target_account, :start_review, actor),
    do: Commercial.review_target_account(target_account, actor: actor)

  defp transition_target_account(target_account, :promote_to_signal, actor),
    do: Commercial.promote_target_account_to_signal(target_account, actor: actor)

  defp transition_target_account(target_account, :reject, actor),
    do: Commercial.reject_target_account(target_account, %{}, actor: actor)

  defp transition_target_account(target_account, :archive, actor),
    do: Commercial.archive_target_account(target_account, actor: actor)

  defp transition_target_account(target_account, :reopen, actor),
    do: Commercial.reopen_target_account(target_account, actor: actor)
end
