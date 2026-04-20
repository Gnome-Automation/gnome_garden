defmodule GnomeGardenWeb.Commercial.PursuitLive.Index do
  use GnomeGardenWeb, :live_view

  import GnomeGardenWeb.Commercial.Helpers

  alias GnomeGarden.Commercial

  @impl true
  def mount(_params, _session, socket) do
    pursuits = load_pursuits(socket.assigns.current_user)

    {:ok,
     socket
     |> assign(:page_title, "Pursuits")
     |> assign(:active_count, length(pursuits))
     |> assign(:proposed_count, Enum.count(pursuits, &(&1.stage in [:proposed, :negotiating])))
     |> assign(:weighted_total, weighted_total(pursuits))
     |> stream(:pursuits, pursuits)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.page class="pb-8">
      <.page_header eyebrow="Commercial">
        Pursuits
        <:subtitle>
          Qualified signals become owned commercial pursuits with forecast, stage discipline, and downstream proposal work.
        </:subtitle>
        <:actions>
          <.button navigate={~p"/commercial/signals"}>
            <.icon name="hero-inbox-stack" class="size-4" /> Signal Queue
          </.button>
          <.button navigate={~p"/commercial/pursuits/new"} variant="primary">
            <.icon name="hero-plus" class="size-4" /> New Pursuit
          </.button>
        </:actions>
      </.page_header>

      <div class="grid gap-4 md:grid-cols-3">
        <.stat_card
          title="Active Pursuits"
          value={Integer.to_string(@active_count)}
          description="Commercial opportunities currently being qualified, priced, proposed, or negotiated."
          icon="hero-arrow-trending-up"
        />
        <.stat_card
          title="Late Stage"
          value={Integer.to_string(@proposed_count)}
          description="Pursuits already in proposal or negotiation and closest to revenue realization."
          icon="hero-document-check"
          accent="sky"
        />
        <.stat_card
          title="Weighted Pipeline"
          value={format_amount(@weighted_total)}
          description="Expected value after multiplying each pursuit by its current probability."
          icon="hero-banknotes"
          accent="amber"
        />
      </div>

      <.section
        title="Active Pipeline"
        description="Keep the pipeline intentionally small and explicit so every active pursuit has a real owner."
        compact
        body_class="p-0"
      >
        <div :if={@active_count == 0} class="p-6 sm:p-7">
          <.empty_state
            icon="hero-arrow-trending-up"
            title="No pursuits yet"
            description="Create a pursuit directly, or accept a signal in the queue and convert it into owned pipeline."
          >
            <:action>
              <.button navigate={~p"/commercial/signals"} variant="primary">
                Open Signal Queue
              </.button>
            </:action>
          </.empty_state>
        </div>

        <div :if={@active_count > 0} class="overflow-x-auto">
          <table class="min-w-full divide-y divide-zinc-200 text-sm dark:divide-white/10">
            <thead class="bg-zinc-50 dark:bg-white/[0.03]">
              <tr>
                <th class="px-5 py-3 text-left font-medium text-zinc-500 dark:text-zinc-400">
                  Pursuit
                </th>
                <th class="px-5 py-3 text-left font-medium text-zinc-500 dark:text-zinc-400">
                  Organization
                </th>
                <th class="px-5 py-3 text-left font-medium text-zinc-500 dark:text-zinc-400">
                  Stage
                </th>
                <th class="px-5 py-3 text-left font-medium text-zinc-500 dark:text-zinc-400">
                  Target
                </th>
                <th class="px-5 py-3 text-left font-medium text-zinc-500 dark:text-zinc-400">
                  Close
                </th>
              </tr>
            </thead>
            <tbody
              id="pursuits"
              phx-update="stream"
              class="divide-y divide-zinc-200 dark:divide-white/10"
            >
              <tr :for={{dom_id, pursuit} <- @streams.pursuits} id={dom_id}>
                <td class="px-5 py-4 align-top">
                  <div class="space-y-1">
                    <.link
                      navigate={~p"/commercial/pursuits/#{pursuit}"}
                      class="font-medium text-zinc-900 hover:text-emerald-600 dark:text-white"
                    >
                      {pursuit.name}
                    </.link>
                    <p class="text-sm text-zinc-500 dark:text-zinc-400">
                      {format_atom(pursuit.pursuit_type)}
                    </p>
                  </div>
                </td>
                <td class="px-5 py-4 align-top text-zinc-600 dark:text-zinc-300">
                  {(pursuit.organization && pursuit.organization.name) || "-"}
                </td>
                <td class="px-5 py-4 align-top">
                  <div class="space-y-2">
                    <.status_badge status={pursuit.stage_variant}>
                      {format_atom(pursuit.stage)}
                    </.status_badge>
                    <div>
                      <.tag color={:zinc}>{pursuit.probability}%</.tag>
                    </div>
                  </div>
                </td>
                <td class="px-5 py-4 align-top text-zinc-600 dark:text-zinc-300">
                  <div class="space-y-1">
                    <p>{format_amount(pursuit.target_value)}</p>
                    <p class="text-xs text-zinc-400 dark:text-zinc-500">
                      Weighted {format_amount(pursuit.weighted_value)}
                    </p>
                  </div>
                </td>
                <td class="px-5 py-4 align-top text-zinc-600 dark:text-zinc-300">
                  {format_date(pursuit.expected_close_on)}
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </.section>
    </.page>
    """
  end

  defp load_pursuits(actor) do
    case Commercial.list_active_pursuits(
           actor: actor,
           load: [:organization, :signal, :weighted_value, :proposal_count, :stage_variant]
         ) do
      {:ok, pursuits} -> pursuits
      {:error, error} -> raise "failed to load pursuits: #{inspect(error)}"
    end
  end

  defp weighted_total(pursuits) do
    Enum.reduce(pursuits, Decimal.new(0), fn pursuit, total ->
      Decimal.add(total, pursuit.weighted_value || Decimal.new(0))
    end)
  end
end
