defmodule GnomeGardenWeb.ClientPortal.AgreementLive.Show do
  use GnomeGardenWeb, :live_view

  alias GnomeGarden.Commercial
  alias GnomeGarden.Finance

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    actor = socket.assigns.current_client_user

    case Commercial.get_portal_agreement(id, actor: actor) do
      {:ok, agreement} ->
        invoices =
          case Finance.list_portal_invoices(actor: actor) do
            {:ok, list} -> Enum.filter(list, &(&1.agreement_id == agreement.id))
            _ -> []
          end

        {:ok,
         socket
         |> assign(:page_title, agreement.name)
         |> assign(:agreement, agreement)
         |> assign(:invoices, invoices)}

      {:error, _} ->
        {:ok,
         socket
         |> put_flash(:error, "Agreement not found.")
         |> redirect(to: ~p"/portal/agreements")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div :if={assigns[:agreement]}>
      <.page max_width="max-w-full" class="pb-8">
        <.page_header eyebrow="Client Portal">
          <%= @agreement.name %>
          <:subtitle>
            <.status_badge status={agreement_status_variant(@agreement.status)}>
              <%= String.capitalize(to_string(@agreement.status)) %>
            </.status_badge>
          </:subtitle>
          <:actions>
            <.button navigate={~p"/portal/agreements"}>← Agreements</.button>
          </:actions>
        </.page_header>

        <.section title="Agreement Details">
          <.properties>
            <.property name="Type">
              <span class="capitalize"><%= @agreement.agreement_type || "—" %></span>
            </.property>
            <.property name="Billing">
              <span class="capitalize"><%= @agreement.billing_model %></span>
            </.property>
            <.property name="Status">
              <.status_badge status={agreement_status_variant(@agreement.status)}>
                <%= String.capitalize(to_string(@agreement.status)) %>
              </.status_badge>
            </.property>
            <.property :if={@agreement.payment_terms_days} name="Terms">
              Net <%= @agreement.payment_terms_days %>
            </.property>
            <.property :if={@agreement.contract_value} name="Value">
              $<%= Decimal.to_string(@agreement.contract_value) %>
            </.property>
            <.property :if={@agreement.start_on} name="Start">
              <%= Date.to_string(@agreement.start_on) %>
            </.property>
            <.property :if={@agreement.end_on} name="End">
              <%= Date.to_string(@agreement.end_on) %>
            </.property>
            <.property :if={@agreement.reference_number} name="Reference">
              <%= @agreement.reference_number %>
            </.property>
          </.properties>
        </.section>

        <.section :if={@agreement.notes} title="Notes">
          <p class="text-sm text-base-content/60 whitespace-pre-line"><%= @agreement.notes %></p>
        </.section>

        <.section title="Invoices" body_class="p-0">
          <div :if={@invoices != []} class="overflow-x-auto">
            <table class="min-w-full divide-y divide-base-content/10">
              <thead>
                <tr class="bg-base-200/50">
                  <th class="px-4 py-3 text-left text-xs font-semibold uppercase tracking-wider text-base-content/60">Invoice #</th>
                  <th class="px-4 py-3 text-left text-xs font-semibold uppercase tracking-wider text-base-content/60">Issued</th>
                  <th class="px-4 py-3 text-left text-xs font-semibold uppercase tracking-wider text-base-content/60">Due</th>
                  <th class="px-4 py-3 text-right text-xs font-semibold uppercase tracking-wider text-base-content/60">Total</th>
                  <th class="px-4 py-3 text-right text-xs font-semibold uppercase tracking-wider text-base-content/60">Balance</th>
                  <th class="px-4 py-3 text-left text-xs font-semibold uppercase tracking-wider text-base-content/60">Status</th>
                </tr>
              </thead>
              <tbody class="divide-y divide-base-content/5">
                <tr :for={inv <- @invoices} class="hover:bg-base-200/30 transition-colors">
                  <td class="px-4 py-3 text-sm text-base-content">
                    <.link navigate={~p"/portal/invoices/#{inv.id}"} class="text-emerald-600 hover:text-emerald-500 font-medium">
                      <%= inv.invoice_number || inv.id %>
                    </.link>
                  </td>
                  <td class="px-4 py-3 text-sm text-base-content/60">
                    <%= if inv.issued_on, do: Date.to_string(inv.issued_on), else: "—" %>
                  </td>
                  <td class="px-4 py-3 text-sm text-base-content/60">
                    <%= if inv.due_on, do: Date.to_string(inv.due_on), else: "—" %>
                  </td>
                  <td class="px-4 py-3 text-sm text-base-content text-right">
                    <%= if inv.total_amount, do: "$#{Decimal.to_string(inv.total_amount)}", else: "—" %>
                  </td>
                  <td class="px-4 py-3 text-sm text-base-content text-right">
                    <%= if inv.balance_amount, do: "$#{Decimal.to_string(inv.balance_amount)}", else: "—" %>
                  </td>
                  <td class="px-4 py-3">
                    <.status_badge status={invoice_status_variant(inv.status)}>
                      <%= String.capitalize(to_string(inv.status)) %>
                    </.status_badge>
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
          <.empty_state
            :if={@invoices == []}
            icon="hero-receipt-percent"
            title="No invoices"
            description="No invoices are linked to this agreement."
          />
        </.section>
      </.page>
    </div>
    """
  end

  defp agreement_status_variant(:active), do: :success
  defp agreement_status_variant(:pending_signature), do: :warning
  defp agreement_status_variant(:suspended), do: :warning
  defp agreement_status_variant(:completed), do: :default
  defp agreement_status_variant(:terminated), do: :error
  defp agreement_status_variant(_), do: :default

  defp invoice_status_variant(:issued), do: :warning
  defp invoice_status_variant(:partial), do: :info
  defp invoice_status_variant(:paid), do: :success
  defp invoice_status_variant(:void), do: :error
  defp invoice_status_variant(:write_off), do: :error
  defp invoice_status_variant(_), do: :default
end
