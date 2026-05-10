defmodule GnomeGardenWeb.Operations.PersonLive.Index do
  use GnomeGardenWeb, :live_view
  use Cinder.UrlSync

  import GnomeGardenWeb.Operations.Helpers

  alias GnomeGarden.Operations

  @impl true
  def mount(_params, _session, socket) do
    counts = load_counts(socket.assigns.current_user)

    {:ok,
     socket
     |> assign(:page_title, "People")
     |> assign(:people_count, counts.total)
     |> assign(:active_count, counts.active)
     |> assign(:linked_count, counts.linked)}
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
        People
        <:subtitle>
          Durable external people records shared across organizations, commercial work, and service contexts.
        </:subtitle>
        <:actions>
          <.button navigate={~p"/operations/organizations"}>
            Organizations
          </.button>
          <.button navigate={~p"/operations/people/new"} variant="primary">
            New Person
          </.button>
        </:actions>
      </.page_header>

      <div class="grid gap-4 md:grid-cols-3">
        <.stat_card
          title="People"
          value={Integer.to_string(@people_count)}
          description="External contacts, requesters, and stakeholders known to the system."
          icon="hero-users"
        />
        <.stat_card
          title="Active"
          value={Integer.to_string(@active_count)}
          description="People currently active for outreach, service communication, or delivery coordination."
          icon="hero-check-badge"
          accent="sky"
        />
        <.stat_card
          title="Linked To Orgs"
          value={Integer.to_string(@linked_count)}
          description="People already connected to at least one organization through active affiliations."
          icon="hero-link"
          accent="amber"
        />
      </div>

      <Cinder.collection
        id="people-table"
        resource={GnomeGarden.Operations.Person}
        actor={@current_user}
        url_state={@url_state}
        theme={GnomeGardenWeb.CinderTheme}
        page_size={25}
        query_opts={[load: [:full_name, :status_variant, :organization_count]]}
        click={fn row -> JS.navigate(~p"/operations/people/#{row}") end}
      >
        <:col :let={person} field="last_name" sort search label="Person">
          <div class="space-y-0.5">
            <div class="font-medium text-base-content">{person.full_name}</div>
            <div class="text-xs text-base-content/50">
              {format_atom(person.preferred_contact_method)}
            </div>
          </div>
        </:col>

        <:col :let={person} field="email" sort search label="Contact">
          <div class="space-y-0.5">
            <p>{person.email || "-"}</p>
            <p class="text-xs text-base-content/40">
              {person.mobile || person.phone || "No phone"}
            </p>
          </div>
        </:col>

        <:col :let={person} label="Organizations">
          {person.organization_count || 0}
        </:col>

        <:col :let={person} field="status" sort label="Status">
          <.status_badge status={person.status_variant}>
            {format_atom(person.status)}
          </.status_badge>
        </:col>

        <:empty>
          <.empty_state
            icon="hero-users"
            title="No people yet"
            description="People discovered by agents or created by operators will appear here."
          >
            <:action>
              <.button navigate={~p"/operations/people/new"} variant="primary">
                Create Person
              </.button>
            </:action>
          </.empty_state>
        </:empty>
      </Cinder.collection>
    </.page>
    """
  end

  defp load_counts(actor) do
    case Operations.list_people(actor: actor, load: [:organization_count]) do
      {:ok, people} ->
        %{
          total: length(people),
          active: Enum.count(people, &(&1.status == :active)),
          linked: Enum.count(people, &((&1.organization_count || 0) > 0))
        }

      {:error, _} ->
        %{total: 0, active: 0, linked: 0}
    end
  end
end
