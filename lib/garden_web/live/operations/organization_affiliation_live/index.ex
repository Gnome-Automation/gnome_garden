defmodule GnomeGardenWeb.Operations.OrganizationAffiliationLive.Index do
  use GnomeGardenWeb, :live_view
  use Cinder.UrlSync

  import GnomeGardenWeb.Operations.Helpers

  alias GnomeGarden.Operations

  @impl true
  def mount(_params, _session, socket) do
    counts = load_counts(socket.assigns.current_user)

    {:ok,
     socket
     |> assign(:page_title, "Affiliations")
     |> assign(:affiliation_count, counts.total)
     |> assign(:active_count, counts.active)
     |> assign(:primary_count, counts.primary)}
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
        Affiliations
        <:subtitle>
          Connect durable people and organizations without collapsing them into duplicated contact records.
        </:subtitle>
        <:actions>
          <.button navigate={~p"/operations/organizations"}>
            Organizations
          </.button>
          <.button navigate={~p"/operations/affiliations/new"} variant="primary">
            New Affiliation
          </.button>
        </:actions>
      </.page_header>

      <div class="grid gap-4 md:grid-cols-3">
        <.stat_card
          title="Affiliations"
          value={Integer.to_string(@affiliation_count)}
          description="Active and historical links between durable people and organizations."
          icon="hero-link"
        />
        <.stat_card
          title="Active"
          value={Integer.to_string(@active_count)}
          description="Current organization relationships still in force."
          icon="hero-check-badge"
          accent="sky"
        />
        <.stat_card
          title="Primary Contacts"
          value={Integer.to_string(@primary_count)}
          description="Affiliations marked as the primary business contact for an account."
          icon="hero-star"
          accent="amber"
        />
      </div>

      <Cinder.collection
        id="affiliations-table"
        resource={GnomeGarden.Operations.OrganizationAffiliation}
        actor={@current_user}
        url_state={@url_state}
        theme={GnomeGardenWeb.CinderTheme}
        page_size={25}
        query_opts={[load: [:status_variant, organization: [], person: [:full_name]]]}
        click={fn row -> JS.navigate(~p"/operations/affiliations/#{row}") end}
      >
        <:col :let={affiliation} field="person.last_name" sort search label="Person">
          <div class="space-y-0.5">
            <div class="font-medium text-base-content">{affiliation.person.full_name}</div>
            <div class="text-xs text-base-content/50">
              {affiliation.person.email || affiliation.person.phone || "No contact details"}
            </div>
          </div>
        </:col>

        <:col :let={affiliation} field="organization.name" sort search label="Organization">
          <div class="space-y-0.5">
            <div class="text-base-content">{affiliation.organization.name}</div>
            <p class="text-sm text-base-content/50">
              {format_roles(affiliation.contact_roles)}
            </p>
          </div>
        </:col>

        <:col :let={affiliation} field="title" sort search label="Role">
          <div class="space-y-0.5">
            <p>{affiliation.title || "-"}</p>
            <p class="text-xs text-base-content/40">
              {affiliation.department || "No department"}
            </p>
          </div>
        </:col>

        <:col :let={affiliation} field="started_on" sort label="Timing">
          <div class="space-y-0.5">
            <p>{format_date(affiliation.started_on)}</p>
            <p class="text-xs text-base-content/40">
              Ends {format_date(affiliation.ended_on)}
            </p>
          </div>
        </:col>

        <:col :let={affiliation} field="status" sort label="Status">
          <div class="flex flex-wrap items-center gap-2">
            <.status_badge status={affiliation.status_variant}>
              {format_atom(affiliation.status)}
            </.status_badge>
            <.tag :if={affiliation.is_primary} color={:emerald}>Primary</.tag>
          </div>
        </:col>

        <:empty>
          <.empty_state
            icon="hero-link"
            title="No affiliations yet"
            description="Create affiliations to connect durable people records to the right organizations."
          >
            <:action>
              <.button navigate={~p"/operations/affiliations/new"} variant="primary">
                Create Affiliation
              </.button>
            </:action>
          </.empty_state>
        </:empty>
      </Cinder.collection>
    </.page>
    """
  end

  defp load_counts(actor) do
    case Operations.list_organization_affiliations(actor: actor) do
      {:ok, affiliations} ->
        %{
          total: length(affiliations),
          active: Enum.count(affiliations, &(&1.status == :active)),
          primary: Enum.count(affiliations, & &1.is_primary)
        }

      {:error, _} ->
        %{total: 0, active: 0, primary: 0}
    end
  end
end
