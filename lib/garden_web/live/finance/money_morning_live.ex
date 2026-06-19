defmodule GnomeGardenWeb.Finance.MoneyMorningLive do
  use GnomeGardenWeb, :live_view

  import GnomeGardenWeb.Finance.Helpers

  alias GnomeGarden.Finance

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Money Morning")
     |> load_workspace()}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.page class="pb-8">
      <.page_header eyebrow="Finance">
        Money Morning
        <:subtitle>
          Everything that needs a decision today — bill, send, review, and chase in one pass.
        </:subtitle>
      </.page_header>

      <div class="grid gap-2 sm:grid-cols-3">
        <.stat_card
          title="To do"
          value={"#{@workspace.action_count}"}
          description="queues needing attention"
          icon="hero-check-circle"
          accent="emerald"
        />
        <.stat_card
          title="Cash this week"
          value={format_amount(@workspace.cash_received_this_week)}
          description="received in the last 7 days"
          icon="hero-banknotes"
          accent="sky"
        />
        <.stat_card
          title="Cash balance"
          value={format_amount(@workspace.cash_balance)}
          description="across bank accounts"
          icon="hero-currency-dollar"
        />
      </div>

      <.section
        title="Today's queue"
        description="Each item links straight to where you act on it."
      >
        <div :if={@workspace.action_count == 0}>
          <.empty_state
            icon="hero-check-circle"
            title="You're clear"
            description="Nothing is waiting to be billed, sent, reviewed, or chased right now."
          />
        </div>

        <div :if={@workspace.action_count > 0} class="space-y-2">
          <.queue_row :for={queue <- actionable(@workspace.queues)} queue={queue} />
        </div>
      </.section>
    </.page>
    """
  end

  attr :queue, :map, required: true

  defp queue_row(assigns) do
    ~H"""
    <.link
      navigate={@queue.path}
      class="flex items-center justify-between gap-3 rounded-lg border border-base-content/10 bg-base-200 px-3 py-3 hover:bg-base-300"
    >
      <div class="flex min-w-0 items-center gap-3">
        <.icon name={@queue.icon} class="size-5 shrink-0 text-emerald-600" />
        <div class="min-w-0">
          <p class="truncate font-semibold text-base-content">{@queue.label}</p>
          <p :if={@queue.amount} class="text-xs text-base-content/60">
            {format_amount(@queue.amount)}
          </p>
        </div>
      </div>

      <div class="flex shrink-0 items-center gap-3">
        <span class="rounded-full bg-emerald-600 px-2.5 py-0.5 text-sm font-semibold text-white tabular-nums">
          {@queue.count}
        </span>
        <.icon name="hero-chevron-right" class="size-4 text-base-content/40" />
      </div>
    </.link>
    """
  end

  defp actionable(queues), do: Enum.filter(queues, &(&1.count > 0))

  defp load_workspace(socket) do
    workspace = Finance.get_money_morning_workspace!(actor: socket.assigns.current_user)
    assign(socket, :workspace, workspace)
  end
end
