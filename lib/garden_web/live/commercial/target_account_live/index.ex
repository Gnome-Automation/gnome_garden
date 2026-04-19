defmodule GnomeGardenWeb.Commercial.TargetAccountLive.Index do
  use GnomeGardenWeb, :live_view

  import GnomeGardenWeb.Commercial.Helpers

  alias GnomeGarden.Commercial

  @queues [:review, :promoted, :rejected, :archived]

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Target Accounts")
     |> assign(:selected_queue, :review)
     |> assign(:queue_counts, %{review: 0, promoted: 0, rejected: 0, archived: 0})
     |> assign(:high_intent_count, 0)
     |> assign(:targets_empty?, true)
     |> stream(:targets, [], reset: true)}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    queue = parse_queue(Map.get(params, "queue"))
    targets = load_targets_for_queue(queue, socket.assigns.current_user)
    queue_counts = load_queue_counts(socket.assigns.current_user)

    {:noreply,
     socket
     |> assign(:selected_queue, queue)
     |> assign(:queue_counts, queue_counts)
     |> assign(
       :high_intent_count,
       if(queue == :review, do: Enum.count(targets, &(&1.intent_score >= 70)), else: 0)
     )
     |> assign(:targets_empty?, targets == [])
     |> stream(:targets, targets, reset: true)}
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
          value={Integer.to_string(@queue_counts.review)}
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
          value={Integer.to_string(@queue_counts.promoted)}
          description="Target accounts already turned into formal commercial signals."
          icon="hero-arrow-up-right"
          accent="sky"
        />
      </div>

      <.section
        title="Discovery Backlog"
        description="Discovery is expected to grow. Manage it as explicit queues instead of one undifferentiated list."
        compact
        body_class="p-0"
      >
        <div class="border-b border-zinc-200 px-5 py-4 dark:border-white/10">
          <div class="flex flex-wrap gap-2">
            <.queue_link
              :for={queue <- queues()}
              queue={queue}
              selected_queue={@selected_queue}
              count={Map.fetch!(@queue_counts, queue)}
            />
            <.button navigate={~p"/commercial/observations"} class="ml-auto px-2.5 py-1.5 text-xs">
              <.icon name="hero-document-magnifying-glass" class="size-4" /> Observations
            </.button>
          </div>
        </div>

        <div :if={@targets_empty?} class="p-6 sm:p-7">
          <.empty_state
            icon="hero-magnifying-glass"
            title={"No #{queue_label(@selected_queue)} targets"}
            description={empty_description(@selected_queue)}
          >
            <:action>
              <.button navigate={~p"/commercial/targets/new"} variant="primary">
                Create Target
              </.button>
            </:action>
          </.empty_state>
        </div>

        <div :if={!@targets_empty?} class="overflow-x-auto">
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
                  Program / Scores
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
                    <p class="text-xs text-zinc-400 dark:text-zinc-500">
                      {(target.discovery_program && target.discovery_program.name) || "No program"}
                    </p>
                    <.tag color={:emerald}>Fit {target.fit_score}</.tag>
                    <.tag color={:sky}>Intent {target.intent_score}</.tag>
                  </div>
                </td>
                <td class="px-5 py-4 align-top text-zinc-600 dark:text-zinc-300">
                  <div class="space-y-1">
                    <p>{target.observation_count} observations</p>
                    <p class="text-sm text-zinc-500 dark:text-zinc-400">
                      {target.latest_observation_summary || "No observation summary yet"}
                    </p>
                    <p class="text-xs text-zinc-400 dark:text-zinc-500">
                      {format_datetime(target.latest_observed_at || target.inserted_at)}
                    </p>
                  </div>
                </td>
                <td class="px-5 py-4 align-top">
                  <div class="space-y-2">
                    <.status_badge status={target.status_variant}>
                      {format_atom(target.status)}
                    </.status_badge>
                    <.link
                      :if={target.promoted_signal}
                      navigate={~p"/commercial/signals/#{target.promoted_signal}"}
                      class="block text-xs font-medium text-emerald-600 hover:text-emerald-500 dark:text-emerald-300"
                    >
                      Open Signal
                    </.link>
                  </div>
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </.section>
    </.page>
    """
  end

  attr :queue, :atom, required: true
  attr :selected_queue, :atom, required: true
  attr :count, :integer, required: true

  defp queue_link(assigns) do
    selected? = assigns.queue == assigns.selected_queue

    assigns =
      assign(assigns,
        selected?: selected?,
        label: queue_label(assigns.queue)
      )

    ~H"""
    <.link
      patch={~p"/commercial/targets?queue=#{@queue}"}
      class={[
        "inline-flex items-center gap-2 rounded-full border px-3 py-1.5 text-sm font-medium transition",
        if(
          @selected?,
          do: "border-emerald-500 bg-emerald-500 text-white shadow-sm shadow-emerald-500/25",
          else:
            "border-zinc-200 bg-white text-zinc-600 hover:border-emerald-300 hover:text-emerald-600 dark:border-white/10 dark:bg-white/[0.03] dark:text-zinc-300 dark:hover:border-emerald-400/40 dark:hover:text-emerald-300"
        )
      ]}
    >
      <span>{@label}</span>
      <span class={[
        "inline-flex min-w-6 items-center justify-center rounded-full px-1.5 py-0.5 text-xs",
        if(@selected?,
          do: "bg-white/20 text-white",
          else: "bg-zinc-100 text-zinc-500 dark:bg-white/10 dark:text-zinc-300"
        )
      ]}>
        {@count}
      </span>
    </.link>
    """
  end

  defp load_targets_for_queue(:review, actor) do
    load_targets(fn ->
      Commercial.list_review_target_accounts(
        actor: actor,
        load: target_loads()
      )
    end)
  end

  defp load_targets_for_queue(:promoted, actor) do
    load_targets(fn ->
      Commercial.list_promoted_target_accounts(
        actor: actor,
        load: target_loads()
      )
    end)
  end

  defp load_targets_for_queue(:rejected, actor) do
    load_targets(fn ->
      Commercial.list_rejected_target_accounts(
        actor: actor,
        load: target_loads()
      )
    end)
  end

  defp load_targets_for_queue(:archived, actor) do
    load_targets(fn ->
      Commercial.list_archived_target_accounts(
        actor: actor,
        load: target_loads()
      )
    end)
  end

  defp load_queue_counts(actor) do
    @queues
    |> Enum.map(fn queue ->
      {queue, queue |> load_targets_for_queue(actor) |> length()}
    end)
    |> Map.new()
  end

  defp load_targets(fun) do
    case fun.() do
      {:ok, targets} -> targets
      {:error, error} -> raise "failed to load target accounts: #{inspect(error)}"
    end
  end

  defp target_loads do
    [
      :discovery_program,
      :organization,
      :promoted_signal,
      :status_variant,
      :observation_count,
      :latest_observed_at,
      :latest_observation_summary
    ]
  end

  defp parse_queue(nil), do: :review

  defp parse_queue(queue) when is_binary(queue) do
    queue
    |> String.to_existing_atom()
    |> then(fn queue_atom -> if queue_atom in @queues, do: queue_atom, else: :review end)
  rescue
    ArgumentError -> :review
  end

  defp queue_label(:review), do: "Review"
  defp queue_label(:promoted), do: "Promoted"
  defp queue_label(:rejected), do: "Rejected"
  defp queue_label(:archived), do: "Archived"

  defp empty_description(:review),
    do: "New discovery candidates will land here until someone promotes or rejects them."

  defp empty_description(:promoted),
    do: "Targets promoted into the signal inbox will appear here for traceability."

  defp empty_description(:rejected),
    do: "Rejected targets stay visible here so discovery can learn from what does not fit."

  defp empty_description(:archived),
    do: "Archived targets stay here as cold history without polluting the live review queue."

  defp queues, do: @queues
end
