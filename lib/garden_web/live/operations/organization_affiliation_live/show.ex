defmodule GnomeGardenWeb.Operations.OrganizationAffiliationLive.Show do
  use GnomeGardenWeb, :live_view

  import GnomeGardenWeb.Operations.Helpers

  alias GnomeGarden.Operations

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    affiliation = load_affiliation!(id, socket.assigns.current_user)

    {:ok,
     socket
     |> assign(:page_title, affiliation.person.full_name)
     |> assign(:affiliation, affiliation)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.page class="pb-8">
      <.page_header eyebrow="Operations">
        {@affiliation.person.full_name}
        <:subtitle>
          {@affiliation.organization.name}
        </:subtitle>
        <:actions>
          <.button navigate={~p"/operations/affiliations"}>
            Back
          </.button>
          <.button navigate={~p"/operations/affiliations/#{@affiliation}/edit"} variant="primary">
            Edit
          </.button>
        </:actions>
      </.page_header>

      <div class="grid gap-4 md:grid-cols-3">
        <.stat_card
          title="Status"
          value={format_atom(@affiliation.status)}
          description="Whether this business relationship is still active, paused, or historical."
          icon="hero-check-badge"
        />
        <.stat_card
          title="Primary"
          value={if(@affiliation.is_primary, do: "Yes", else: "No")}
          description="Primary relationship marker for who should be treated as the main account contact."
          icon="hero-star"
          accent="amber"
        />
        <.stat_card
          title="Started"
          value={format_date(@affiliation.started_on)}
          description="Relationship start date for the person and organization pairing."
          icon="hero-calendar-days"
          accent="sky"
        />
      </div>

      <div class="grid gap-6 lg:grid-cols-2">
        <.section title="Relationship Context">
          <.properties>
            <.property name="Person">
              <.link
                navigate={~p"/operations/people/#{@affiliation.person}"}
                class="text-emerald-600 hover:text-primary"
              >
                {@affiliation.person.full_name}
              </.link>
            </.property>
            <.property name="Organization">
              <.link
                navigate={~p"/operations/organizations/#{@affiliation.organization}"}
                class="text-emerald-600 hover:text-primary"
              >
                {@affiliation.organization.name}
              </.link>
            </.property>
            <.property name="Title">{@affiliation.title || "-"}</.property>
            <.property name="Department">{@affiliation.department || "-"}</.property>
            <.property name="Roles">{format_roles(@affiliation.contact_roles)}</.property>
          </.properties>
        </.section>

        <.section title="Lifecycle">
          <.properties>
            <.property name="Status">
              <.status_badge status={@affiliation.status_variant}>
                {format_atom(@affiliation.status)}
              </.status_badge>
            </.property>
            <.property name="Primary">
              {if @affiliation.is_primary, do: "Yes", else: "No"}
            </.property>
            <.property name="Started">{format_date(@affiliation.started_on)}</.property>
            <.property name="Ended">{format_date(@affiliation.ended_on)}</.property>
            <.property name="Created">{format_datetime(@affiliation.inserted_at)}</.property>
          </.properties>
        </.section>
      </div>

      <.section :if={@affiliation.notes} title="Notes">
        <p class="whitespace-pre-wrap text-sm leading-6 text-base-content/70">
          {@affiliation.notes}
        </p>
      </.section>
    </.page>
    """
  end

  defp load_affiliation!(id, actor) do
    case Operations.get_organization_affiliation(
           id,
           actor: actor,
           load: [:status_variant, organization: [], person: [:full_name]]
         ) do
      {:ok, affiliation} -> affiliation
      {:error, error} -> raise "failed to load affiliation #{id}: #{inspect(error)}"
    end
  end
end
