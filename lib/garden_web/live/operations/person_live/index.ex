defmodule GnomeGardenWeb.Operations.PersonLive.Index do
  use GnomeGardenWeb, :live_view

  import GnomeGardenWeb.Operations.Helpers

  alias GnomeGarden.Operations

  @impl true
  def mount(_params, _session, socket) do
    people = load_people(socket.assigns.current_user)

    {:ok,
     socket
     |> assign(:page_title, "People")
     |> assign(:people_count, length(people))
     |> assign(:active_count, Enum.count(people, &(&1.status == :active)))
     |> assign(:linked_count, Enum.count(people, &((&1.organization_count || 0) > 0)))
     |> stream(:people, people)}
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
            <.icon name="hero-building-office-2" class="size-4" /> Organizations
          </.button>
          <.button navigate={~p"/operations/people/new"} variant="primary">
            <.icon name="hero-plus" class="size-4" /> New Person
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

      <.section
        title="People Directory"
        description="Review the durable people model instead of duplicating contacts per company."
        compact
        body_class="p-0"
      >
        <div :if={@people_count == 0} class="p-6 sm:p-7">
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
        </div>

        <div :if={@people_count > 0} class="overflow-x-auto">
          <table class="min-w-full divide-y divide-zinc-200 text-sm dark:divide-white/10">
            <thead class="bg-zinc-50 dark:bg-white/[0.03]">
              <tr>
                <th class="px-5 py-3 text-left font-medium text-zinc-500 dark:text-zinc-400">
                  Person
                </th>
                <th class="px-5 py-3 text-left font-medium text-zinc-500 dark:text-zinc-400">
                  Contact
                </th>
                <th class="px-5 py-3 text-left font-medium text-zinc-500 dark:text-zinc-400">
                  Organizations
                </th>
                <th class="px-5 py-3 text-left font-medium text-zinc-500 dark:text-zinc-400">
                  Status
                </th>
              </tr>
            </thead>
            <tbody
              id="people"
              phx-update="stream"
              class="divide-y divide-zinc-200 dark:divide-white/10"
            >
              <tr :for={{dom_id, person} <- @streams.people} id={dom_id}>
                <td class="px-5 py-4 align-top">
                  <div class="space-y-1">
                    <.link
                      navigate={~p"/operations/people/#{person}"}
                      class="font-medium text-zinc-900 hover:text-emerald-600 dark:text-white"
                    >
                      {person.full_name}
                    </.link>
                    <p class="text-sm text-zinc-500 dark:text-zinc-400">
                      {format_atom(person.preferred_contact_method)}
                    </p>
                  </div>
                </td>
                <td class="px-5 py-4 align-top text-zinc-600 dark:text-zinc-300">
                  <div class="space-y-1">
                    <p>{person.email || "-"}</p>
                    <p class="text-xs text-zinc-400 dark:text-zinc-500">
                      {person.mobile || person.phone || "No phone"}
                    </p>
                  </div>
                </td>
                <td class="px-5 py-4 align-top text-zinc-600 dark:text-zinc-300">
                  {person.organization_count || 0}
                </td>
                <td class="px-5 py-4 align-top">
                  <.status_badge status={person.status_variant}>
                    {format_atom(person.status)}
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

  defp load_people(actor) do
    case Operations.list_people(
           actor: actor,
           load: [:full_name, :status_variant, :organization_count]
         ) do
      {:ok, people} ->
        Enum.sort_by(people, fn person ->
          String.downcase("#{person.last_name || ""} #{person.first_name || ""}")
        end)

      {:error, error} ->
        raise "failed to load people: #{inspect(error)}"
    end
  end
end
