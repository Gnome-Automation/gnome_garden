defmodule GnomeGardenWeb.Commercial.TargetAccountLive.Show do
  use GnomeGardenWeb, :live_view

  import GnomeGardenWeb.Commercial.Helpers

  alias GnomeGarden.Commercial
  alias GnomeGarden.Commercial.DiscoveryIdentityResolver
  alias GnomeGarden.Operations

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    target_account = load_target_account!(id, socket.assigns.current_user)
    observations = load_observations(id, socket.assigns.current_user)
    identity_review = load_identity_review(target_account, socket.assigns.current_user)

    {:ok,
     socket
     |> assign(:page_title, target_account.name)
     |> assign(:target_account, target_account)
     |> assign(:observations, observations)
     |> assign(:identity_review, identity_review)}
  end

  @impl true
  def handle_event("transition", %{"action" => action}, socket) do
    target_account = socket.assigns.target_account

    case transition_target_account(
           target_account,
           String.to_existing_atom(action),
           socket.assigns.current_user
         ) do
      {:ok, updated_target_account} ->
        refreshed_target_account = reload_target_account(updated_target_account.id, socket)

        {:noreply,
         socket
         |> assign(:target_account, refreshed_target_account)
         |> assign(
           :observations,
           load_observations(updated_target_account.id, socket.assigns.current_user)
         )
         |> assign(
           :identity_review,
           load_identity_review(refreshed_target_account, socket.assigns.current_user)
         )
         |> put_flash(:info, "Target account updated")}

      {:error, error} ->
        {:noreply,
         put_flash(socket, :error, "Could not update target account: #{inspect(error)}")}
    end
  end

  @impl true
  def handle_event("resolve_identity", params, socket) do
    attrs =
      %{}
      |> maybe_put_identity_attr(:organization_id, Map.get(params, "organization_id"))
      |> maybe_put_identity_attr(:contact_person_id, Map.get(params, "contact_person_id"))

    case Commercial.resolve_target_account_identity(
           socket.assigns.target_account,
           attrs,
           actor: socket.assigns.current_user
         ) do
      {:ok, updated_target_account} ->
        refreshed_target_account = reload_target_account(updated_target_account.id, socket)

        {:noreply,
         socket
         |> assign(:target_account, refreshed_target_account)
         |> assign(
           :identity_review,
           load_identity_review(refreshed_target_account, socket.assigns.current_user)
         )
         |> put_flash(:info, "Target identity updated")}

      {:error, error} ->
        {:noreply, put_flash(socket, :error, "Could not resolve identity: #{inspect(error)}")}
    end
  end

  @impl true
  def handle_event("merge_organization", %{"organization_id" => organization_id}, socket) do
    case socket.assigns.target_account.organization do
      nil ->
        {:noreply, put_flash(socket, :error, "No linked organization to merge")}

      source_organization ->
        case Operations.merge_organization(
               source_organization,
               %{into_organization_id: organization_id},
               actor: socket.assigns.current_user
             ) do
          {:ok, _merged_organization} ->
            refreshed_target_account =
              reload_target_account(socket.assigns.target_account.id, socket)

            {:noreply,
             socket
             |> assign(:target_account, refreshed_target_account)
             |> assign(
               :identity_review,
               load_identity_review(refreshed_target_account, socket.assigns.current_user)
             )
             |> put_flash(:info, "Linked organization merged into candidate")}

          {:error, error} ->
            {:noreply,
             put_flash(socket, :error, "Could not merge organization: #{inspect(error)}")}
        end
    end
  end

  @impl true
  def handle_event("merge_person", %{"person_id" => person_id}, socket) do
    case socket.assigns.target_account.contact_person do
      nil ->
        {:noreply, put_flash(socket, :error, "No linked person to merge")}

      source_person ->
        case Operations.merge_person(
               source_person,
               %{into_person_id: person_id},
               actor: socket.assigns.current_user
             ) do
          {:ok, _merged_person} ->
            refreshed_target_account =
              reload_target_account(socket.assigns.target_account.id, socket)

            {:noreply,
             socket
             |> assign(:target_account, refreshed_target_account)
             |> assign(
               :identity_review,
               load_identity_review(refreshed_target_account, socket.assigns.current_user)
             )
             |> put_flash(:info, "Linked person merged into candidate")}

          {:error, error} ->
            {:noreply, put_flash(socket, :error, "Could not merge person: #{inspect(error)}")}
        end
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.page class="pb-8">
      <.page_header eyebrow="Commercial">
        {@target_account.name}
        <:subtitle>
          <span class="inline-flex items-center gap-2">
            <.status_badge status={@target_account.status_variant}>
              {format_atom(@target_account.status)}
            </.status_badge>
            <span class="text-zinc-400 dark:text-zinc-500">/</span>
            <span>{@target_account.website_domain || "No website domain"}</span>
          </span>
        </:subtitle>
        <:actions>
          <.button navigate={~p"/commercial/targets"}>
            <.icon name="hero-arrow-left" class="size-4" /> Back
          </.button>
          <.button navigate={new_observation_path(@target_account)}>
            <.icon name="hero-plus" class="size-4" /> New Observation
          </.button>
          <.button
            :if={@target_account.promoted_signal}
            navigate={~p"/commercial/signals/#{@target_account.promoted_signal}"}
            variant="primary"
          >
            <.icon name="hero-inbox-stack" class="size-4" /> Open Signal
          </.button>
          <.button navigate={~p"/commercial/targets/#{@target_account}/edit"}>
            <.icon name="hero-pencil-square" class="size-4" /> Edit
          </.button>
        </:actions>
      </.page_header>

      <.section
        title="Review Actions"
        description="Promote only the target accounts that deserve real commercial attention."
      >
        <div class="flex flex-wrap gap-3">
          <.button
            :for={action <- target_actions(@target_account)}
            phx-click="transition"
            phx-value-action={action.action}
            variant={action.variant}
          >
            <.icon name={action.icon} class="size-4" /> {action.label}
          </.button>
        </div>
      </.section>

      <.section
        :if={show_identity_review?(@target_account, @identity_review)}
        title="Identity Review"
        description="Discovery can match the wrong org or contact. Resolve identity here before this target turns into owned commercial work."
      >
        <div class="grid gap-6 xl:grid-cols-2">
          <div class="space-y-4">
            <div class="space-y-2">
              <p class="text-xs font-semibold uppercase tracking-[0.2em] text-zinc-400 dark:text-zinc-500">
                Organization
              </p>
              <div class="rounded-2xl border border-zinc-200 bg-zinc-50/70 px-4 py-4 dark:border-white/10 dark:bg-white/[0.03]">
                <%= if @target_account.organization do %>
                  <div class="flex items-center justify-between gap-3">
                    <div class="space-y-1">
                      <.link
                        navigate={~p"/operations/organizations/#{@target_account.organization}"}
                        class="font-medium text-zinc-900 hover:text-emerald-600 dark:text-white"
                      >
                        {@target_account.organization.name}
                      </.link>
                      <p class="text-sm text-zinc-500 dark:text-zinc-400">
                        {@target_account.organization.website_domain ||
                          @target_account.organization.primary_region ||
                          "Linked organization"}
                      </p>
                    </div>
                    <.status_badge status={@target_account.organization.status_variant}>
                      {format_atom(@target_account.organization.status)}
                    </.status_badge>
                  </div>
                <% else %>
                  <p class="text-sm text-zinc-500 dark:text-zinc-400">
                    No durable organization linked yet.
                  </p>
                <% end %>
              </div>
            </div>

            <div :if={@identity_review.organization_candidates != []} class="space-y-3">
              <p class="text-xs font-semibold uppercase tracking-[0.2em] text-zinc-400 dark:text-zinc-500">
                Candidate Organizations
              </p>
              <div
                :for={organization <- @identity_review.organization_candidates}
                class="rounded-2xl border border-zinc-200 px-4 py-4 dark:border-white/10"
              >
                <div class="flex flex-wrap items-start justify-between gap-3">
                  <div class="space-y-1">
                    <.link
                      navigate={~p"/operations/organizations/#{organization}"}
                      class="font-medium text-zinc-900 hover:text-emerald-600 dark:text-white"
                    >
                      {organization.name}
                    </.link>
                    <p class="text-sm text-zinc-500 dark:text-zinc-400">
                      {organization.website_domain || organization.primary_region || "No domain"}
                    </p>
                    <p class="text-xs text-zinc-400 dark:text-zinc-500">
                      {organization.people_count} people · {organization.signal_count} signals
                    </p>
                  </div>
                  <div class="flex flex-wrap gap-2">
                    <.button
                      id={"use-organization-#{organization.id}"}
                      phx-click="resolve_identity"
                      phx-value-organization_id={organization.id}
                      variant="primary"
                    >
                      Use Organization
                    </.button>
                    <.button
                      :if={
                        @target_account.organization &&
                          @target_account.organization.id != organization.id
                      }
                      id={"merge-linked-organization-#{organization.id}"}
                      phx-click="merge_organization"
                      phx-value-organization_id={organization.id}
                    >
                      Merge Linked Org
                    </.button>
                  </div>
                </div>
              </div>
            </div>
          </div>

          <div class="space-y-4">
            <div class="space-y-2">
              <p class="text-xs font-semibold uppercase tracking-[0.2em] text-zinc-400 dark:text-zinc-500">
                Contact Person
              </p>
              <div class="rounded-2xl border border-zinc-200 bg-zinc-50/70 px-4 py-4 dark:border-white/10 dark:bg-white/[0.03]">
                <%= if @target_account.contact_person do %>
                  <div class="flex items-center justify-between gap-3">
                    <div class="space-y-1">
                      <.link
                        navigate={~p"/operations/people/#{@target_account.contact_person}"}
                        class="font-medium text-zinc-900 hover:text-emerald-600 dark:text-white"
                      >
                        {@target_account.contact_person.full_name}
                      </.link>
                      <p class="text-sm text-zinc-500 dark:text-zinc-400">
                        {@target_account.contact_person.email || @target_account.contact_person.phone ||
                          "No direct contact details"}
                      </p>
                    </div>
                    <.status_badge status={@target_account.contact_person.status_variant}>
                      {format_atom(@target_account.contact_person.status)}
                    </.status_badge>
                  </div>
                <% else %>
                  <div class="space-y-1">
                    <p class="text-sm text-zinc-500 dark:text-zinc-400">
                      No durable contact linked yet.
                    </p>
                    <p
                      :if={@identity_review.contact_snapshot}
                      class="text-sm text-zinc-600 dark:text-zinc-300"
                    >
                      {format_contact_snapshot(@identity_review.contact_snapshot)}
                    </p>
                  </div>
                <% end %>
              </div>
            </div>

            <div :if={@identity_review.person_candidates != []} class="space-y-3">
              <p class="text-xs font-semibold uppercase tracking-[0.2em] text-zinc-400 dark:text-zinc-500">
                Candidate People
              </p>
              <div
                :for={person <- @identity_review.person_candidates}
                class="rounded-2xl border border-zinc-200 px-4 py-4 dark:border-white/10"
              >
                <div class="flex flex-wrap items-start justify-between gap-3">
                  <div class="space-y-1">
                    <.link
                      navigate={~p"/operations/people/#{person}"}
                      class="font-medium text-zinc-900 hover:text-emerald-600 dark:text-white"
                    >
                      {person.full_name}
                    </.link>
                    <p class="text-sm text-zinc-500 dark:text-zinc-400">
                      {person.email || person.phone || "No direct contact details"}
                    </p>
                    <p class="text-xs text-zinc-400 dark:text-zinc-500">
                      {candidate_person_organizations(person)}
                    </p>
                  </div>
                  <div class="flex flex-wrap gap-2">
                    <.button
                      id={"use-person-#{person.id}"}
                      phx-click="resolve_identity"
                      phx-value-contact_person_id={person.id}
                      variant="primary"
                    >
                      Use Person
                    </.button>
                    <.button
                      :if={
                        @target_account.contact_person &&
                          @target_account.contact_person.id != person.id
                      }
                      id={"merge-linked-person-#{person.id}"}
                      phx-click="merge_person"
                      phx-value-person_id={person.id}
                    >
                      Merge Linked Person
                    </.button>
                  </div>
                </div>
              </div>
            </div>
          </div>
        </div>
      </.section>

      <div class="grid gap-6 lg:grid-cols-2">
        <.section title="Target Context">
          <div class="grid gap-5 sm:grid-cols-2">
            <.property_item label="Website" value={@target_account.website || "-"} />
            <.property_item label="Domain" value={@target_account.website_domain || "-"} />
            <.property_item label="Location" value={@target_account.location || "-"} />
            <.property_item label="Region" value={@target_account.region || "-"} />
            <.property_item label="Industry" value={@target_account.industry || "-"} />
            <.property_item
              label="Discovery Program"
              value={
                (@target_account.discovery_program && @target_account.discovery_program.name) || "-"
              }
            />
            <.property_item
              label="Organization"
              value={(@target_account.organization && @target_account.organization.name) || "-"}
            />
            <.property_item
              label="Contact Person"
              value={
                (@target_account.contact_person && @target_account.contact_person.full_name) || "-"
              }
            />
          </div>
        </.section>

        <.section title="Scoring">
          <div class="grid gap-5 sm:grid-cols-2">
            <.property_item label="Fit Score" value={Integer.to_string(@target_account.fit_score)} />
            <.property_item
              label="Intent Score"
              value={Integer.to_string(@target_account.intent_score)}
            />
            <.property_item
              label="Observation Count"
              value={Integer.to_string(@target_account.observation_count)}
            />
            <.property_item
              label="Latest Observed"
              value={format_datetime(@target_account.latest_observed_at)}
            />
          </div>
        </.section>
      </div>

      <.section :if={@target_account.notes} title="Notes">
        <p class="whitespace-pre-wrap text-sm leading-6 text-zinc-600 dark:text-zinc-300">
          {@target_account.notes}
        </p>
      </.section>

      <.section
        title="Observations"
        description="Raw evidence stays attached here so the signal inbox only gets promoted, human-approved accounts."
      >
        <div :if={Enum.empty?(@observations)}>
          <.empty_state
            icon="hero-document-magnifying-glass"
            title="No observations yet"
            description="Scanners and operators can attach evidence here before the target becomes a signal."
          />
        </div>

        <div :if={!Enum.empty?(@observations)} class="space-y-3">
          <div
            :for={observation <- @observations}
            class="rounded-2xl border border-zinc-200 bg-zinc-50/70 px-4 py-4 dark:border-white/10 dark:bg-white/[0.03]"
          >
            <div class="flex flex-wrap items-start justify-between gap-3">
              <div class="space-y-2">
                <div class="flex flex-wrap gap-2">
                  <.tag color={:zinc}>{format_atom(observation.observation_type)}</.tag>
                  <.tag color={:sky}>{format_atom(observation.source_channel)}</.tag>
                  <.status_badge status={observation.confidence_variant}>
                    Confidence {observation.confidence_score}
                  </.status_badge>
                </div>
                <p class="font-medium text-zinc-900 dark:text-white">{observation.summary}</p>
                <p class="text-xs text-zinc-400 dark:text-zinc-500">
                  {format_datetime(observation.observed_at || observation.inserted_at)}
                </p>
              </div>
              <.link
                :if={observation.source_url}
                href={observation.source_url}
                target="_blank"
                class="text-sm font-medium text-emerald-600 hover:text-emerald-500 dark:text-emerald-300"
              >
                Source
              </.link>
              <.link
                navigate={~p"/commercial/observations/#{observation}"}
                class="text-sm font-medium text-sky-600 hover:text-sky-500 dark:text-sky-300"
              >
                Details
              </.link>
            </div>

            <p
              :if={observation.raw_excerpt}
              class="mt-3 text-sm leading-6 text-zinc-600 dark:text-zinc-300"
            >
              {observation.raw_excerpt}
            </p>
          </div>
        </div>
      </.section>
    </.page>
    """
  end

  attr :label, :string, required: true
  attr :value, :string, required: true

  defp property_item(assigns) do
    ~H"""
    <div class="space-y-1">
      <p class="text-xs font-semibold uppercase tracking-[0.2em] text-zinc-400 dark:text-zinc-500">
        {@label}
      </p>
      <div class="flex flex-wrap items-center gap-2">
        <p class="text-sm font-medium text-zinc-900 dark:text-white">{@value}</p>
      </div>
    </div>
    """
  end

  defp load_target_account!(id, actor) do
    case Commercial.get_target_account(
           id,
           actor: actor,
           load: [
             :discovery_program,
             :promoted_signal,
             :status_variant,
             :observation_count,
             :latest_observed_at,
             organization: [:status_variant],
             contact_person: [:full_name, :status_variant, organizations: []]
           ]
         ) do
      {:ok, target_account} -> target_account
      {:error, error} -> raise "failed to load target account #{id}: #{inspect(error)}"
    end
  end

  defp reload_target_account(id, socket) do
    load_target_account!(id, socket.assigns.current_user)
  end

  defp load_observations(id, actor) do
    case Commercial.list_target_observations_for_target_account(
           id,
           actor: actor,
           load: [:confidence_variant]
         ) do
      {:ok, observations} -> observations
      {:error, error} -> raise "failed to load target observations: #{inspect(error)}"
    end
  end

  defp target_actions(%{status: :new}) do
    [
      %{action: "start_review", label: "Start Review", icon: "hero-eye", variant: nil},
      %{
        action: "promote_to_signal",
        label: "Promote To Signal",
        icon: "hero-arrow-up-right",
        variant: "primary"
      },
      %{action: "reject", label: "Reject", icon: "hero-x-mark", variant: nil},
      %{action: "archive", label: "Archive", icon: "hero-archive-box", variant: nil}
    ]
  end

  defp target_actions(%{status: :reviewing}) do
    [
      %{
        action: "promote_to_signal",
        label: "Promote To Signal",
        icon: "hero-arrow-up-right",
        variant: "primary"
      },
      %{action: "reject", label: "Reject", icon: "hero-x-mark", variant: nil},
      %{action: "archive", label: "Archive", icon: "hero-archive-box", variant: nil}
    ]
  end

  defp target_actions(%{status: :promoted}) do
    [
      %{action: "archive", label: "Archive", icon: "hero-archive-box", variant: nil}
    ]
  end

  defp target_actions(%{status: :rejected}) do
    [
      %{action: "reopen", label: "Reopen", icon: "hero-arrow-path", variant: "primary"},
      %{action: "archive", label: "Archive", icon: "hero-archive-box", variant: nil}
    ]
  end

  defp target_actions(%{status: :archived}) do
    [
      %{action: "reopen", label: "Reopen", icon: "hero-arrow-path", variant: "primary"}
    ]
  end

  defp target_actions(_target_account), do: []

  defp transition_target_account(target_account, :start_review, actor),
    do: Commercial.review_target_account(target_account, actor: actor)

  defp transition_target_account(target_account, :promote_to_signal, actor),
    do: Commercial.promote_target_account_to_signal(target_account, actor: actor)

  defp transition_target_account(target_account, :reject, actor),
    do: Commercial.reject_target_account(target_account, %{}, actor: actor)

  defp transition_target_account(target_account, :archive, actor),
    do: Commercial.archive_target_account(target_account, actor: actor)

  defp transition_target_account(target_account, :reopen, actor),
    do: Commercial.reopen_target_account(target_account, actor: actor)

  defp load_identity_review(target_account, actor) do
    case DiscoveryIdentityResolver.target_review_context(target_account, actor: actor) do
      {:ok, identity_review} -> identity_review
      {:error, error} -> raise "failed to load target identity review: #{inspect(error)}"
    end
  end

  defp maybe_put_identity_attr(attrs, _key, nil), do: attrs
  defp maybe_put_identity_attr(attrs, _key, ""), do: attrs
  defp maybe_put_identity_attr(attrs, key, value), do: Map.put(attrs, key, value)

  defp show_identity_review?(target_account, identity_review) do
    not is_nil(target_account.contact_person_id) or
      not is_nil(target_account.organization_id) or
      not is_nil(identity_review.contact_snapshot) or
      identity_review.organization_candidates != [] or
      identity_review.person_candidates != []
  end

  defp format_contact_snapshot(snapshot) do
    [metadata_value(snapshot, :first_name), metadata_value(snapshot, :last_name)]
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.join(" ")
    |> case do
      "" ->
        metadata_value(snapshot, :email) || metadata_value(snapshot, :phone) || "Contact snapshot"

      name ->
        [name, metadata_value(snapshot, :title), metadata_value(snapshot, :email)]
        |> Enum.reject(&(&1 in [nil, ""]))
        |> Enum.join(" · ")
    end
  end

  defp candidate_person_organizations(person) do
    case person.organizations || [] do
      [] -> "No linked organizations"
      organizations -> organizations |> Enum.map(& &1.name) |> Enum.join(", ")
    end
  end

  defp metadata_value(metadata, key) when is_map(metadata),
    do: Map.get(metadata, key) || Map.get(metadata, to_string(key))

  defp metadata_value(_metadata, _key), do: nil

  defp new_observation_path(target_account) do
    params =
      [
        target_account_id: target_account.id,
        discovery_program_id: target_account.discovery_program_id
      ]
      |> Enum.reject(fn {_key, value} -> is_nil(value) end)

    ~p"/commercial/observations/new?#{params}"
  end
end
