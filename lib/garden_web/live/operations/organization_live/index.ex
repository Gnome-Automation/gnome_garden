defmodule GnomeGardenWeb.Operations.OrganizationLive.Index do
  use GnomeGardenWeb, :live_view
  use Cinder.UrlSync

  import GnomeGardenWeb.Operations.Helpers

  alias GnomeGarden.Operations

  @impl true
  def mount(_params, _session, socket) do
    counts = load_counts(socket.assigns.current_user)

    {:ok,
     socket
     |> assign(:page_title, "Organizations")
     |> assign(:organization_count, counts.total)
     |> assign(:prospect_count, counts.prospect)
     |> assign(:active_count, counts.active)}
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
      <.page_header eyebrow="Operations">
        Organizations
        <:subtitle>
          The durable account backbone for commercial signals, delivery, service, and finance.
        </:subtitle>
        <:actions>
          <.button navigate={~p"/operations/people"}>
            People
          </.button>
          <.button navigate={~p"/operations/organizations/new"} variant="primary">
            New Organization
          </.button>
        </:actions>
      </.page_header>

      <div class="grid gap-2 sm:grid-cols-3">
        <.stat_card
          title="Organizations"
          value={Integer.to_string(@organization_count)}
          description="External and internal orgs tracked in the operating model."
          icon="hero-building-office-2"
        />
        <.stat_card
          title="Prospects"
          value={Integer.to_string(@prospect_count)}
          description="Organizations still in discovery or commercial qualification."
          icon="hero-magnifying-glass"
          accent="amber"
        />
        <.stat_card
          title="Active Accounts"
          value={Integer.to_string(@active_count)}
          description="Organizations already active in delivery, service, or commercial operations."
          icon="hero-check-badge"
          accent="sky"
        />
      </div>

      <Cinder.collection
        id="organizations-table"
        resource={GnomeGarden.Operations.Organization}
        actor={@current_user}
        url_state={@url_state}
        theme={GnomeGardenWeb.CinderTheme}
        page_size={25}
        query_opts={[load: [:status_variant, :people_count, :signal_count, :pursuit_count]]}
        click={fn row -> JS.navigate(~p"/operations/organizations/#{row}") end}
      >
        <:col :let={org} field="name" search sort label="Organization">
          <div class="space-y-0.5">
            <div class="font-medium text-base-content">{org.name}</div>
            <div class="text-xs text-base-content/50">
              {org.primary_region || "No primary region"}
            </div>
          </div>
        </:col>

        <:col :let={org} field="organization_kind" sort label="Kind">
          <.tag color={tag_color_for_kind(org.organization_kind)}>
            {format_atom(org.organization_kind)}
          </.tag>
        </:col>

        <:col :let={org} label="Roles">
          {format_roles(org.relationship_roles)}
        </:col>

        <:col :let={org} label="Footprint">
          <div class="space-y-0.5">
            <p>{org.people_count || 0} people</p>
            <p class="text-xs text-base-content/40">
              {org.signal_count || 0} signals, {org.pursuit_count || 0} pursuits
            </p>
          </div>
        </:col>

        <:col :let={org} field="status" sort label="Status">
          <.status_badge status={org.status_variant}>
            {format_atom(org.status)}
          </.status_badge>
        </:col>

        <:empty>
          <.empty_state
            icon="hero-building-office-2"
            title="No organizations yet"
            description="Agent-discovered companies and manual operating accounts will appear here."
          >
            <:action>
              <.button navigate={~p"/operations/organizations/new"} variant="primary">
                Create Organization
              </.button>
            </:action>
          </.empty_state>
        </:empty>
      </Cinder.collection>
    </.page>
    """
  end

  defp load_counts(actor) do
    case Operations.list_organizations(actor: actor) do
      {:ok, orgs} ->
        %{
          total: length(orgs),
          prospect: Enum.count(orgs, &(&1.status == :prospect)),
          active: Enum.count(orgs, &(&1.status == :active))
        }

      {:error, _} ->
        %{total: 0, prospect: 0, active: 0}
    end
  end
end
