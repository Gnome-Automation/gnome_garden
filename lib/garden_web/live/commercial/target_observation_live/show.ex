defmodule GnomeGardenWeb.Commercial.TargetObservationLive.Show do
  use GnomeGardenWeb, :live_view

  import GnomeGardenWeb.Commercial.Helpers

  alias GnomeGarden.Commercial

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    observation = load_observation!(id, socket.assigns.current_user)

    {:ok,
     socket
     |> assign(:page_title, observation.summary)
     |> assign(:observation, observation)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.page class="pb-8">
      <.page_header eyebrow="Commercial">
        {@observation.summary}
        <:subtitle>
          <span class="inline-flex items-center gap-2">
            <.tag color={:zinc}>{format_atom(@observation.observation_type)}</.tag>
            <span class="text-zinc-400 dark:text-zinc-500">/</span>
            <span>{format_atom(@observation.source_channel)}</span>
          </span>
        </:subtitle>
        <:actions>
          <.button navigate={~p"/commercial/observations"}>
            <.icon name="hero-arrow-left" class="size-4" /> Back
          </.button>
          <.button
            :if={@observation.target_account}
            navigate={~p"/commercial/targets/#{@observation.target_account}"}
          >
            <.icon name="hero-magnifying-glass" class="size-4" /> Open Target
          </.button>
          <.button navigate={~p"/commercial/observations/#{@observation}/edit"}>
            <.icon name="hero-pencil-square" class="size-4" /> Edit
          </.button>
        </:actions>
      </.page_header>

      <div class="grid gap-6 lg:grid-cols-2">
        <.section title="Observation Context">
          <div class="grid gap-5 sm:grid-cols-2">
            <.property_item
              label="Target Account"
              value={(@observation.target_account && @observation.target_account.name) || "-"}
            />
            <.property_item
              label="Discovery Program"
              value={(@observation.discovery_program && @observation.discovery_program.name) || "-"}
            />
            <.property_item
              label="Observation Type"
              value={format_atom(@observation.observation_type)}
            />
            <.property_item label="Source Channel" value={format_atom(@observation.source_channel)} />
            <.property_item
              label="Observed"
              value={format_datetime(@observation.observed_at || @observation.inserted_at)}
            />
            <.property_item
              label="Confidence"
              value={Integer.to_string(@observation.confidence_score)}
              badge={@observation.confidence_variant}
            />
            <.property_item label="External Ref" value={@observation.external_ref || "-"} />
            <.property_item label="Source URL" value={@observation.source_url || "-"} />
          </div>
        </.section>

        <.section
          title="Evidence Points"
          description="Keep the raw rationale durable so target-account promotion stays explainable."
        >
          <div :if={Enum.empty?(@observation.evidence_points)}>
            <.empty_state
              icon="hero-list-bullet"
              title="No evidence points"
              description="This observation does not yet have structured supporting bullets."
            />
          </div>

          <ul
            :if={!Enum.empty?(@observation.evidence_points)}
            class="space-y-3 text-sm text-zinc-600 dark:text-zinc-300"
          >
            <li
              :for={point <- @observation.evidence_points}
              class="rounded-2xl border border-zinc-200 bg-zinc-50/70 px-4 py-3 dark:border-white/10 dark:bg-white/[0.03]"
            >
              {point}
            </li>
          </ul>
        </.section>
      </div>

      <.section :if={@observation.raw_excerpt} title="Raw Excerpt">
        <p class="whitespace-pre-wrap text-sm leading-6 text-zinc-600 dark:text-zinc-300">
          {@observation.raw_excerpt}
        </p>
      </.section>
    </.page>
    """
  end

  attr :label, :string, required: true
  attr :value, :string, required: true
  attr :badge, :atom, default: nil

  defp property_item(assigns) do
    ~H"""
    <div class="space-y-1">
      <p class="text-xs font-semibold uppercase tracking-[0.2em] text-zinc-400 dark:text-zinc-500">
        {@label}
      </p>
      <p :if={is_nil(@badge)} class="text-sm font-medium text-zinc-900 dark:text-white">{@value}</p>
      <.status_badge :if={@badge} status={@badge}>{@value}</.status_badge>
    </div>
    """
  end

  defp load_observation!(id, actor) do
    case Commercial.get_target_observation(
           id,
           actor: actor,
           load: [:target_account, :discovery_program, :confidence_variant]
         ) do
      {:ok, observation} -> observation
      {:error, error} -> raise "failed to load target observation #{id}: #{inspect(error)}"
    end
  end
end
