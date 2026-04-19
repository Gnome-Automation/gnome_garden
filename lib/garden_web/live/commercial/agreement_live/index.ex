defmodule GnomeGardenWeb.Commercial.AgreementLive.Index do
  use GnomeGardenWeb, :live_view

  import GnomeGardenWeb.Commercial.Helpers

  alias GnomeGarden.Commercial

  @impl true
  def mount(_params, _session, socket) do
    agreements = load_agreements(socket.assigns.current_user)

    {:ok,
     socket
     |> assign(:page_title, "Agreements")
     |> assign(:agreement_count, length(agreements))
     |> assign(:active_count, Enum.count(agreements, &(&1.status == :active)))
     |> assign(:pending_count, Enum.count(agreements, &(&1.status == :pending_signature)))
     |> assign(:contract_value_total, sum_amounts(agreements, :contract_value))
     |> stream(:agreements, agreements)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.page class="pb-8">
      <.page_header eyebrow="Commercial">
        Agreements
        <:subtitle>
          Commercial commitments that can seed projects, service work, invoicing, and contract consumption.
        </:subtitle>
        <:actions>
          <.button navigate={~p"/commercial/proposals"}>
            <.icon name="hero-document-text" class="size-4" /> Proposals
          </.button>
          <.button navigate={~p"/commercial/agreements/new"} variant="primary">
            <.icon name="hero-plus" class="size-4" /> New Agreement
          </.button>
        </:actions>
      </.page_header>

      <div class="grid gap-4 md:grid-cols-4">
        <.stat_card
          title="Agreements"
          value={Integer.to_string(@agreement_count)}
          description="Draft, active, and completed commercial commitments managed in the platform."
          icon="hero-document-check"
        />
        <.stat_card
          title="Active"
          value={Integer.to_string(@active_count)}
          description="Agreements currently driving delivery, service, billing, or entitlement usage."
          icon="hero-check-badge"
          accent="sky"
        />
        <.stat_card
          title="Pending Signature"
          value={Integer.to_string(@pending_count)}
          description="Agreements waiting on final signature or explicit activation."
          icon="hero-pencil-square"
          accent="amber"
        />
        <.stat_card
          title="Contract Value"
          value={format_amount(@contract_value_total)}
          description="Aggregate committed value across current agreement records."
          icon="hero-banknotes"
          accent="rose"
        />
      </div>

      <.section
        title="Commercial Commitments"
        description="Keep agreements explicit so project, service, and finance automation hangs off a durable contract record."
        compact
        body_class="p-0"
      >
        <div :if={@agreement_count == 0} class="p-6 sm:p-7">
          <.empty_state
            icon="hero-document-check"
            title="No agreements yet"
            description="Create an agreement directly, or convert an accepted proposal into a commercial commitment."
          >
            <:action>
              <.button navigate={~p"/commercial/agreements/new"} variant="primary">
                Create Agreement
              </.button>
            </:action>
          </.empty_state>
        </div>

        <div :if={@agreement_count > 0} class="overflow-x-auto">
          <table class="min-w-full divide-y divide-zinc-200 text-sm dark:divide-white/10">
            <thead class="bg-zinc-50 dark:bg-white/[0.03]">
              <tr>
                <th class="px-5 py-3 text-left font-medium text-zinc-500 dark:text-zinc-400">
                  Agreement
                </th>
                <th class="px-5 py-3 text-left font-medium text-zinc-500 dark:text-zinc-400">
                  Organization
                </th>
                <th class="px-5 py-3 text-left font-medium text-zinc-500 dark:text-zinc-400">
                  Type
                </th>
                <th class="px-5 py-3 text-left font-medium text-zinc-500 dark:text-zinc-400">
                  Value
                </th>
                <th class="px-5 py-3 text-left font-medium text-zinc-500 dark:text-zinc-400">
                  Status
                </th>
              </tr>
            </thead>
            <tbody
              id="agreements"
              phx-update="stream"
              class="divide-y divide-zinc-200 dark:divide-white/10"
            >
              <tr :for={{dom_id, agreement} <- @streams.agreements} id={dom_id}>
                <td class="px-5 py-4 align-top">
                  <div class="space-y-1">
                    <.link
                      navigate={~p"/commercial/agreements/#{agreement}"}
                      class="font-medium text-zinc-900 hover:text-emerald-600 dark:text-white"
                    >
                      {agreement.name}
                    </.link>
                    <p class="text-sm text-zinc-500 dark:text-zinc-400">
                      {agreement.reference_number || "No reference"} · {format_atom(
                        agreement.billing_model
                      )}
                    </p>
                  </div>
                </td>
                <td class="px-5 py-4 align-top text-zinc-600 dark:text-zinc-300">
                  {(agreement.organization && agreement.organization.name) || "-"}
                </td>
                <td class="px-5 py-4 align-top text-zinc-600 dark:text-zinc-300">
                  {format_atom(agreement.agreement_type)}
                </td>
                <td class="px-5 py-4 align-top text-zinc-600 dark:text-zinc-300">
                  <div class="space-y-1">
                    <p>{format_amount(agreement.contract_value)}</p>
                    <p class="text-xs text-zinc-400 dark:text-zinc-500">
                      {agreement.project_count || 0} projects · {agreement.invoice_count || 0} invoices
                    </p>
                  </div>
                </td>
                <td class="px-5 py-4 align-top">
                  <.status_badge status={agreement.status_variant}>
                    {format_atom(agreement.status)}
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

  defp load_agreements(actor) do
    case Commercial.list_agreements(
           actor: actor,
           query: [sort: [inserted_at: :desc]],
           load: [:status_variant, :project_count, :invoice_count, organization: []]
         ) do
      {:ok, agreements} -> agreements
      {:error, error} -> raise "failed to load agreements: #{inspect(error)}"
    end
  end

  defp sum_amounts(records, field) do
    Enum.reduce(records, Decimal.new(0), fn record, total ->
      Decimal.add(total, Map.get(record, field) || Decimal.new(0))
    end)
  end
end
