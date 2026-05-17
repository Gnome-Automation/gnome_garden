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
    <.page max_width="max-w-full" class="pb-8">
      <.page_header eyebrow="Client Portal">
        Agreements
        <:subtitle>Your active and historical service agreements.</:subtitle>
      </.page_header>

      <.section body_class="p-0">
        <div :if={@agreements != []} class="overflow-x-auto">
          <table class="min-w-full divide-y divide-base-content/10">
            <thead>
              <tr class="bg-base-200/50">
                <th class="px-4 py-3 text-left text-xs font-semibold uppercase tracking-wider text-base-content/60">Name</th>
                <th class="px-4 py-3 text-left text-xs font-semibold uppercase tracking-wider text-base-content/60">Type</th>
                <th class="px-4 py-3 text-left text-xs font-semibold uppercase tracking-wider text-base-content/60">Billing</th>
                <th class="px-4 py-3 text-left text-xs font-semibold uppercase tracking-wider text-base-content/60">Status</th>
              </tr>
            </thead>
            <tbody class="divide-y divide-base-content/5">
              <tr :for={ag <- @agreements} class="hover:bg-base-200/30 transition-colors">
                <td class="px-4 py-3 text-sm text-base-content">
                  <.link navigate={~p"/portal/agreements/#{ag.id}"} class="text-emerald-600 hover:text-emerald-500 font-medium">
                    <%= ag.name %>
                  </.link>
                </td>
                <td class="px-4 py-3 text-sm text-base-content/60 capitalize"><%= ag.agreement_type || "—" %></td>
                <td class="px-4 py-3 text-sm text-base-content/60 capitalize"><%= ag.billing_model %></td>
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
