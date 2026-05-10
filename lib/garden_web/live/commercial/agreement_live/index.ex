defmodule GnomeGardenWeb.Commercial.AgreementLive.Index do
  use GnomeGardenWeb, :live_view
  use Cinder.UrlSync

  import GnomeGardenWeb.Commercial.Helpers

  alias GnomeGarden.Commercial

  @impl true
  def mount(_params, _session, socket) do
    counts = load_counts(socket.assigns.current_user)

    {:ok,
     socket
     |> assign(:page_title, "Agreements")
     |> assign(:agreement_count, counts.total)
     |> assign(:active_count, counts.active)
     |> assign(:pending_count, counts.pending)
     |> assign(:contract_value_total, counts.contract_value_total)}
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
        Agreements
        <:subtitle>
          Commercial commitments that can seed projects, service work, invoicing, and contract consumption.
        </:subtitle>
        <:actions>
          <.button navigate={~p"/commercial/proposals"}>
            Proposals
          </.button>
          <.button navigate={~p"/commercial/agreements/new"} variant="primary">
            New Agreement
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

      <Cinder.collection
        id="agreements-table"
        resource={GnomeGarden.Commercial.Agreement}
        actor={@current_user}
        url_state={@url_state}
        theme={GnomeGardenWeb.CinderTheme}
        page_size={25}
        query_opts={[
          load: [:status_variant, :project_count, :invoice_count, organization: []]
        ]}
        click={fn agreement -> JS.navigate(~p"/commercial/agreements/#{agreement}") end}
      >
        <:col :let={agreement} field="name" sort search label="Agreement">
          <div class="space-y-1">
            <div class="font-medium text-zinc-900 dark:text-white">{agreement.name}</div>
            <p class="text-sm text-base-content/50">
              {agreement.reference_number || "No reference"} · {format_atom(agreement.billing_model)}
            </p>
          </div>
        </:col>

        <:col :let={agreement} field="organization.name" sort search label="Organization">
          {(agreement.organization && agreement.organization.name) || "-"}
        </:col>

        <:col :let={agreement} field="agreement_type" sort label="Type">
          {format_atom(agreement.agreement_type)}
        </:col>

        <:col :let={agreement} field="contract_value" sort label="Value">
          <div class="space-y-1">
            <p>{format_amount(agreement.contract_value)}</p>
            <p class="text-xs text-base-content/40">
              {agreement.project_count || 0} projects · {agreement.invoice_count || 0} invoices
            </p>
          </div>
        </:col>

        <:col :let={agreement} field="status" sort label="Status">
          <.status_badge status={agreement.status_variant}>
            {format_atom(agreement.status)}
          </.status_badge>
        </:col>

        <:empty>
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
        </:empty>
      </Cinder.collection>
    </.page>
    """
  end

  defp load_counts(actor) do
    case Commercial.list_agreements(actor: actor) do
      {:ok, agreements} ->
        %{
          total: length(agreements),
          active: Enum.count(agreements, &(&1.status == :active)),
          pending: Enum.count(agreements, &(&1.status == :pending_signature)),
          contract_value_total: sum_amounts(agreements, :contract_value)
        }

      {:error, _} ->
        %{total: 0, active: 0, pending: 0, contract_value_total: Decimal.new(0)}
    end
  end

  defp sum_amounts(records, field) do
    Enum.reduce(records, Decimal.new(0), fn record, total ->
      Decimal.add(total, Map.get(record, field) || Decimal.new(0))
    end)
  end
end
