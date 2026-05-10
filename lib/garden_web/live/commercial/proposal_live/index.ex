defmodule GnomeGardenWeb.Commercial.ProposalLive.Index do
  use GnomeGardenWeb, :live_view
  use Cinder.UrlSync

  import GnomeGardenWeb.Commercial.Helpers

  alias GnomeGarden.Commercial

  @impl true
  def mount(_params, _session, socket) do
    counts = load_counts(socket.assigns.current_user)

    {:ok,
     socket
     |> assign(:page_title, "Proposals")
     |> assign(:proposal_count, counts.total)
     |> assign(:issued_count, counts.issued)
     |> assign(:accepted_count, counts.accepted)
     |> assign(:total_amount, counts.total_amount)}
  end

  @impl true
  def handle_params(params, uri, socket) do
    socket = Cinder.UrlSync.handle_params(params, uri, socket)
    {:noreply, socket}
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
            Pursuits
          </.button>
          <.button navigate={~p"/commercial/proposals/new"} variant="primary">
            New Proposal
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

      <Cinder.collection
        id="proposals-table"
        resource={GnomeGarden.Commercial.Proposal}
        actor={@current_user}
        url_state={@url_state}
        theme={GnomeGardenWeb.CinderTheme}
        page_size={25}
        query_opts={[
          load: [
            :status_variant,
            :line_count,
            :agreement_count,
            :total_amount,
            pursuit: [],
            organization: []
          ]
        ]}
        click={fn proposal -> JS.navigate(~p"/commercial/proposals/#{proposal}") end}
      >
        <:col :let={proposal} field="name" sort search label="Proposal">
          <div class="space-y-1">
            <div class="font-medium text-zinc-900 dark:text-white">{proposal.name}</div>
            <p class="text-sm text-base-content/50">
              {proposal.proposal_number} · Rev {proposal.revision_number}
            </p>
          </div>
        </:col>

        <:col :let={proposal} field="pursuit.name" sort search label="Pursuit">
          {(proposal.pursuit && proposal.pursuit.name) || "-"}
        </:col>

        <:col :let={proposal} field="organization.name" sort search label="Account">
          {(proposal.organization && proposal.organization.name) || "-"}
        </:col>

        <:col :let={proposal} field="total_amount" sort label="Value">
          <div class="space-y-1">
            <p>{format_amount(proposal.total_amount)}</p>
            <p class="text-xs text-base-content/40">
              {proposal.line_count || 0} lines · {proposal.agreement_count || 0} agreements
            </p>
          </div>
        </:col>

        <:col :let={proposal} field="status" sort label="Status">
          <.status_badge status={proposal.status_variant}>
            {format_atom(proposal.status)}
          </.status_badge>
        </:col>

        <:empty>
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
        </:empty>
      </Cinder.collection>
    </.page>
    """
  end

  defp load_counts(actor) do
    case Commercial.list_proposals(actor: actor, load: [:total_amount]) do
      {:ok, proposals} ->
        %{
          total: length(proposals),
          issued: Enum.count(proposals, &(&1.status == :issued)),
          accepted: Enum.count(proposals, &(&1.status == :accepted)),
          total_amount: sum_amounts(proposals, :total_amount)
        }

      {:error, _} ->
        %{total: 0, issued: 0, accepted: 0, total_amount: Decimal.new(0)}
    end
  end

  defp sum_amounts(records, field) do
    Enum.reduce(records, Decimal.new(0), fn record, total ->
      Decimal.add(total, Map.get(record, field) || Decimal.new(0))
    end)
  end
end
