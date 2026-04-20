defmodule GnomeGardenWeb.Commercial.SignalLive.Index do
  use GnomeGardenWeb, :live_view

  import GnomeGardenWeb.Commercial.Helpers

  alias GnomeGarden.Acquisition
  alias GnomeGarden.Commercial

  @impl true
  def mount(_params, _session, socket) do
    signals = load_signals(socket.assigns.current_user)
    finding_ids_by_signal = finding_ids_by_signal(signals)

    {:ok,
     socket
     |> assign(:page_title, "Signal Queue")
     |> assign(:finding_ids_by_signal, finding_ids_by_signal)
     |> assign(:queue_count, length(signals))
     |> assign(:accepted_count, Enum.count(signals, &(&1.status == :accepted)))
     |> assign(:converted_count, 0)
     |> stream(:signals, signals)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.page class="pb-8">
      <.page_header eyebrow="Commercial">
        Signal Queue
        <:subtitle>
          Cross-channel commercial opportunities waiting on active follow-up. Raw procurement and discovery findings stay in acquisition until they are intentionally advanced.
        </:subtitle>
        <:actions>
          <.button navigate={~p"/commercial/pursuits"}>
            <.icon name="hero-arrow-trending-up" class="size-4" /> Pursuits
          </.button>
          <.button navigate={~p"/commercial/signals/new"} variant="primary">
            <.icon name="hero-plus" class="size-4" /> New Signal
          </.button>
        </:actions>
      </.page_header>

      <div class="grid gap-4 md:grid-cols-3">
        <.stat_card
          title="Queue Signals"
          value={Integer.to_string(@queue_count)}
          description="Commercial-ready signals waiting on review, acceptance, or conversion."
          icon="hero-inbox-stack"
        />
        <.stat_card
          title="Ready To Convert"
          value={Integer.to_string(@accepted_count)}
          description="Accepted signals that can become pursuits as soon as someone takes ownership."
          icon="hero-check-badge"
          accent="sky"
        />
        <.stat_card
          title="Converted Today"
          value={Integer.to_string(@converted_count)}
          description="This will become a live operational metric once conversion activity is instrumented."
          icon="hero-arrow-path-rounded-square"
          accent="amber"
        />
      </div>

      <.section
        title="Commercial Intake"
        description="Review the queue, assign context, and decide what becomes active pipeline."
        compact
        body_class="p-0"
      >
        <div :if={@queue_count == 0} class="p-6 sm:p-7">
          <.empty_state
            icon="hero-inbox-stack"
            title="No signals waiting"
            description="Accepted procurement opportunities, promoted targets, referrals, and manual signals will appear here."
          >
            <:action>
              <.button navigate={~p"/commercial/signals/new"} variant="primary">
                Create Signal
              </.button>
            </:action>
          </.empty_state>
        </div>

        <div :if={@queue_count > 0} class="overflow-x-auto">
          <table class="min-w-full divide-y divide-zinc-200 text-sm dark:divide-white/10">
            <thead class="bg-zinc-50 dark:bg-white/[0.03]">
              <tr>
                <th class="px-5 py-3 text-left font-medium text-zinc-500 dark:text-zinc-400">
                  Signal
                </th>
                <th class="px-5 py-3 text-left font-medium text-zinc-500 dark:text-zinc-400">Type</th>
                <th class="px-5 py-3 text-left font-medium text-zinc-500 dark:text-zinc-400">
                  Organization
                </th>
                <th class="px-5 py-3 text-left font-medium text-zinc-500 dark:text-zinc-400">
                  Observed
                </th>
                <th class="px-5 py-3 text-left font-medium text-zinc-500 dark:text-zinc-400">
                  Status
                </th>
                <th class="px-5 py-3 text-left font-medium text-zinc-500 dark:text-zinc-400">
                  Provenance
                </th>
              </tr>
            </thead>
            <tbody
              id="signals"
              phx-update="stream"
              class="divide-y divide-zinc-200 dark:divide-white/10"
            >
              <tr :for={{dom_id, signal} <- @streams.signals} id={dom_id}>
                <td class="px-5 py-4 align-top">
                  <div class="space-y-1">
                    <.link
                      navigate={~p"/commercial/signals/#{signal}"}
                      class="font-medium text-zinc-900 hover:text-emerald-600 dark:text-white"
                    >
                      {signal.title}
                    </.link>
                    <p class="max-w-xl text-sm text-zinc-500 dark:text-zinc-400">
                      {signal.description || "No description yet."}
                    </p>
                  </div>
                </td>
                <td class="px-5 py-4 align-top">
                  <div class="flex flex-wrap gap-2">
                    <.tag color={:zinc}>{format_atom(signal.signal_type)}</.tag>
                    <.tag color={:emerald}>{format_atom(signal.source_channel)}</.tag>
                  </div>
                </td>
                <td class="px-5 py-4 align-top text-zinc-600 dark:text-zinc-300">
                  {(signal.organization && signal.organization.name) || "-"}
                </td>
                <td class="px-5 py-4 align-top text-zinc-600 dark:text-zinc-300">
                  {format_datetime(signal.observed_at || signal.inserted_at)}
                </td>
                <td class="px-5 py-4 align-top">
                  <.status_badge status={signal.status_variant}>
                    {format_atom(signal.status)}
                  </.status_badge>
                </td>
                <td class="px-5 py-4 align-top">
                  <div class="space-y-2">
                    <span
                      :if={signal.procurement_bid}
                      class="badge badge-outline badge-sm border-amber-300 text-amber-700 dark:border-amber-400/30 dark:text-amber-200"
                    >
                      Procurement Bid
                    </span>
                    <.link
                      :if={Map.get(@finding_ids_by_signal, signal.id)}
                      navigate={
                        ~p"/acquisition/findings/#{Map.fetch!(@finding_ids_by_signal, signal.id)}"
                      }
                      class="block text-xs font-medium text-emerald-600 hover:text-emerald-500 dark:text-emerald-300"
                    >
                      Open Intake Finding
                    </.link>
                    <div :if={signal.procurement_bid} class="flex flex-wrap gap-1">
                      <span class={tier_badge(signal.procurement_bid.score_tier)}>
                        {format_score_tier(signal.procurement_bid.score_tier)}
                      </span>
                      <span
                        :if={signal.procurement_bid.score_source_confidence}
                        class={
                          source_confidence_badge(signal.procurement_bid.score_source_confidence)
                        }
                      >
                        {format_source_confidence(signal.procurement_bid.score_source_confidence)}
                      </span>
                    </div>
                    <p
                      :if={signal.procurement_bid && signal.procurement_bid.score_risk_flags != []}
                      class="max-w-[14rem] text-xs text-zinc-500 dark:text-zinc-400"
                    >
                      Watchout: {List.first(signal.procurement_bid.score_risk_flags)}
                    </p>
                    <span
                      :if={!signal.procurement_bid}
                      class="text-xs text-zinc-400 dark:text-zinc-500"
                    >
                      {signal_provenance_label(signal, @finding_ids_by_signal)}
                    </span>
                    <div
                      :if={discovery_signal?(signal, @finding_ids_by_signal)}
                      class="flex flex-wrap gap-1"
                    >
                      <span class="badge badge-info badge-sm">
                        Fit {metadata_value(signal.metadata, :fit_score) || "-"}
                      </span>
                      <span class="badge badge-info badge-sm">
                        Intent {metadata_value(signal.metadata, :intent_score) || "-"}
                      </span>
                    </div>
                    <p
                      :if={
                        discovery_signal?(signal, @finding_ids_by_signal) &&
                          discovery_watchouts(signal) != []
                      }
                      class="max-w-[14rem] text-xs text-zinc-500 dark:text-zinc-400"
                    >
                      Watchout: {List.first(discovery_watchouts(signal))}
                    </p>
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

  defp load_signals(actor) do
    case Commercial.list_signal_queue(
           actor: actor,
           load: [:organization, :site, :pursuits, :status_variant, :procurement_bid]
         ) do
      {:ok, signals} -> signals
      {:error, error} -> raise "failed to load signals: #{inspect(error)}"
    end
  end

  defp tier_badge(:hot), do: "badge badge-error badge-sm"
  defp tier_badge(:warm), do: "badge badge-warning badge-sm"
  defp tier_badge(:prospect), do: "badge badge-info badge-sm"
  defp tier_badge(_), do: "badge badge-ghost badge-sm"

  defp finding_ids_by_signal(signals) do
    Map.new(signals, fn signal ->
      finding_id =
        case Acquisition.get_finding_by_signal(signal.id) do
          {:ok, finding} -> finding.id
          _ -> nil
        end

      {signal.id, finding_id}
    end)
    |> Enum.reject(fn {_signal_id, finding_id} -> is_nil(finding_id) end)
    |> Map.new()
  end

  defp format_score_tier(nil), do: "-"

  defp format_score_tier(tier) do
    tier
    |> to_string()
    |> String.upcase()
  end

  defp source_confidence_badge(:direct), do: "badge badge-success badge-sm"
  defp source_confidence_badge(:aggregated), do: "badge badge-warning badge-sm"
  defp source_confidence_badge(:unknown), do: "badge badge-ghost badge-sm"
  defp source_confidence_badge(_), do: "badge badge-ghost badge-sm"

  defp format_source_confidence(confidence) do
    confidence
    |> to_string()
    |> String.replace("_", " ")
    |> String.capitalize()
  end

  defp signal_provenance_label(signal, finding_ids_by_signal) do
    cond do
      discovery_signal?(signal, finding_ids_by_signal) -> "Promoted Discovery Finding"
      true -> "Native commercial signal"
    end
  end

  defp discovery_signal?(signal, finding_ids_by_signal) do
    signal.source_channel == :agent_discovery and Map.has_key?(finding_ids_by_signal, signal.id)
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

  defp metadata_value(metadata, key) when is_map(metadata),
    do: Map.get(metadata, key) || Map.get(metadata, to_string(key))

  defp metadata_value(_metadata, _key), do: nil
end
