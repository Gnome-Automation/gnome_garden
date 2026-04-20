defmodule GnomeGardenWeb.Operations.OrganizationLive.Show do
  use GnomeGardenWeb, :live_view

  import GnomeGardenWeb.Operations.Helpers

  alias GnomeGarden.Operations
  alias GnomeGarden.Operations.IdentityMergeReview

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    organization = load_organization!(id, socket.assigns.current_user)
    merge_review = load_merge_review!(organization, socket.assigns.current_user)

    {:ok,
     socket
     |> assign(:page_title, organization.name)
     |> assign(:organization, organization)
     |> assign(:merge_review, merge_review)}
  end

  @impl true
  def handle_event("merge_organization", %{"organization_id" => organization_id}, socket) do
    case Operations.merge_organization(
           socket.assigns.organization,
           %{into_organization_id: organization_id},
           actor: socket.assigns.current_user
         ) do
      {:ok, _merged_organization} ->
        merged_target = load_organization!(organization_id, socket.assigns.current_user)

        {:noreply,
         socket
         |> assign(:page_title, merged_target.name)
         |> assign(:organization, merged_target)
         |> assign(:merge_review, load_merge_review!(merged_target, socket.assigns.current_user))
         |> put_flash(:info, "Organization merged into selected canonical record")}

      {:error, error} ->
        {:noreply, put_flash(socket, :error, "Could not merge organization: #{inspect(error)}")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.page class="pb-8">
      <.page_header eyebrow="Operations">
        {@organization.name}
        <:subtitle>
          <span class="inline-flex items-center gap-2">
            <.status_badge status={@organization.status_variant}>
              {format_atom(@organization.status)}
            </.status_badge>
            <span class="text-zinc-400 dark:text-zinc-500">/</span>
            <span>{format_atom(@organization.organization_kind)}</span>
          </span>
        </:subtitle>
        <:actions>
          <.button navigate={~p"/operations/organizations"}>
            <.icon name="hero-arrow-left" class="size-4" /> Back
          </.button>
          <.button navigate={~p"/operations/organizations/#{@organization}/edit"} variant="primary">
            <.icon name="hero-pencil-square" class="size-4" /> Edit
          </.button>
        </:actions>
      </.page_header>

      <div class="grid gap-4 md:grid-cols-4">
        <.stat_card
          title="People"
          value={Integer.to_string(@organization.people_count || 0)}
          description="Known external contacts and stakeholders linked to this organization."
          icon="hero-users"
        />
        <.stat_card
          title="Signals"
          value={Integer.to_string(@organization.signal_count || 0)}
          description="Raw commercial intake items tied to this organization."
          icon="hero-inbox-stack"
          accent="sky"
        />
        <.stat_card
          title="Pursuits"
          value={Integer.to_string(@organization.pursuit_count || 0)}
          description="Owned commercial pipeline already attached to this account."
          icon="hero-arrow-trending-up"
          accent="amber"
        />
        <.stat_card
          title="Sources"
          value={Integer.to_string(@organization.procurement_source_count || 0)}
          description="Monitored procurement or company-web sources linked to this organization."
          icon="hero-globe-alt"
          accent="rose"
        />
      </div>

      <div class="grid gap-6 lg:grid-cols-2">
        <.section title="Operating Profile">
          <.properties>
            <.property name="Legal Name">{@organization.legal_name || "-"}</.property>
            <.property name="Primary Region">{@organization.primary_region || "-"}</.property>
            <.property name="Website">
              <a
                :if={@organization.website}
                href={@organization.website}
                target="_blank"
                class="text-emerald-600 hover:text-emerald-500 dark:text-emerald-400"
              >
                {@organization.website}
              </a>
              <span :if={!@organization.website}>-</span>
            </.property>
            <.property name="Phone">{format_phone(@organization.phone)}</.property>
            <.property name="Roles">{format_roles(@organization.relationship_roles)}</.property>
          </.properties>
        </.section>

        <.section title="Operational Footprint">
          <.properties>
            <.property name="Sites">{Integer.to_string(@organization.site_count || 0)}</.property>
            <.property name="Managed Systems">
              {Integer.to_string(@organization.managed_system_count || 0)}
            </.property>
            <.property name="Assets">{Integer.to_string(@organization.asset_count || 0)}</.property>
            <.property name="Created">{format_datetime(@organization.inserted_at)}</.property>
          </.properties>
        </.section>
      </div>

      <.section :if={@organization.notes} title="Notes">
        <p class="whitespace-pre-wrap text-sm leading-6 text-zinc-600 dark:text-zinc-300">
          {@organization.notes}
        </p>
      </.section>

      <.section
        :if={@merge_review.candidates != []}
        title="Duplicate Review"
        description="Potential canonical matches based on shared normalized name or website domain."
      >
        <div id="organization-merge-candidates" class="space-y-3">
          <div
            :for={candidate <- @merge_review.candidates}
            class="rounded-2xl border border-zinc-200 bg-zinc-50/70 px-4 py-4 dark:border-white/10 dark:bg-white/[0.03]"
          >
            <div class="flex flex-wrap items-start justify-between gap-3">
              <div class="space-y-2">
                <div class="space-y-1">
                  <.link
                    navigate={~p"/operations/organizations/#{candidate.organization}"}
                    class="font-medium text-zinc-900 hover:text-emerald-600 dark:text-white"
                  >
                    {candidate.organization.name}
                  </.link>
                  <p class="text-sm text-zinc-500 dark:text-zinc-400">
                    {candidate.organization.website_domain || candidate.organization.primary_region ||
                      "No domain"}
                  </p>
                </div>
                <div class="flex flex-wrap gap-2">
                  <.tag
                    :for={reason <- candidate.match_reasons}
                    color={merge_reason_tag_color(reason)}
                  >
                    {format_merge_reason(reason)}
                  </.tag>
                </div>
                <p class="text-xs text-zinc-400 dark:text-zinc-500">
                  {candidate.organization.people_count} people · {candidate.organization.signal_count} signals · {candidate.organization.pursuit_count} pursuits · {candidate.organization.procurement_source_count} sources
                </p>
              </div>

              <div class="flex flex-wrap gap-2">
                <.button
                  id={"merge-organization-#{candidate.organization.id}"}
                  phx-click="merge_organization"
                  phx-value-organization_id={candidate.organization.id}
                  variant="primary"
                >
                  Merge Into Candidate
                </.button>
              </div>
            </div>
          </div>
        </div>
      </.section>

      <div class="grid gap-6 xl:grid-cols-2">
        <.section
          title="People"
          description="External contacts and stakeholders currently associated with this organization."
        >
          <:actions>
            <.button
              navigate={~p"/operations/affiliations/new?#{[organization_id: @organization.id]}"}
              variant="primary"
            >
              <.icon name="hero-plus" class="size-4" /> Add Affiliation
            </.button>
          </:actions>
          <div id="organization-people" class="space-y-3">
            <div :if={Enum.empty?(@organization.people || [])}>
              <.empty_state
                icon="hero-users"
                title="No people linked"
                description="Agent-discovered or manually curated contacts will appear here."
              />
            </div>

            <.link
              :for={person <- @organization.people || []}
              navigate={~p"/operations/people/#{person}"}
              class="flex items-center justify-between rounded-2xl border border-zinc-200 bg-zinc-50/70 px-4 py-4 transition hover:border-emerald-300 hover:bg-white dark:border-white/10 dark:bg-white/[0.03] dark:hover:border-emerald-400/40"
            >
              <div class="space-y-1">
                <p class="font-medium text-zinc-900 dark:text-white">{person.full_name}</p>
                <p class="text-sm text-zinc-500 dark:text-zinc-400">
                  {person.email || person.phone || "No contact details"}
                </p>
              </div>
              <.status_badge status={person.status_variant}>
                {format_atom(person.status)}
              </.status_badge>
            </.link>
          </div>
        </.section>

        <.section
          title="Commercial Context"
          description="Signals and pursuits already attached to this organization."
        >
          <div id="organization-commercial" class="space-y-4">
            <div>
              <h3 class="text-sm font-semibold uppercase tracking-[0.2em] text-zinc-400 dark:text-zinc-500">
                Signals
              </h3>
              <div class="mt-3 space-y-2">
                <div :if={Enum.empty?(@organization.signals || [])} class="text-sm text-zinc-500">
                  No signals yet.
                </div>
                <.link
                  :for={signal <- @organization.signals || []}
                  navigate={~p"/commercial/signals/#{signal}"}
                  class="flex items-center justify-between rounded-xl border border-zinc-200 bg-zinc-50/70 px-3 py-3 transition hover:border-emerald-300 hover:bg-white dark:border-white/10 dark:bg-white/[0.03] dark:hover:border-emerald-400/40"
                >
                  <span class="font-medium text-zinc-900 dark:text-white">{signal.title}</span>
                  <.status_badge status={signal.status_variant}>
                    {format_atom(signal.status)}
                  </.status_badge>
                </.link>
              </div>
            </div>

            <div>
              <h3 class="text-sm font-semibold uppercase tracking-[0.2em] text-zinc-400 dark:text-zinc-500">
                Pursuits
              </h3>
              <div class="mt-3 space-y-2">
                <div :if={Enum.empty?(@organization.pursuits || [])} class="text-sm text-zinc-500">
                  No pursuits yet.
                </div>
                <.link
                  :for={pursuit <- @organization.pursuits || []}
                  navigate={~p"/commercial/pursuits/#{pursuit}"}
                  class="flex items-center justify-between rounded-xl border border-zinc-200 bg-zinc-50/70 px-3 py-3 transition hover:border-emerald-300 hover:bg-white dark:border-white/10 dark:bg-white/[0.03] dark:hover:border-emerald-400/40"
                >
                  <span class="font-medium text-zinc-900 dark:text-white">{pursuit.name}</span>
                  <.status_badge status={pursuit.stage_variant}>
                    {format_atom(pursuit.stage)}
                  </.status_badge>
                </.link>
              </div>
            </div>
          </div>
        </.section>
      </div>

      <.section
        title="Procurement Sources"
        description="Tracked procurement or website sources currently tied to this organization."
      >
        <div id="organization-procurement-sources" class="space-y-2">
          <div
            :if={Enum.empty?(@organization.procurement_sources || [])}
            class="text-sm text-zinc-500"
          >
            No procurement sources linked.
          </div>
          <.link
            :for={source <- @organization.procurement_sources || []}
            navigate={~p"/acquisition/sources"}
            class="flex items-center justify-between rounded-xl border border-zinc-200 bg-zinc-50/70 px-3 py-3 transition hover:border-emerald-300 hover:bg-white dark:border-white/10 dark:bg-white/[0.03] dark:hover:border-emerald-400/40"
          >
            <span class="font-medium text-zinc-900 dark:text-white">{source.name}</span>
            <span class="text-sm text-zinc-500 dark:text-zinc-400">
              {format_atom(source.source_type)}
            </span>
          </.link>
        </div>
      </.section>
    </.page>
    """
  end

  defp load_organization!(id, actor) do
    case Operations.get_organization(
           id,
           actor: actor,
           load: [
             :status_variant,
             :people_count,
             :site_count,
             :managed_system_count,
             :asset_count,
             :signal_count,
             :pursuit_count,
             :procurement_source_count,
             procurement_sources: [],
             people: [:full_name, :status_variant],
             signals: [:status_variant],
             pursuits: [:stage_variant]
           ]
         ) do
      {:ok, organization} -> organization
      {:error, error} -> raise "failed to load organization #{id}: #{inspect(error)}"
    end
  end

  defp load_merge_review!(organization, actor) do
    case IdentityMergeReview.organization_review(organization, actor: actor) do
      {:ok, merge_review} -> merge_review
      {:error, error} -> raise "failed to load organization merge review: #{inspect(error)}"
    end
  end

  defp format_merge_reason(:website_domain), do: "Same Website Domain"
  defp format_merge_reason(:name_key), do: "Same Normalized Name"
  defp format_merge_reason(reason), do: format_atom(reason)

  defp merge_reason_tag_color(:website_domain), do: :emerald
  defp merge_reason_tag_color(:name_key), do: :sky
  defp merge_reason_tag_color(_reason), do: :zinc
end
