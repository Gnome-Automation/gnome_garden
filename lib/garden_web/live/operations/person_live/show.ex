defmodule GnomeGardenWeb.Operations.PersonLive.Show do
  use GnomeGardenWeb, :live_view

  import GnomeGardenWeb.Operations.Helpers

  alias GnomeGarden.Operations
  alias GnomeGarden.Operations.IdentityMergeReview

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    person = load_person!(id, socket.assigns.current_user)
    merge_review = load_merge_review!(person, socket.assigns.current_user)

    {:ok,
     socket
     |> assign(:page_title, person.full_name)
     |> assign(:person, person)
     |> assign(:merge_review, merge_review)}
  end

  @impl true
  def handle_event("merge_person", %{"person_id" => person_id}, socket) do
    case Operations.merge_person(
           socket.assigns.person,
           %{into_person_id: person_id},
           actor: socket.assigns.current_user
         ) do
      {:ok, _merged_person} ->
        merged_target = load_person!(person_id, socket.assigns.current_user)

        {:noreply,
         socket
         |> assign(:page_title, merged_target.full_name)
         |> assign(:person, merged_target)
         |> assign(:merge_review, load_merge_review!(merged_target, socket.assigns.current_user))
         |> put_flash(:info, "Person merged into selected canonical record")}

      {:error, error} ->
        {:noreply, put_flash(socket, :error, "Could not merge person: #{inspect(error)}")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.page class="pb-8">
      <.page_header eyebrow="Operations">
        {@person.full_name}
        <:subtitle>
          {[@person.email, @person.mobile || @person.phone]
          |> Enum.filter(&(&1 not in [nil, ""]))
          |> Enum.join(" · ")}
        </:subtitle>
        <:actions>
          <.button navigate={~p"/operations/people"}>
            <.icon name="hero-arrow-left" class="size-4" /> Back
          </.button>
          <.button navigate={~p"/operations/people/#{@person}/edit"} variant="primary">
            <.icon name="hero-pencil-square" class="size-4" /> Edit
          </.button>
        </:actions>
      </.page_header>

      <div class="grid gap-4 md:grid-cols-3">
        <.stat_card
          title="Organizations"
          value={Integer.to_string(@person.organization_count || 0)}
          description="Active organization relationships currently linked to this person."
          icon="hero-building-office-2"
        />
        <.stat_card
          title="Service Tickets"
          value={Integer.to_string(length(@person.requested_service_tickets || []))}
          description="Service tickets this person has requested or initiated."
          icon="hero-wrench-screwdriver"
          accent="sky"
        />
        <.stat_card
          title="Status"
          value={format_atom(@person.status)}
          description="Communication and lifecycle state for this durable person record."
          icon="hero-check-badge"
          accent="amber"
        />
      </div>

      <div class="grid gap-6 lg:grid-cols-2">
        <.section title="Contact Profile">
          <.properties>
            <.property name="Email">
              <a
                :if={@person.email}
                href={"mailto:#{@person.email}"}
                class="text-emerald-600 hover:text-emerald-500 dark:text-emerald-400"
              >
                {@person.email}
              </a>
              <span :if={!@person.email}>-</span>
            </.property>
            <.property name="Phone">{format_phone(@person.phone)}</.property>
            <.property name="Mobile">{format_phone(@person.mobile)}</.property>
            <.property name="LinkedIn">
              <a
                :if={@person.linkedin_url}
                href={@person.linkedin_url}
                target="_blank"
                class="text-emerald-600 hover:text-emerald-500 dark:text-emerald-400"
              >
                View Profile
              </a>
              <span :if={!@person.linkedin_url}>-</span>
            </.property>
            <.property name="Timezone">{@person.timezone || "-"}</.property>
          </.properties>
        </.section>

        <.section title="Communication Preferences">
          <.properties>
            <.property name="Status">
              <.status_badge status={@person.status_variant}>
                {format_atom(@person.status)}
              </.status_badge>
            </.property>
            <.property name="Preferred Contact">
              {format_atom(@person.preferred_contact_method)}
            </.property>
            <.property name="Do Not Call">{if @person.do_not_call, do: "Yes", else: "No"}</.property>
            <.property name="Do Not Email">
              {if @person.do_not_email, do: "Yes", else: "No"}
            </.property>
            <.property name="Created">{format_datetime(@person.inserted_at)}</.property>
          </.properties>
        </.section>
      </div>

      <.section :if={@person.notes} title="Notes">
        <p class="whitespace-pre-wrap text-sm leading-6 text-zinc-600 dark:text-zinc-300">
          {@person.notes}
        </p>
      </.section>

      <.section
        :if={@merge_review.candidates != []}
        title="Duplicate Review"
        description="Potential canonical people based on shared normalized name, email domain, or linked organizations."
      >
        <div id="person-merge-candidates" class="space-y-3">
          <div
            :for={candidate <- @merge_review.candidates}
            class="rounded-2xl border border-zinc-200 bg-zinc-50/70 px-4 py-4 dark:border-white/10 dark:bg-white/[0.03]"
          >
            <div class="flex flex-wrap items-start justify-between gap-3">
              <div class="space-y-2">
                <div class="space-y-1">
                  <.link
                    navigate={~p"/operations/people/#{candidate.person}"}
                    class="font-medium text-zinc-900 hover:text-emerald-600 dark:text-white"
                  >
                    {candidate.person.full_name}
                  </.link>
                  <p class="text-sm text-zinc-500 dark:text-zinc-400">
                    {candidate.person.email || candidate.person.phone || "No direct contact details"}
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
                  {candidate.person.organization_count} organizations · {candidate_person_organizations(
                    candidate.person
                  )}
                </p>
              </div>

              <div class="flex flex-wrap gap-2">
                <.button
                  id={"merge-person-#{candidate.person.id}"}
                  phx-click="merge_person"
                  phx-value-person_id={candidate.person.id}
                  variant="primary"
                >
                  Merge Into Candidate
                </.button>
              </div>
            </div>
          </div>
        </div>
      </.section>

      <.section
        title="Organizations"
        description="The same person can participate across multiple organizations over time."
      >
        <:actions>
          <.button
            navigate={~p"/operations/affiliations/new?#{[person_id: @person.id]}"}
            variant="primary"
          >
            <.icon name="hero-plus" class="size-4" /> Add Affiliation
          </.button>
        </:actions>
        <div id="person-organizations" class="space-y-3">
          <div :if={Enum.empty?(@person.organizations || [])}>
            <.empty_state
              icon="hero-building-office-2"
              title="No organizations linked"
              description="Create affiliations to connect this person to customers, prospects, or partners."
            />
          </div>

          <.link
            :for={organization <- @person.organizations || []}
            navigate={~p"/operations/organizations/#{organization}"}
            class="flex items-center justify-between rounded-2xl border border-zinc-200 bg-zinc-50/70 px-4 py-4 transition hover:border-emerald-300 hover:bg-white dark:border-white/10 dark:bg-white/[0.03] dark:hover:border-emerald-400/40"
          >
            <div class="space-y-1">
              <p class="font-medium text-zinc-900 dark:text-white">{organization.name}</p>
              <p class="text-sm text-zinc-500 dark:text-zinc-400">
                {format_roles(organization.relationship_roles)}
              </p>
            </div>
            <.status_badge status={organization.status_variant}>
              {format_atom(organization.status)}
            </.status_badge>
          </.link>
        </div>
      </.section>
    </.page>
    """
  end

  defp load_person!(id, actor) do
    case Operations.get_person(
           id,
           actor: actor,
           load: [
             :full_name,
             :status_variant,
             :organization_count,
             :requested_service_tickets,
             organizations: [:status_variant]
           ]
         ) do
      {:ok, person} -> person
      {:error, error} -> raise "failed to load person #{id}: #{inspect(error)}"
    end
  end

  defp load_merge_review!(person, actor) do
    case IdentityMergeReview.person_review(person, actor: actor) do
      {:ok, merge_review} -> merge_review
      {:error, error} -> raise "failed to load person merge review: #{inspect(error)}"
    end
  end

  defp candidate_person_organizations(person) do
    case person.organizations || [] do
      [] -> "No linked organizations"
      organizations -> organizations |> Enum.map(& &1.name) |> Enum.join(", ")
    end
  end

  defp format_merge_reason(:name_key), do: "Same Normalized Name"
  defp format_merge_reason(:email_domain), do: "Same Email Domain"
  defp format_merge_reason(:shared_organization), do: "Shared Organization"
  defp format_merge_reason(reason), do: format_atom(reason)

  defp merge_reason_tag_color(:name_key), do: :sky
  defp merge_reason_tag_color(:email_domain), do: :emerald
  defp merge_reason_tag_color(:shared_organization), do: :amber
  defp merge_reason_tag_color(_reason), do: :zinc
end
