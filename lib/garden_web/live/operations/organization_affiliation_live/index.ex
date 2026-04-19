defmodule GnomeGardenWeb.Operations.OrganizationAffiliationLive.Index do
  use GnomeGardenWeb, :live_view

  import GnomeGardenWeb.Operations.Helpers

  alias GnomeGarden.Operations

  @impl true
  def mount(_params, _session, socket) do
    affiliations = load_affiliations(socket.assigns.current_user)

    {:ok,
     socket
     |> assign(:page_title, "Affiliations")
     |> assign(:affiliation_count, length(affiliations))
     |> assign(:active_count, Enum.count(affiliations, &(&1.status == :active)))
     |> assign(:primary_count, Enum.count(affiliations, & &1.is_primary))
     |> stream(:affiliations, affiliations)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.page class="pb-8">
      <.page_header eyebrow="Operations">
        Affiliations
        <:subtitle>
          Connect durable people and organizations without collapsing them into duplicated CRM contact records.
        </:subtitle>
        <:actions>
          <.button navigate={~p"/operations/organizations"}>
            <.icon name="hero-building-office-2" class="size-4" /> Organizations
          </.button>
          <.button navigate={~p"/operations/affiliations/new"} variant="primary">
            <.icon name="hero-plus" class="size-4" /> New Affiliation
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

      <.section
        title="Organization Relationships"
        description="Review who is attached to which organization, in what role, and whether the relationship is still active."
        compact
        body_class="p-0"
      >
        <div :if={@affiliation_count == 0} class="p-6 sm:p-7">
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
        </div>

        <div :if={@affiliation_count > 0} class="overflow-x-auto">
          <table class="min-w-full divide-y divide-zinc-200 text-sm dark:divide-white/10">
            <thead class="bg-zinc-50 dark:bg-white/[0.03]">
              <tr>
                <th class="px-5 py-3 text-left font-medium text-zinc-500 dark:text-zinc-400">
                  Person
                </th>
                <th class="px-5 py-3 text-left font-medium text-zinc-500 dark:text-zinc-400">
                  Organization
                </th>
                <th class="px-5 py-3 text-left font-medium text-zinc-500 dark:text-zinc-400">
                  Role
                </th>
                <th class="px-5 py-3 text-left font-medium text-zinc-500 dark:text-zinc-400">
                  Timing
                </th>
                <th class="px-5 py-3 text-left font-medium text-zinc-500 dark:text-zinc-400">
                  Status
                </th>
              </tr>
            </thead>
            <tbody
              id="organization-affiliations"
              phx-update="stream"
              class="divide-y divide-zinc-200 dark:divide-white/10"
            >
              <tr :for={{dom_id, affiliation} <- @streams.affiliations} id={dom_id}>
                <td class="px-5 py-4 align-top">
                  <div class="space-y-1">
                    <.link
                      navigate={~p"/operations/affiliations/#{affiliation}"}
                      class="font-medium text-zinc-900 hover:text-emerald-600 dark:text-white"
                    >
                      {affiliation.person.full_name}
                    </.link>
                    <p class="text-sm text-zinc-500 dark:text-zinc-400">
                      {affiliation.person.email || affiliation.person.phone || "No contact details"}
                    </p>
                  </div>
                </td>
                <td class="px-5 py-4 align-top">
                  <div class="space-y-1">
                    <.link
                      navigate={~p"/operations/organizations/#{affiliation.organization}"}
                      class="text-zinc-900 hover:text-emerald-600 dark:text-white"
                    >
                      {affiliation.organization.name}
                    </.link>
                    <p class="text-sm text-zinc-500 dark:text-zinc-400">
                      {format_roles(affiliation.contact_roles)}
                    </p>
                  </div>
                </td>
                <td class="px-5 py-4 align-top text-zinc-600 dark:text-zinc-300">
                  <div class="space-y-1">
                    <p>{affiliation.title || "-"}</p>
                    <p class="text-xs text-zinc-400 dark:text-zinc-500">
                      {affiliation.department || "No department"}
                    </p>
                  </div>
                </td>
                <td class="px-5 py-4 align-top text-zinc-600 dark:text-zinc-300">
                  <div class="space-y-1">
                    <p>{format_date(affiliation.started_on)}</p>
                    <p class="text-xs text-zinc-400 dark:text-zinc-500">
                      Ends {format_date(affiliation.ended_on)}
                    </p>
                  </div>
                </td>
                <td class="px-5 py-4 align-top">
                  <div class="flex flex-wrap items-center gap-2">
                    <.status_badge status={affiliation.status_variant}>
                      {format_atom(affiliation.status)}
                    </.status_badge>
                    <.tag :if={affiliation.is_primary} color={:emerald}>Primary</.tag>
                  </div>
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </.section>
    </.page>
    """
  end

  defp load_affiliations(actor) do
    case Operations.list_organization_affiliations(
           actor: actor,
           query: [sort: [is_primary: :desc, inserted_at: :desc]],
           load: [:status_variant, organization: [], person: [:full_name]]
         ) do
      {:ok, affiliations} -> affiliations
      {:error, error} -> raise "failed to load affiliations: #{inspect(error)}"
    end
  end
end
