defmodule GnomeGardenWeb.Commercial.TargetAccountLive.Index do
  use GnomeGardenWeb, :live_view

  import GnomeGardenWeb.Commercial.Helpers

  alias GnomeGarden.Commercial

  @impl true
  def mount(_params, _session, socket) do
    review_targets = load_review_targets(socket.assigns.current_user)
    promoted_targets = load_promoted_targets(socket.assigns.current_user)

    {:ok,
     socket
     |> assign(:page_title, "Target Accounts")
     |> assign(:review_count, length(review_targets))
     |> assign(:promoted_count, length(promoted_targets))
     |> assign(:high_intent_count, Enum.count(review_targets, &(&1.intent_score >= 70)))
     |> stream(:targets, review_targets)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.page class="pb-8">
      <.page_header eyebrow="Commercial">
        Target Accounts
        <:subtitle>
          Broad outbound discovery stays here first. Promote only the best-fit accounts into the signal inbox once a human decides they deserve active commercial energy.
        </:subtitle>
        <:actions>
          <.button navigate={~p"/commercial/signals"}>
            <.icon name="hero-inbox-stack" class="size-4" /> Signal Inbox
          </.button>
          <.button navigate={~p"/commercial/targets/new"} variant="primary">
            <.icon name="hero-plus" class="size-4" /> New Target
          </.button>
        </:actions>
      </.page_header>

      <div class="grid gap-4 md:grid-cols-3">
        <.stat_card
          title="Review Queue"
          value={Integer.to_string(@review_count)}
          description="Discovered accounts still waiting for human review or promotion."
          icon="hero-magnifying-glass"
        />
        <.stat_card
          title="High Intent"
          value={Integer.to_string(@high_intent_count)}
          description="Targets with strong evidence that something operational is changing right now."
          icon="hero-fire"
          accent="amber"
        />
        <.stat_card
          title="Already Promoted"
          value={Integer.to_string(@promoted_count)}
          description="Target accounts already turned into formal commercial signals."
          icon="hero-arrow-up-right"
          accent="sky"
        />
      </div>

      <.section
        title="Discovery Review Queue"
        description="This is where broad lead-finder output gets triaged before it enters the formal signal inbox."
        compact
        body_class="p-0"
      >
        <div :if={@review_count == 0} class="p-6 sm:p-7">
          <.empty_state
            icon="hero-magnifying-glass"
            title="No targets waiting"
            description="Once company discovery and scouting flows are active, the review queue will land here."
          >
            <:action>
              <.button navigate={~p"/commercial/targets/new"} variant="primary">
                Create Target
              </.button>
            </:action>
          </.empty_state>
        </div>

        <div :if={@review_count > 0} class="overflow-x-auto">
          <table class="min-w-full divide-y divide-zinc-200 text-sm dark:divide-white/10">
            <thead class="bg-zinc-50 dark:bg-white/[0.03]">
              <tr>
                <th class="px-5 py-3 text-left font-medium text-zinc-500 dark:text-zinc-400">
                  Target
                </th>
                <th class="px-5 py-3 text-left font-medium text-zinc-500 dark:text-zinc-400">
                  Organization
                </th>
                <th class="px-5 py-3 text-left font-medium text-zinc-500 dark:text-zinc-400">
                  Scores
                </th>
                <th class="px-5 py-3 text-left font-medium text-zinc-500 dark:text-zinc-400">
                  Evidence
                </th>
                <th class="px-5 py-3 text-left font-medium text-zinc-500 dark:text-zinc-400">
                  Status
                </th>
              </tr>
            </thead>
            <tbody
              id="targets"
              phx-update="stream"
              class="divide-y divide-zinc-200 dark:divide-white/10"
            >
              <tr :for={{dom_id, target} <- @streams.targets} id={dom_id}>
                <td class="px-5 py-4 align-top">
                  <div class="space-y-1">
                    <.link
                      navigate={~p"/commercial/targets/#{target}"}
                      class="font-medium text-zinc-900 hover:text-emerald-600 dark:text-white"
                    >
                      {target.name}
                    </.link>
                    <p class="text-sm text-zinc-500 dark:text-zinc-400">
                      {target.website_domain || "-"}
                    </p>
                  </div>
                </td>
                <td class="px-5 py-4 align-top text-zinc-600 dark:text-zinc-300">
                  {(target.organization && target.organization.name) || "-"}
                </td>
                <td class="px-5 py-4 align-top">
                  <div class="space-y-2">
                    <.tag color={:emerald}>Fit {target.fit_score}</.tag>
                    <.tag color={:sky}>Intent {target.intent_score}</.tag>
                  </div>
                </td>
                <td class="px-5 py-4 align-top text-zinc-600 dark:text-zinc-300">
                  <div class="space-y-1">
                    <p>{target.observation_count} observations</p>
                    <p class="text-xs text-zinc-400 dark:text-zinc-500">
                      {format_datetime(target.latest_observed_at || target.inserted_at)}
                    </p>
                  </div>
                </td>
                <td class="px-5 py-4 align-top">
                  <.status_badge status={target.status_variant}>
                    {format_atom(target.status)}
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

  defp load_review_targets(actor) do
    case Commercial.list_review_target_accounts(
           actor: actor,
           load: [
             :discovery_program,
             :organization,
             :status_variant,
             :observation_count,
             :latest_observed_at
           ]
         ) do
      {:ok, targets} -> targets
      {:error, error} -> raise "failed to load target accounts: #{inspect(error)}"
    end
  end

  defp load_promoted_targets(actor) do
    case Commercial.list_promoted_target_accounts(actor: actor) do
      {:ok, targets} -> targets
      {:error, error} -> raise "failed to load promoted target accounts: #{inspect(error)}"
    end
  end
end
