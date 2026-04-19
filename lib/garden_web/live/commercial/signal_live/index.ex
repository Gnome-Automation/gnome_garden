defmodule GnomeGardenWeb.Commercial.SignalLive.Index do
  use GnomeGardenWeb, :live_view

  import GnomeGardenWeb.Commercial.Helpers

  alias GnomeGarden.Commercial

  @impl true
  def mount(_params, _session, socket) do
    signals = load_signals(socket.assigns.current_user)

    {:ok,
     socket
     |> assign(:page_title, "Signal Inbox")
     |> assign(:open_count, length(signals))
     |> assign(:accepted_count, Enum.count(signals, &(&1.status == :accepted)))
     |> assign(:converted_count, 0)
     |> stream(:signals, signals)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.page class="pb-8">
      <.page_header eyebrow="Commercial">
        Signal Inbox
        <:subtitle>
          Agents and operators can drop raw market signals here first, then qualify what deserves real pursuit energy.
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
          title="Open Signals"
          value={Integer.to_string(@open_count)}
          description="New, reviewing, and accepted items waiting on a commercial decision."
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
        title="Open Intake"
        description="Review the feed, assign context, and decide what becomes active pipeline."
        compact
        body_class="p-0"
      >
        <div :if={@open_count == 0} class="p-6 sm:p-7">
          <.empty_state
            icon="hero-inbox-stack"
            title="No signals waiting"
            description="Once agents start discovering bids, referrals, and target accounts, they will appear here."
          >
            <:action>
              <.button navigate={~p"/commercial/signals/new"} variant="primary">
                Create Signal
              </.button>
            </:action>
          </.empty_state>
        </div>

        <div :if={@open_count > 0} class="overflow-x-auto">
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
              </tr>
            </tbody>
          </table>
        </div>
      </.section>
    </.page>
    """
  end

  defp load_signals(actor) do
    case Commercial.list_open_signals(
           actor: actor,
           load: [:organization, :site, :pursuits, :status_variant]
         ) do
      {:ok, signals} -> signals
      {:error, error} -> raise "failed to load signals: #{inspect(error)}"
    end
  end
end
