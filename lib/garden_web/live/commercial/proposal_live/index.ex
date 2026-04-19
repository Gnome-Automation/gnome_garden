defmodule GnomeGardenWeb.Commercial.ProposalLive.Index do
  use GnomeGardenWeb, :live_view

  import GnomeGardenWeb.Commercial.Helpers

  alias GnomeGarden.Commercial

  @impl true
  def mount(_params, _session, socket) do
    proposals = load_proposals(socket.assigns.current_user)

    {:ok,
     socket
     |> assign(:page_title, "Proposals")
     |> assign(:proposal_count, length(proposals))
     |> assign(:issued_count, Enum.count(proposals, &(&1.status == :issued)))
     |> assign(:accepted_count, Enum.count(proposals, &(&1.status == :accepted)))
     |> assign(:total_amount, sum_amounts(proposals, :total_amount))
     |> stream(:proposals, proposals)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.page class="pb-8">
      <.page_header eyebrow="Commercial">
        Proposals
        <:subtitle>
          Turn qualified pursuits into priced offers that can be issued, accepted, and converted into agreements.
        </:subtitle>
        <:actions>
          <.button navigate={~p"/commercial/pursuits"}>
            <.icon name="hero-arrow-trending-up" class="size-4" /> Pursuits
          </.button>
          <.button navigate={~p"/commercial/proposals/new"} variant="primary">
            <.icon name="hero-plus" class="size-4" /> New Proposal
          </.button>
        </:actions>
      </.page_header>

      <div class="grid gap-4 md:grid-cols-4">
        <.stat_card
          title="Proposals"
          value={Integer.to_string(@proposal_count)}
          description="Draft, issued, and accepted customer-facing proposals in the system."
          icon="hero-document-text"
        />
        <.stat_card
          title="Issued"
          value={Integer.to_string(@issued_count)}
          description="Proposals already sent out and waiting on a customer decision."
          icon="hero-paper-airplane"
          accent="sky"
        />
        <.stat_card
          title="Accepted"
          value={Integer.to_string(@accepted_count)}
          description="Accepted proposals that are ready to become commercial agreements."
          icon="hero-check-badge"
          accent="amber"
        />
        <.stat_card
          title="Quoted Value"
          value={format_amount(@total_amount)}
          description="Aggregate priced scope represented by all current proposal lines."
          icon="hero-banknotes"
          accent="rose"
        />
      </div>

      <.section
        title="Commercial Offers"
        description="Keep proposal issuance explicit so every priced offer maps back to a real pursuit and account."
        compact
        body_class="p-0"
      >
        <div :if={@proposal_count == 0} class="p-6 sm:p-7">
          <.empty_state
            icon="hero-document-text"
            title="No proposals yet"
            description="Create a proposal once a pursuit has enough clarity to turn into priced scope."
          >
            <:action>
              <.button navigate={~p"/commercial/proposals/new"} variant="primary">
                Create Proposal
              </.button>
            </:action>
          </.empty_state>
        </div>

        <div :if={@proposal_count > 0} class="overflow-x-auto">
          <table class="min-w-full divide-y divide-zinc-200 text-sm dark:divide-white/10">
            <thead class="bg-zinc-50 dark:bg-white/[0.03]">
              <tr>
                <th class="px-5 py-3 text-left font-medium text-zinc-500 dark:text-zinc-400">
                  Proposal
                </th>
                <th class="px-5 py-3 text-left font-medium text-zinc-500 dark:text-zinc-400">
                  Pursuit
                </th>
                <th class="px-5 py-3 text-left font-medium text-zinc-500 dark:text-zinc-400">
                  Account
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
              id="proposals"
              phx-update="stream"
              class="divide-y divide-zinc-200 dark:divide-white/10"
            >
              <tr :for={{dom_id, proposal} <- @streams.proposals} id={dom_id}>
                <td class="px-5 py-4 align-top">
                  <div class="space-y-1">
                    <.link
                      navigate={~p"/commercial/proposals/#{proposal}"}
                      class="font-medium text-zinc-900 hover:text-emerald-600 dark:text-white"
                    >
                      {proposal.name}
                    </.link>
                    <p class="text-sm text-zinc-500 dark:text-zinc-400">
                      {proposal.proposal_number} · Rev {proposal.revision_number}
                    </p>
                  </div>
                </td>
                <td class="px-5 py-4 align-top text-zinc-600 dark:text-zinc-300">
                  {(proposal.pursuit && proposal.pursuit.name) || "-"}
                </td>
                <td class="px-5 py-4 align-top text-zinc-600 dark:text-zinc-300">
                  {(proposal.organization && proposal.organization.name) || "-"}
                </td>
                <td class="px-5 py-4 align-top text-zinc-600 dark:text-zinc-300">
                  <div class="space-y-1">
                    <p>{format_amount(proposal.total_amount)}</p>
                    <p class="text-xs text-zinc-400 dark:text-zinc-500">
                      {proposal.line_count || 0} lines · {proposal.agreement_count || 0} agreements
                    </p>
                  </div>
                </td>
                <td class="px-5 py-4 align-top">
                  <.status_badge status={proposal.status_variant}>
                    {format_atom(proposal.status)}
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

  defp load_proposals(actor) do
    case Commercial.list_proposals(
           actor: actor,
           query: [sort: [inserted_at: :desc]],
           load: [
             :status_variant,
             :line_count,
             :agreement_count,
             :total_amount,
             pursuit: [],
             organization: []
           ]
         ) do
      {:ok, proposals} -> proposals
      {:error, error} -> raise "failed to load proposals: #{inspect(error)}"
    end
  end

  defp sum_amounts(records, field) do
    Enum.reduce(records, Decimal.new(0), fn record, total ->
      Decimal.add(total, Map.get(record, field) || Decimal.new(0))
    end)
  end
end
