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
     |> assign(:merge_review, merge_review)
     |> assign(:invite_ok, false)
     |> assign(:invite_error, nil)}
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
  def handle_event("invite_to_portal", %{"invite" => %{"email" => email}}, socket) do
    org_id = socket.assigns.organization.id

    case GnomeGarden.Accounts.invite_client_user(email, org_id) do
      {:ok, _client_user} ->
        GnomeGarden.Accounts.request_client_portal_access(email)
        {:noreply, assign(socket, :invite_ok, true)}

      {:error, error} ->
        {:noreply, assign(socket, :invite_error, "Could not invite: #{inspect(error)}")}
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
            <span class="text-base-content/40">/</span>
            <span>{format_atom(@organization.organization_kind)}</span>
          </span>
        </:subtitle>
        <:actions>
          <.button navigate={~p"/operations/organizations"}>
            Back
          </.button>
          <.button navigate={~p"/operations/organizations/#{@organization}/edit"} variant="primary">
            Edit
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
                class="text-emerald-600 hover:text-primary"
              >
                {@organization.website}
              </a>
              <span :if={!@organization.website}>-</span>
            </.property>
            <.property name="Phone">{format_phone(@organization.phone)}</.property>
            <.property name="Roles">{format_roles(@organization.relationship_roles)}</.property>
            <.property name="Billing Contact">
              <%= if @organization.billing_contact do %>
                <.link navigate={~p"/operations/people/#{@organization.billing_contact}"}>
                  {@organization.billing_contact.first_name} {@organization.billing_contact.last_name}
                  <span class="text-zinc-400 ml-1 text-sm">({@organization.billing_contact.email})</span>
                </.link>
              <% else %>
                <span class="text-zinc-400 italic">Not set — invoices go to any affiliated contact</span>
              <% end %>
            </.property>
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
        <p class="whitespace-pre-wrap text-sm leading-6 text-base-content/70">
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
                  <p class="text-sm text-base-content/50">
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
                <p class="text-xs text-base-content/40">
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
              Add Affiliation
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
                <p class="font-medium text-base-content">{person.full_name}</p>
                <p class="text-sm text-base-content/50">
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
              <h3 class="text-sm font-semibold uppercase tracking-[0.2em] text-base-content/40">
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
                  <span class="font-medium text-base-content">{signal.title}</span>
                  <.status_badge status={signal.status_variant}>
                    {format_atom(signal.status)}
                  </.status_badge>
                </.link>
              </div>
            </div>

            <div>
              <h3 class="text-sm font-semibold uppercase tracking-[0.2em] text-base-content/40">
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
                  <span class="font-medium text-base-content">{pursuit.name}</span>
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
            <span class="font-medium text-base-content">{source.name}</span>
            <span class="text-sm text-base-content/50">
              {format_atom(source.source_type)}
            </span>
          </.link>
        </div>
      </.section>
      <.section
        title="Client Portal"
        description="Invite a contact to view their invoices and agreements in the client portal."
      >
        <form id="invite-portal-form" phx-submit="invite_to_portal" class="flex gap-3 items-end">
          <div class="flex-1">
            <label class="block text-sm/6 font-medium text-gray-900 dark:text-white mb-1">Email address</label>
            <input
              type="email"
              name="invite[email]"
              placeholder="client@example.com"
              required
              class="rounded-md bg-white px-3 py-1.5 text-base text-gray-900 outline-1 -outline-offset-1 outline-gray-300 placeholder:text-gray-400 focus:outline-2 focus:-outline-offset-2 focus:outline-emerald-600 sm:text-sm/6 dark:bg-white/5 dark:text-white dark:outline-white/10 dark:placeholder:text-gray-500 dark:focus:outline-emerald-500 w-full"
            />
          </div>
          <button type="submit" class="rounded-md bg-emerald-600 px-3 py-2 text-sm font-semibold text-white shadow-xs hover:bg-emerald-500 dark:bg-emerald-500">
            Invite to portal
          </button>
        </form>
        <div :if={@invite_ok} class="mt-2 text-sm text-emerald-600">Contact invited — they'll receive a sign-in link by email.</div>
        <div :if={@invite_error} class="mt-2 text-sm text-red-600"><%= @invite_error %></div>
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
             pursuits: [:stage_variant],
             billing_contact: []
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
