defmodule GnomeGardenWeb.Commercial.PursuitLive.Index do
  use GnomeGardenWeb, :live_view
  use Cinder.UrlSync

  import GnomeGardenWeb.Commercial.Helpers

  alias GnomeGarden.Commercial

  @impl true
  def mount(_params, _session, socket) do
    counts = load_counts(socket.assigns.current_user)

    {:ok,
     socket
     |> assign(:page_title, "Pursuits")
     |> assign(:active_count, counts.active)
     |> assign(:proposed_count, counts.proposed)
     |> assign(:weighted_total, counts.weighted_total)}
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
        Pursuits
        <:subtitle>
          Qualified signals become owned commercial pursuits with forecast, stage discipline, and downstream proposal work.
        </:subtitle>
        <:actions>
          <.button navigate={~p"/commercial/signals"}>
            Signal Queue
          </.button>
          <.button navigate={~p"/commercial/pursuits/new"} variant="primary">
            New Pursuit
          </.button>
        </:actions>
      </.page_header>

      <div class="grid gap-4 md:grid-cols-3">
        <.stat_card
          title="Active Pursuits"
          value={Integer.to_string(@active_count)}
          description="Commercial opportunities currently being qualified, priced, proposed, or negotiated."
          icon="hero-arrow-trending-up"
        />
        <.stat_card
          title="Late Stage"
          value={Integer.to_string(@proposed_count)}
          description="Pursuits already in proposal or negotiation and closest to revenue realization."
          icon="hero-document-check"
          accent="sky"
        />
        <.stat_card
          title="Weighted Pipeline"
          value={format_amount(@weighted_total)}
          description="Expected value after multiplying each pursuit by its current probability."
          icon="hero-banknotes"
          accent="amber"
        />
      </div>

      <Cinder.collection
        id="pursuits-table"
        resource={GnomeGarden.Commercial.Pursuit}
        action={:active}
        actor={@current_user}
        url_state={@url_state}
        theme={GnomeGardenWeb.CinderTheme}
        page_size={25}
        query_opts={[
          load: [:organization, :signal, :weighted_value, :proposal_count, :stage_variant]
        ]}
        click={fn pursuit -> JS.navigate(~p"/commercial/pursuits/#{pursuit}") end}
      >
        <:col :let={pursuit} field="name" sort search label="Pursuit">
          <div class="space-y-1">
            <div class="font-medium text-zinc-900 dark:text-white">{pursuit.name}</div>
            <p class="text-sm text-base-content/50">
              {format_atom(pursuit.pursuit_type)}
            </p>
          </div>
        </:col>

        <:col :let={pursuit} field="organization.name" sort search label="Organization">
          {(pursuit.organization && pursuit.organization.name) || "-"}
        </:col>

        <:col :let={pursuit} field="stage" sort label="Stage">
          <div class="space-y-2">
            <.status_badge status={pursuit.stage_variant}>
              {format_atom(pursuit.stage)}
            </.status_badge>
            <div>
              <.tag color={:zinc}>{pursuit.probability}%</.tag>
            </div>
          </div>
        </:col>

        <:col :let={pursuit} field="target_value" sort label="Target">
          <div class="space-y-1">
            <p>{format_amount(pursuit.target_value)}</p>
            <p class="text-xs text-base-content/40">
              Weighted {format_amount(pursuit.weighted_value)}
            </p>
          </div>
        </:col>

        <:col :let={pursuit} field="expected_close_on" sort label="Close">
          {format_date(pursuit.expected_close_on)}
        </:col>

        <:empty>
          <.empty_state
            icon="hero-arrow-trending-up"
            title="No pursuits yet"
            description="Create a pursuit directly, or accept a signal in the queue and convert it into owned pipeline."
          >
            <:action>
              <.button navigate={~p"/commercial/signals"} variant="primary">
                Open Signal Queue
              </.button>
            </:action>
          </.empty_state>
        </:empty>
      </Cinder.collection>
    </.page>
    """
  end

  defp load_counts(actor) do
    case Commercial.list_active_pursuits(
           actor: actor,
           load: [:weighted_value]
         ) do
      {:ok, pursuits} ->
        %{
          active: length(pursuits),
          proposed: Enum.count(pursuits, &(&1.stage in [:proposed, :negotiating])),
          weighted_total: weighted_total(pursuits)
        }

      {:error, _} ->
        %{active: 0, proposed: 0, weighted_total: Decimal.new(0)}
    end
  end

  defp weighted_total(pursuits) do
    Enum.reduce(pursuits, Decimal.new(0), fn pursuit, total ->
      Decimal.add(total, pursuit.weighted_value || Decimal.new(0))
    end)
  end
end
