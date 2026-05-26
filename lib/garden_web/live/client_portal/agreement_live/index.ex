defmodule GnomeGardenWeb.ClientPortal.AgreementLive.Index do
  use GnomeGardenWeb, :live_view

  alias GnomeGarden.Commercial

  @impl true
  def mount(_params, _session, socket) do
    actor = socket.assigns.current_client_user

    agreements =
      case Commercial.list_portal_agreements(actor: actor) do
        {:ok, list} -> list
        _ -> []
      end

    {:ok,
     socket
     |> assign(:page_title, "Agreements")
     |> assign(:agreements, agreements)
     |> assign(:show_export_form, false)}
  end

  @impl true
  def handle_event("toggle_export_form", _params, socket) do
    {:noreply, assign(socket, :show_export_form, !socket.assigns.show_export_form)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.page max_width="max-w-full" class="pb-8">
      <.page_header eyebrow="Client Portal">
        Agreements
        <:subtitle>Your active and historical service agreements.</:subtitle>
        <:actions>
          <.button phx-click="toggle_export_form">
            Batch Export
          </.button>
        </:actions>
      </.page_header>

      <%= if @show_export_form do %>
        <div class="mb-6 rounded-lg border border-gray-200 bg-white p-5 shadow-sm dark:border-white/10 dark:bg-white/5">
          <h3 class="text-sm font-semibold text-gray-900 dark:text-white mb-4">Batch Export</h3>
          <form method="get" action="/portal/agreements/batch-export" target="_blank" class="grid grid-cols-1 gap-4 sm:grid-cols-3 items-end">
            <input type="hidden" name="format" value="pdf" />
            <div>
              <label class="block text-sm/6 font-medium text-gray-900 dark:text-white">From</label>
              <input type="date" name="from" class="mt-1 block w-full rounded-md bg-white px-3 py-1.5 text-base text-gray-900 outline-1 -outline-offset-1 outline-gray-300 focus:outline-2 focus:-outline-offset-2 focus:outline-emerald-600 sm:text-sm/6 dark:bg-white/5 dark:text-white dark:outline-white/10" />
            </div>
            <div>
              <label class="block text-sm/6 font-medium text-gray-900 dark:text-white">To</label>
              <input type="date" name="to" class="mt-1 block w-full rounded-md bg-white px-3 py-1.5 text-base text-gray-900 outline-1 -outline-offset-1 outline-gray-300 focus:outline-2 focus:-outline-offset-2 focus:outline-emerald-600 sm:text-sm/6 dark:bg-white/5 dark:text-white dark:outline-white/10" />
            </div>
            <div>
              <button type="submit" class="rounded-md bg-emerald-600 px-3 py-2 text-sm font-semibold text-white shadow-xs hover:bg-emerald-500 cursor-pointer transition-colors">
                Download
              </button>
            </div>
          </form>
          <p class="mt-2 text-xs text-gray-500 dark:text-gray-400">Filter by agreement start date. Leave blank to export all.</p>
        </div>
      <% end %>

      <.section body_class="p-0">
        <div :if={@agreements != []} class="overflow-x-auto">
          <table class="min-w-full divide-y divide-base-content/10">
            <thead>
              <tr class="bg-base-200/50">
                <th class="px-4 py-3 text-left text-xs font-semibold uppercase tracking-wider text-base-content/60">Name</th>
                <th class="px-4 py-3 text-left text-xs font-semibold uppercase tracking-wider text-base-content/60">Type</th>
                <th class="px-4 py-3 text-left text-xs font-semibold uppercase tracking-wider text-base-content/60">Billing</th>
                <th class="px-4 py-3 text-left text-xs font-semibold uppercase tracking-wider text-base-content/60">Start</th>
                <th class="px-4 py-3 text-left text-xs font-semibold uppercase tracking-wider text-base-content/60">End</th>
                <th class="px-4 py-3 text-left text-xs font-semibold uppercase tracking-wider text-base-content/60">Status</th>
              </tr>
            </thead>
            <tbody class="divide-y divide-base-content/5">
              <tr :for={ag <- @agreements} class="hover:bg-base-200/30 transition-colors">
                <td class="px-4 py-3 text-sm text-base-content">
                  <.link navigate={~p"/portal/agreements/#{ag.id}"} class="text-emerald-600 hover:text-emerald-500 hover:underline font-medium">
                    <%= ag.name %>
                  </.link>
                </td>
                <td class="px-4 py-3 text-sm text-base-content/60 capitalize"><%= ag.agreement_type || "—" %></td>
                <td class="px-4 py-3 text-sm text-base-content/60"><%= ag.billing_model |> to_string() |> String.replace("_", " ") |> String.capitalize() %></td>
                <td class="px-4 py-3 text-sm text-base-content/60"><%= if ag.start_on, do: Date.to_string(ag.start_on), else: "—" %></td>
                <td class="px-4 py-3 text-sm text-base-content/60"><%= if ag.end_on, do: Date.to_string(ag.end_on), else: "—" %></td>
                <td class="px-4 py-3">
                  <.status_badge status={agreement_status_variant(ag.status)}>
                    <%= String.capitalize(to_string(ag.status)) %>
                  </.status_badge>
                </td>
              </tr>
            </tbody>
          </table>
        </div>
        <.empty_state
          :if={@agreements == []}
          icon="hero-document-text"
          title="No agreements"
          description="You have no active or historical agreements."
        />
      </.section>
    </.page>
    """
  end

  defp agreement_status_variant(:active), do: :success
  defp agreement_status_variant(:pending_signature), do: :warning
  defp agreement_status_variant(:suspended), do: :warning
  defp agreement_status_variant(:completed), do: :default
  defp agreement_status_variant(:terminated), do: :error
  defp agreement_status_variant(_), do: :default
end
