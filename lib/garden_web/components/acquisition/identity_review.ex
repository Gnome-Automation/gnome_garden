defmodule GnomeGardenWeb.Components.Acquisition.IdentityReview do
  @moduledoc """
  Identity resolution panel for discovery-origin acquisition findings.
  """

  use GnomeGardenWeb, :html

  import GnomeGardenWeb.Commercial.Helpers, only: [format_atom: 1]

  attr :discovery_record, :map, required: true
  attr :identity_review, :map, default: nil

  def identity_review_section(assigns) do
    ~H"""
    <.section
      :if={show_identity_review?(@discovery_record, @identity_review)}
      title="Identity Review"
      description="Resolve the canonical organization and person here before this finding becomes owned commercial work."
    >
      <div class="grid gap-6">
        <div class="space-y-4">
          <div class="space-y-2">
            <p class="text-xs font-semibold uppercase tracking-[0.2em] text-base-content/40">
              Organization
            </p>
            <div class="rounded-2xl border border-zinc-200 bg-zinc-50/70 px-4 py-4 dark:border-white/10 dark:bg-white/[0.03]">
              <%= if @discovery_record.organization do %>
                <div class="flex items-center justify-between gap-3">
                  <div class="space-y-1">
                    <.link
                      navigate={~p"/operations/organizations/#{@discovery_record.organization}"}
                      class="font-medium text-zinc-900 hover:text-emerald-600 dark:text-white"
                    >
                      {@discovery_record.organization.name}
                    </.link>
                    <p class="text-sm text-base-content/50">
                      {@discovery_record.organization.website_domain ||
                        @discovery_record.organization.primary_region ||
                        "Linked organization"}
                    </p>
                  </div>
                  <.status_badge status={@discovery_record.organization.status_variant}>
                    {format_atom(@discovery_record.organization.status)}
                  </.status_badge>
                </div>
              <% else %>
                <p class="text-sm text-base-content/50">
                  No durable organization linked yet.
                </p>
              <% end %>
            </div>
          </div>

          <div
            :if={@identity_review && @identity_review.organization_candidates != []}
            class="space-y-3"
          >
            <p class="text-xs font-semibold uppercase tracking-[0.2em] text-base-content/40">
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
                  <p class="text-sm text-base-content/50">
                    {organization.website_domain || organization.primary_region || "No domain"}
                  </p>
                  <p class="text-xs text-base-content/40">
                    {organization.people_count} people · {organization.signal_count} signals
                  </p>
                </div>
                <div class="flex flex-wrap gap-2">
                  <.button
                    id={"finding-use-organization-#{organization.id}"}
                    phx-click="resolve_identity"
                    phx-value-organization_id={organization.id}
                    variant="primary"
                  >
                    Use Organization
                  </.button>
                  <.button
                    :if={
                      @discovery_record.organization &&
                        @discovery_record.organization.id != organization.id
                    }
                    id={"finding-merge-linked-organization-#{organization.id}"}
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
            <p class="text-xs font-semibold uppercase tracking-[0.2em] text-base-content/40">
              Contact Person
            </p>
            <div class="rounded-2xl border border-zinc-200 bg-zinc-50/70 px-4 py-4 dark:border-white/10 dark:bg-white/[0.03]">
              <%= if @discovery_record.contact_person do %>
                <div class="flex items-center justify-between gap-3">
                  <div class="space-y-1">
                    <.link
                      navigate={~p"/operations/people/#{@discovery_record.contact_person}"}
                      class="font-medium text-zinc-900 hover:text-emerald-600 dark:text-white"
                    >
                      {@discovery_record.contact_person.full_name}
                    </.link>
                    <p class="text-sm text-base-content/50">
                      {@discovery_record.contact_person.email ||
                        @discovery_record.contact_person.phone ||
                        "No direct contact details"}
                    </p>
                  </div>
                  <.status_badge status={@discovery_record.contact_person.status_variant}>
                    {format_atom(@discovery_record.contact_person.status)}
                  </.status_badge>
                </div>
              <% else %>
                <div class="space-y-1">
                  <p class="text-sm text-base-content/50">
                    No durable contact linked yet.
                  </p>
                  <p
                    :if={@identity_review && @identity_review.contact_snapshot}
                    class="text-sm text-base-content/70"
                  >
                    {format_contact_snapshot(@identity_review.contact_snapshot)}
                  </p>
                </div>
              <% end %>
            </div>
          </div>

          <div
            :if={@identity_review && @identity_review.person_candidates != []}
            class="space-y-3"
          >
            <p class="text-xs font-semibold uppercase tracking-[0.2em] text-base-content/40">
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
                  <p class="text-sm text-base-content/50">
                    {person.email || person.phone || "No direct contact details"}
                  </p>
                  <p class="text-xs text-base-content/40">
                    {candidate_person_organizations(person)}
                  </p>
                </div>
                <div class="flex flex-wrap gap-2">
                  <.button
                    id={"finding-use-person-#{person.id}"}
                    phx-click="resolve_identity"
                    phx-value-contact_person_id={person.id}
                    variant="primary"
                  >
                    Use Person
                  </.button>
                  <.button
                    :if={
                      @discovery_record.contact_person &&
                        @discovery_record.contact_person.id != person.id
                    }
                    id={"finding-merge-linked-person-#{person.id}"}
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
    """
  end

  defp show_identity_review?(_discovery_record, nil), do: false

  defp show_identity_review?(discovery_record, identity_review) do
    not is_nil(discovery_record.contact_person_id) or
      not is_nil(discovery_record.organization_id) or
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

  defp metadata_value(nil, _key), do: nil

  defp metadata_value(map, key) when is_map(map) do
    Map.get(map, key) || Map.get(map, String.to_existing_atom(key))
  rescue
    ArgumentError -> Map.get(map, key)
  end

  defp metadata_value(_value, _key), do: nil
end
