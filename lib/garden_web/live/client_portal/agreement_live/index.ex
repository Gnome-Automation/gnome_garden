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
     |> assign(:agreements, agreements)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <h1 class="text-2xl font-bold text-gray-900 dark:text-white mb-6">Agreements</h1>

      <div class="bg-white dark:bg-gray-900 rounded-lg shadow overflow-hidden">
        <table class="min-w-full divide-y divide-gray-200 dark:divide-gray-700">
          <thead class="bg-gray-50 dark:bg-gray-800">
            <tr>
              <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 dark:text-gray-400 uppercase">Name</th>
              <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 dark:text-gray-400 uppercase">Type</th>
              <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 dark:text-gray-400 uppercase">Billing</th>
              <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 dark:text-gray-400 uppercase">Status</th>
            </tr>
          </thead>
          <tbody class="divide-y divide-gray-200 dark:divide-gray-700">
            <tr :for={ag <- @agreements}>
              <td class="px-6 py-4">
                <.link navigate={~p"/portal/agreements/#{ag.id}"} class="text-emerald-600 hover:text-emerald-500 font-medium">
                  <%= ag.name %>
                </.link>
              </td>
              <td class="px-6 py-4 text-sm text-gray-500 dark:text-gray-400 capitalize"><%= ag.agreement_type || "—" %></td>
              <td class="px-6 py-4 text-sm text-gray-500 dark:text-gray-400 capitalize"><%= ag.billing_model %></td>
              <td class="px-6 py-4">
                <span class="inline-flex items-center rounded-full px-2 py-1 text-xs font-medium bg-emerald-100 text-emerald-800 dark:bg-emerald-900/20 dark:text-emerald-400">
                  <%= ag.status %>
                </span>
              </td>
            </tr>
          </tbody>
        </table>
        <div :if={@agreements == []} class="px-6 py-8 text-center text-sm text-gray-500">
          No active agreements.
        </div>
      </div>
    </div>
    """
  end
end
