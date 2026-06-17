defmodule GnomeGardenWeb.Finance.BankingSyncLive do
  use GnomeGardenWeb, :live_view

  import GnomeGardenWeb.Finance.Helpers

  alias GnomeGarden.Finance

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Sync Health")
     |> load_workspace()}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.page class="pb-8">
      <.page_header eyebrow="Finance">
        Sync Health
        <:subtitle>
          Provider pull history, webhook hints, and failed integration events.
        </:subtitle>
        <:actions>
          <.button navigate={~p"/finance/banking"}>
            <.icon name="hero-building-library" class="size-4" /> Banking
          </.button>
          <.button navigate={~p"/finance/banking/review"}>
            <.icon name="hero-queue-list" class="size-4" /> Review Queue
          </.button>
        </:actions>
      </.page_header>

      <div class="grid grid-cols-2 gap-2 sm:gap-3 xl:grid-cols-4">
        <.stat_card
          title="Syncs"
          value={Integer.to_string(@workspace.sync_run_count)}
          description="Recent provider pull attempts."
          icon="hero-arrow-path"
        />
        <.stat_card
          title="Failed"
          value={Integer.to_string(@workspace.failed_sync_count)}
          description="Sync attempts needing attention."
          icon="hero-exclamation-triangle"
          accent="rose"
        />
        <.stat_card
          title="Events"
          value={Integer.to_string(@workspace.event_count)}
          description="Webhook and sync audit events."
          icon="hero-bolt"
          accent="sky"
        />
        <.stat_card
          title="Pending"
          value={Integer.to_string(@workspace.pending_event_count)}
          description="Integration events not processed yet."
          icon="hero-clock"
          accent="amber"
        />
      </div>

      <div class="grid gap-4 xl:grid-cols-[minmax(0,1fr)_24rem]">
        <.section
          title="Sync History"
          description="Recent canonical provider pulls. Pull sync remains the source of truth; webhooks only wake or prioritize sync."
          compact
        >
          <div :if={@workspace.sync_runs == []} class="p-3 sm:p-4">
            <.empty_state
              icon="hero-arrow-path"
              title="No sync runs yet"
              description="Manual, scheduled, and webhook-triggered pulls will appear here."
            />
          </div>

          <div :if={@workspace.sync_runs != []} class="md:hidden">
            <div class="divide-y divide-base-content/10">
              <.sync_run_card :for={sync_run <- @workspace.sync_runs} sync_run={sync_run} />
            </div>
          </div>

          <div :if={@workspace.sync_runs != []} class="hidden md:block">
            <div class="overflow-x-auto">
              <table class="min-w-full divide-y divide-base-content/10 text-sm">
                <thead class="bg-base-200/60">
                  <tr>
                    <th class="px-4 py-3 text-left text-xs font-semibold uppercase text-base-content/50">
                      Started
                    </th>
                    <th class="px-4 py-3 text-left text-xs font-semibold uppercase text-base-content/50">
                      Source
                    </th>
                    <th class="px-4 py-3 text-left text-xs font-semibold uppercase text-base-content/50">
                      Connection
                    </th>
                    <th class="px-4 py-3 text-left text-xs font-semibold uppercase text-base-content/50">
                      Counts
                    </th>
                    <th class="px-4 py-3 text-left text-xs font-semibold uppercase text-base-content/50">
                      Status
                    </th>
                  </tr>
                </thead>
                <tbody class="divide-y divide-base-content/10">
                  <tr :for={sync_run <- @workspace.sync_runs} class="bg-base-100">
                    <td class="px-4 py-4 align-top text-base-content/70">
                      <div class="space-y-1">
                        <p>{format_datetime(sync_run.started_at)}</p>
                        <p class="text-xs text-base-content/45">
                          Finished {format_datetime(sync_run.finished_at)}
                        </p>
                      </div>
                    </td>
                    <td class="px-4 py-4 align-top text-base-content/70">
                      {format_atom(sync_run.source)}
                    </td>
                    <td class="px-4 py-4 align-top">
                      <div class="space-y-1">
                        <p class="font-medium text-base-content">
                          {connection_name(sync_run.bank_connection)}
                        </p>
                        <p class="text-xs text-base-content/45">
                          {connection_provider(sync_run.bank_connection)}
                        </p>
                      </div>
                    </td>
                    <td class="px-4 py-4 align-top text-base-content/70">
                      <div class="space-y-1 text-xs">
                        <p>{sync_run.accounts_seen_count || 0} accounts</p>
                        <p>{sync_run.transactions_seen_count || 0} transactions</p>
                        <p>
                          {sync_run.transactions_created_count || 0} created · {sync_run.transactions_updated_count ||
                            0} updated
                        </p>
                      </div>
                    </td>
                    <td class="px-4 py-4 align-top">
                      <div class="space-y-2">
                        <.status_badge status={sync_run_status_variant(sync_run.status)}>
                          {format_atom(sync_run.status)}
                        </.status_badge>
                        <p
                          :if={sync_run.error_message}
                          class="max-w-sm text-xs leading-5 text-error"
                        >
                          {sync_run.error_message}
                        </p>
                      </div>
                    </td>
                  </tr>
                </tbody>
              </table>
            </div>
          </div>
        </.section>

        <aside class="space-y-4">
          <.section title="Latest Sync" description="Most recent canonical pull.">
            <.latest_sync sync_run={@workspace.latest_sync_run} />
          </.section>

          <.section title="Integration Events" description="Webhook and sync event trail.">
            <div :if={@workspace.integration_events == []}>
              <.empty_state
                icon="hero-bolt"
                title="No integration events"
                description="Provider event hints and sync audit events will appear here."
                class="py-6"
              />
            </div>

            <div :if={@workspace.integration_events != []} class="space-y-2">
              <.integration_event_card
                :for={event <- @workspace.integration_events}
                event={event}
              />
            </div>
          </.section>
        </aside>
      </div>
    </.page>
    """
  end

  attr :sync_run, :map, required: true

  defp sync_run_card(assigns) do
    ~H"""
    <div class="space-y-3 bg-base-100 p-3">
      <div class="flex items-start justify-between gap-3">
        <div class="min-w-0">
          <p class="text-sm font-semibold text-base-content">
            {format_atom(@sync_run.source)}
          </p>
          <p class="mt-0.5 text-xs text-base-content/50">
            {format_datetime(@sync_run.started_at)}
          </p>
        </div>
        <.status_badge status={sync_run_status_variant(@sync_run.status)}>
          {format_atom(@sync_run.status)}
        </.status_badge>
      </div>

      <div class="grid grid-cols-3 gap-2 text-xs">
        <div>
          <p class="text-base-content/45">Seen</p>
          <p class="font-semibold">{@sync_run.transactions_seen_count || 0}</p>
        </div>
        <div>
          <p class="text-base-content/45">Created</p>
          <p class="font-semibold">{@sync_run.transactions_created_count || 0}</p>
        </div>
        <div>
          <p class="text-base-content/45">Updated</p>
          <p class="font-semibold">{@sync_run.transactions_updated_count || 0}</p>
        </div>
      </div>

      <p :if={@sync_run.error_message} class="line-clamp-3 text-xs leading-5 text-error">
        {@sync_run.error_message}
      </p>
    </div>
    """
  end

  attr :sync_run, :any, required: true

  defp latest_sync(assigns) do
    ~H"""
    <div :if={is_nil(@sync_run)}>
      <.empty_state
        icon="hero-arrow-path"
        title="No sync runs yet"
        description="Run a sync from Banking after credentials are configured."
        class="py-6"
      />
    </div>

    <div :if={@sync_run} class="rounded-lg border border-base-content/10 bg-base-200 p-3">
      <div class="flex items-start justify-between gap-3">
        <div class="min-w-0">
          <p class="text-sm font-semibold text-base-content">{format_atom(@sync_run.source)}</p>
          <p class="mt-1 text-xs text-base-content/55">
            {format_datetime(@sync_run.started_at)}
          </p>
        </div>
        <.status_badge status={sync_run_status_variant(@sync_run.status)}>
          {format_atom(@sync_run.status)}
        </.status_badge>
      </div>

      <div class="mt-3 grid grid-cols-3 gap-2 text-xs">
        <div>
          <p class="text-base-content/45">Accounts</p>
          <p class="font-semibold">{@sync_run.accounts_seen_count || 0}</p>
        </div>
        <div>
          <p class="text-base-content/45">Created</p>
          <p class="font-semibold">{@sync_run.transactions_created_count || 0}</p>
        </div>
        <div>
          <p class="text-base-content/45">Updated</p>
          <p class="font-semibold">{@sync_run.transactions_updated_count || 0}</p>
        </div>
      </div>
    </div>
    """
  end

  attr :event, :map, required: true

  defp integration_event_card(assigns) do
    ~H"""
    <div class="rounded-lg border border-base-content/10 bg-base-200 p-3">
      <div class="flex items-start justify-between gap-3">
        <div class="min-w-0">
          <p class="truncate text-sm font-semibold text-base-content">{@event.event_type}</p>
          <p class="mt-1 text-xs text-base-content/55">
            {format_atom(@event.source)} · {format_datetime(@event.received_at)}
          </p>
        </div>
        <.status_badge status={integration_event_status_variant(@event.status)}>
          {format_atom(@event.status)}
        </.status_badge>
      </div>

      <p :if={@event.error_message} class="mt-2 line-clamp-3 text-xs leading-5 text-error">
        {@event.error_message}
      </p>
    </div>
    """
  end

  defp load_workspace(socket) do
    workspace = Finance.get_bank_sync_history_workspace!(actor: socket.assigns.current_user)
    assign(socket, :workspace, workspace)
  end

  defp connection_name(%Ash.NotLoaded{}), do: "Unknown connection"
  defp connection_name(nil), do: "Unknown connection"
  defp connection_name(%{name: name}) when is_binary(name), do: name
  defp connection_name(_), do: "Unknown connection"

  defp connection_provider(%Ash.NotLoaded{}), do: "-"
  defp connection_provider(nil), do: "-"

  defp connection_provider(%{provider: provider, environment: environment}) do
    "#{format_atom(provider)} · #{format_atom(environment)}"
  end

  defp sync_run_status_variant(:succeeded), do: :success
  defp sync_run_status_variant(:failed), do: :error
  defp sync_run_status_variant(:partial), do: :warning
  defp sync_run_status_variant(:running), do: :info
  defp sync_run_status_variant(_), do: :default

  defp integration_event_status_variant(:processed), do: :success
  defp integration_event_status_variant(:failed), do: :error
  defp integration_event_status_variant(:processing), do: :info
  defp integration_event_status_variant(:ignored), do: :default
  defp integration_event_status_variant(_), do: :warning
end
