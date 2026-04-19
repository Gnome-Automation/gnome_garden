defmodule GnomeGardenWeb.Commercial.TargetObservationLive.Index do
  use GnomeGardenWeb, :live_view

  import GnomeGardenWeb.Commercial.Helpers

  alias GnomeGarden.Commercial

  @impl true
  def mount(_params, _session, socket) do
    observations = load_observations(socket.assigns.current_user)

    {:ok,
     socket
     |> assign(:page_title, "Target Observations")
     |> assign(:observation_count, length(observations))
     |> assign(:high_confidence_count, Enum.count(observations, &(&1.confidence_score >= 75)))
     |> assign(
       :website_contact_count,
       Enum.count(observations, &(&1.observation_type == :website_contact))
     )
     |> stream(:observations, observations)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.page class="pb-8">
      <.page_header eyebrow="Commercial">
        Target Observations
        <:subtitle>
          Raw discovery evidence lives here. Promote target accounts, not individual observations, into the signal inbox.
        </:subtitle>
        <:actions>
          <.button navigate={~p"/commercial/targets"}>
            <.icon name="hero-magnifying-glass" class="size-4" /> Targets
          </.button>
          <.button navigate={~p"/commercial/observations/new"} variant="primary">
            <.icon name="hero-plus" class="size-4" /> New Observation
          </.button>
        </:actions>
      </.page_header>

      <div class="grid gap-4 md:grid-cols-3">
        <.stat_card
          title="Observations"
          value={Integer.to_string(@observation_count)}
          description="Raw pieces of evidence attached to the discovery backlog."
          icon="hero-document-magnifying-glass"
        />
        <.stat_card
          title="High Confidence"
          value={Integer.to_string(@high_confidence_count)}
          description="Observations that look strong enough to shape a real review decision."
          icon="hero-check-badge"
          accent="emerald"
        />
        <.stat_card
          title="Website Contacts"
          value={Integer.to_string(@website_contact_count)}
          description="Observations that came directly from company sites or public contact pages."
          icon="hero-globe-alt"
          accent="sky"
        />
      </div>

      <.section
        title="Recent Evidence"
        description="Inspect discovery evidence independently from target-account promotion so the backlog stays explainable."
        compact
        body_class="p-0"
      >
        <div :if={@observation_count == 0} class="p-6 sm:p-7">
          <.empty_state
            icon="hero-document-magnifying-glass"
            title="No observations yet"
            description="Discovery runs and operators can add evidence here before or after target creation."
          >
            <:action>
              <.button navigate={~p"/commercial/observations/new"} variant="primary">
                Create Observation
              </.button>
            </:action>
          </.empty_state>
        </div>

        <div :if={@observation_count > 0} class="overflow-x-auto">
          <table class="min-w-full divide-y divide-zinc-200 text-sm dark:divide-white/10">
            <thead class="bg-zinc-50 dark:bg-white/[0.03]">
              <tr>
                <th class="px-5 py-3 text-left font-medium text-zinc-500 dark:text-zinc-400">
                  Observation
                </th>
                <th class="px-5 py-3 text-left font-medium text-zinc-500 dark:text-zinc-400">
                  Target
                </th>
                <th class="px-5 py-3 text-left font-medium text-zinc-500 dark:text-zinc-400">
                  Source
                </th>
                <th class="px-5 py-3 text-left font-medium text-zinc-500 dark:text-zinc-400">
                  Observed
                </th>
                <th class="px-5 py-3 text-left font-medium text-zinc-500 dark:text-zinc-400">
                  Confidence
                </th>
              </tr>
            </thead>
            <tbody
              id="target-observations"
              phx-update="stream"
              class="divide-y divide-zinc-200 dark:divide-white/10"
            >
              <tr :for={{dom_id, observation} <- @streams.observations} id={dom_id}>
                <td class="px-5 py-4 align-top">
                  <div class="space-y-1">
                    <.link
                      navigate={~p"/commercial/observations/#{observation}"}
                      class="font-medium text-zinc-900 hover:text-emerald-600 dark:text-white"
                    >
                      {observation.summary}
                    </.link>
                    <p class="text-xs text-zinc-400 dark:text-zinc-500">
                      {format_atom(observation.observation_type)}
                    </p>
                  </div>
                </td>
                <td class="px-5 py-4 align-top text-zinc-600 dark:text-zinc-300">
                  <.link
                    :if={observation.target_account}
                    navigate={~p"/commercial/targets/#{observation.target_account}"}
                    class="hover:text-emerald-600 dark:hover:text-emerald-300"
                  >
                    {observation.target_account.name}
                  </.link>
                  <span :if={is_nil(observation.target_account)}>-</span>
                </td>
                <td class="px-5 py-4 align-top text-zinc-600 dark:text-zinc-300">
                  <div class="space-y-2">
                    <.tag color={:zinc}>{format_atom(observation.source_channel)}</.tag>
                    <.link
                      :if={observation.source_url}
                      href={observation.source_url}
                      target="_blank"
                      class="block text-xs font-medium text-emerald-600 hover:text-emerald-500 dark:text-emerald-300"
                    >
                      Open source
                    </.link>
                  </div>
                </td>
                <td class="px-5 py-4 align-top text-zinc-600 dark:text-zinc-300">
                  {format_datetime(observation.observed_at || observation.inserted_at)}
                </td>
                <td class="px-5 py-4 align-top">
                  <.status_badge status={observation.confidence_variant}>
                    {Integer.to_string(observation.confidence_score)}
                  </.status_badge>
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </.section>
    </.page>
    """
  end

  defp load_observations(actor) do
    case Commercial.list_recent_target_observations(
           actor: actor,
           load: [:target_account, :confidence_variant]
         ) do
      {:ok, observations} -> observations
      {:error, error} -> raise "failed to load target observations: #{inspect(error)}"
    end
  end
end
