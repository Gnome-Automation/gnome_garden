defmodule GnomeGardenWeb.Operations.OrganizationLive.Index do
  use GnomeGardenWeb, :live_view

  import GnomeGardenWeb.Operations.Helpers

  alias GnomeGarden.Operations

  @impl true
  def mount(_params, _session, socket) do
    organizations = load_organizations(socket.assigns.current_user)

    {:ok,
     socket
     |> assign(:page_title, "Organizations")
     |> assign(:organization_count, length(organizations))
     |> assign(:prospect_count, Enum.count(organizations, &(&1.status == :prospect)))
     |> assign(:active_count, Enum.count(organizations, &(&1.status == :active)))
     |> stream(:organizations, organizations)}
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
            <.icon name="hero-users" class="size-4" /> People
          </.button>
          <.button navigate={~p"/operations/organizations/new"} variant="primary">
            <.icon name="hero-plus" class="size-4" /> New Organization
          </.button>
        </:actions>
      </.page_header>

      <div class="grid gap-4 md:grid-cols-3">
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

      <.section
        title="Organization Directory"
        description="Review the customer, prospect, partner, and agency records feeding the rest of the platform."
        compact
        body_class="p-0"
      >
        <div :if={@organization_count == 0} class="p-6 sm:p-7">
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
        </div>

        <div :if={@organization_count > 0} class="overflow-x-auto">
          <table class="min-w-full divide-y divide-zinc-200 text-sm dark:divide-white/10">
            <thead class="bg-zinc-50 dark:bg-white/[0.03]">
              <tr>
                <th class="px-5 py-3 text-left font-medium text-zinc-500 dark:text-zinc-400">
                  Organization
                </th>
                <th class="px-5 py-3 text-left font-medium text-zinc-500 dark:text-zinc-400">
                  Kind
                </th>
                <th class="px-5 py-3 text-left font-medium text-zinc-500 dark:text-zinc-400">
                  Roles
                </th>
                <th class="px-5 py-3 text-left font-medium text-zinc-500 dark:text-zinc-400">
                  Footprint
                </th>
                <th class="px-5 py-3 text-left font-medium text-zinc-500 dark:text-zinc-400">
                  Status
                </th>
              </tr>
            </thead>
            <tbody
              id="organizations"
              phx-update="stream"
              class="divide-y divide-zinc-200 dark:divide-white/10"
            >
              <tr :for={{dom_id, organization} <- @streams.organizations} id={dom_id}>
                <td class="px-5 py-4 align-top">
                  <div class="space-y-1">
                    <.link
                      navigate={~p"/operations/organizations/#{organization}"}
                      class="font-medium text-zinc-900 hover:text-emerald-600 dark:text-white"
                    >
                      {organization.name}
                    </.link>
                    <p class="text-sm text-zinc-500 dark:text-zinc-400">
                      {organization.primary_region || "No primary region"}
                    </p>
                  </div>
                </td>
                <td class="px-5 py-4 align-top">
                  <.tag color={tag_color_for_kind(organization.organization_kind)}>
                    {format_atom(organization.organization_kind)}
                  </.tag>
                </td>
                <td class="px-5 py-4 align-top text-zinc-600 dark:text-zinc-300">
                  {format_roles(organization.relationship_roles)}
                </td>
                <td class="px-5 py-4 align-top text-zinc-600 dark:text-zinc-300">
                  <div class="space-y-1">
                    <p>{organization.people_count || 0} people</p>
                    <p class="text-xs text-zinc-400 dark:text-zinc-500">
                      {organization.signal_count || 0} signals, {organization.pursuit_count || 0} pursuits
                    </p>
                  </div>
                </td>
                <td class="px-5 py-4 align-top">
                  <.status_badge status={organization.status_variant}>
                    {format_atom(organization.status)}
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

  defp load_organizations(actor) do
    case Operations.list_organizations(
           actor: actor,
           load: [
             :status_variant,
             :people_count,
             :signal_count,
             :pursuit_count
           ]
         ) do
      {:ok, organizations} -> Enum.sort_by(organizations, &String.downcase(&1.name || ""))
      {:error, error} -> raise "failed to load organizations: #{inspect(error)}"
    end
  end
end
