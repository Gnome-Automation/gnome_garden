defmodule GnomeGardenWeb.Components.Acquisition.DiscoveryContext do
  @moduledoc """
  Discovery-origin finding context, feedback, and evidence sections.
  """

  use GnomeGardenWeb, :html

  import GnomeGardenWeb.Commercial.Helpers, only: [format_atom: 1, format_datetime: 1]

  alias GnomeGarden.Commercial.DiscoveryFeedback

  attr :discovery_record, :map, required: true

  def discovery_context_section(assigns) do
    ~H"""
    <.section
      title="Discovery Context"
      description="Discovery-origin findings keep their discovery record context here so no separate legacy detail page is needed."
    >
      <div class="grid gap-5 sm:grid-cols-2">
        <.property_item label="Website" value={@discovery_record.website || "-"} />
        <.property_item label="Domain" value={@discovery_record.website_domain || "-"} />
        <.property_item
          label="Discovery Program"
          value={
            (@discovery_record.discovery_program && @discovery_record.discovery_program.name) ||
              "-"
          }
        />
        <.property_item
          label="Linked Organization"
          value={(@discovery_record.organization && @discovery_record.organization.name) || "-"}
        />
        <.property_item
          label="Contact Person"
          value={
            (@discovery_record.contact_person && @discovery_record.contact_person.full_name) || "-"
          }
        />
        <.property_item
          label="Evidence Count"
          value={Integer.to_string(@discovery_record.discovery_evidence_count || 0)}
        />
        <.property_item
          label="Latest Observed"
          value={format_datetime(@discovery_record.latest_evidence_at)}
        />
        <.property_item
          label="Discovery Record Status"
          value={format_atom(@discovery_record.status)}
          badge={@discovery_record.status_variant}
        />
      </div>

      <div
        :if={
          discovery_record_icp_matches(@discovery_record) != [] or
            discovery_record_risk_flags(@discovery_record) != []
        }
        class="mt-5 grid gap-4 sm:grid-cols-2"
      >
        <div
          :if={discovery_record_icp_matches(@discovery_record) != []}
          id="finding-show-discovery-icp"
        >
          <p class="text-xs font-semibold uppercase tracking-[0.2em] text-base-content/40">
            Why It Fits
          </p>
          <div class="mt-2 flex flex-wrap gap-1">
            <span
              :for={match <- discovery_record_icp_matches(@discovery_record)}
              class="badge badge-success badge-sm"
            >
              {match}
            </span>
          </div>
        </div>

        <div
          :if={discovery_record_risk_flags(@discovery_record) != []}
          id="finding-show-discovery-risks"
        >
          <p class="text-xs font-semibold uppercase tracking-[0.2em] text-base-content/40">
            Watchouts
          </p>
          <div class="mt-2 flex flex-wrap gap-1">
            <span
              :for={flag <- discovery_record_risk_flags(@discovery_record)}
              class="badge badge-outline badge-sm border-amber-300 bg-white/70 text-amber-700 dark:border-amber-400/30 dark:bg-white/[0.03] dark:text-amber-200"
            >
              {flag}
            </span>
          </div>
        </div>
      </div>
    </.section>
    """
  end

  attr :discovery_record, :map, required: true

  def discovery_feedback_section(assigns) do
    ~H"""
    <.section
      :if={discovery_feedback(@discovery_record)}
      title="Discovery Feedback"
      description="Rejected discovery stays explainable and continues teaching the shared targeting model."
    >
      <div class="grid gap-5 sm:grid-cols-2">
        <.property_item
          label="Disposition"
          value={format_feedback_reason(discovery_feedback(@discovery_record))}
        />
        <.property_item
          label="Feedback Scope"
          value={format_value(discovery_feedback(@discovery_record)["feedback_scope"])}
        />
        <.property_item
          label="Learned Terms"
          value={render_feedback_terms(discovery_feedback(@discovery_record)["exclude_terms"])}
        />
        <.property_item
          label="Category"
          value={format_value(discovery_feedback(@discovery_record)["source_feedback_category"])}
        />
      </div>
    </.section>
    """
  end

  attr :discovery_record, :map, default: nil
  attr :discovery_evidence, :list, default: []

  def evidence_section(assigns) do
    ~H"""
    <.section
      :if={@discovery_record}
      title="Evidence"
      description="Raw discovery evidence stays attached to the finding so promotion remains explainable."
    >
      <div :if={Enum.empty?(@discovery_evidence)}>
        <.empty_state
          icon="hero-document-magnifying-glass"
          title="No evidence yet"
          description="Discovery runs and operators can still attach evidence before or after review."
        />
      </div>

      <div :if={!Enum.empty?(@discovery_evidence)} class="space-y-3">
        <div
          :for={evidence <- @discovery_evidence}
          class="rounded-2xl border border-zinc-200 bg-zinc-50/70 px-4 py-4 dark:border-white/10 dark:bg-white/[0.03]"
        >
          <div class="flex flex-wrap items-start justify-between gap-3">
            <div class="space-y-2">
              <div class="flex flex-wrap gap-2">
                <.tag color={:zinc}>{format_atom(evidence.observation_type)}</.tag>
                <.tag color={:sky}>{format_atom(evidence.source_channel)}</.tag>
                <.status_badge status={evidence.confidence_variant}>
                  Confidence {evidence.confidence_score}
                </.status_badge>
              </div>
              <p class="font-medium text-base-content">{evidence.summary}</p>
              <p class="text-xs text-base-content/40">
                {format_datetime(evidence.observed_at || evidence.inserted_at)}
              </p>
            </div>
            <div class="flex flex-wrap gap-3">
              <.link
                :if={evidence.source_url}
                href={evidence.source_url}
                target="_blank"
                class="text-sm font-medium text-emerald-600 hover:text-emerald-500 dark:text-emerald-300"
              >
                Source
              </.link>
              <.link
                navigate={~p"/acquisition/evidence/#{evidence.id}/edit"}
                class="text-sm font-medium text-sky-600 hover:text-sky-500 dark:text-sky-300"
              >
                Edit
              </.link>
            </div>
          </div>

          <p
            :if={evidence.raw_excerpt}
            class="mt-3 whitespace-pre-wrap text-sm leading-6 text-base-content/70"
          >
            {evidence.raw_excerpt}
          </p>

          <div :if={evidence.evidence_points != []} class="mt-3 flex flex-wrap gap-2">
            <span
              :for={point <- evidence.evidence_points}
              class="badge badge-outline badge-sm border-zinc-200 bg-white/80 text-zinc-700 dark:border-white/10 dark:bg-transparent dark:text-zinc-300"
            >
              {point}
            </span>
          </div>
        </div>
      </div>
    </.section>
    """
  end

  attr :label, :string, required: true
  attr :value, :string, required: true
  attr :badge, :atom, default: nil

  defp property_item(assigns) do
    ~H"""
    <div class="space-y-1">
      <p class="text-xs font-semibold uppercase tracking-[0.2em] text-base-content/40">
        {@label}
      </p>
      <p :if={is_nil(@badge)} class="text-sm font-medium text-base-content">
        {@value}
      </p>
      <.status_badge :if={@badge} status={@badge}>{@value}</.status_badge>
    </div>
    """
  end

  defp discovery_feedback(discovery_record) do
    metadata = Map.get(discovery_record, :metadata) || %{}
    metadata["discovery_feedback"]
  end

  defp discovery_record_market_focus(discovery_record) do
    metadata = Map.get(discovery_record, :metadata) || %{}
    Map.get(metadata, "market_focus", %{})
  end

  defp discovery_record_icp_matches(discovery_record) do
    discovery_record
    |> discovery_record_market_focus()
    |> Map.get("icp_matches", [])
    |> List.wrap()
  end

  defp discovery_record_risk_flags(discovery_record) do
    discovery_record
    |> discovery_record_market_focus()
    |> Map.get("risk_flags", [])
    |> List.wrap()
  end

  defp render_feedback_terms(nil), do: "-"
  defp render_feedback_terms([]), do: "-"
  defp render_feedback_terms(terms), do: Enum.join(List.wrap(terms), ", ")

  defp format_feedback_reason(nil), do: "-"

  defp format_feedback_reason(feedback) when is_map(feedback) do
    reason_code = Map.get(feedback, "reason_code")
    reason = metadata_value(feedback, :reason)
    label = DiscoveryFeedback.reject_reason_label(reason_code)

    if reason in [nil, "", label], do: label, else: "#{label} - #{reason}"
  end

  defp format_feedback_reason(feedback), do: to_string(feedback)

  defp metadata_value(nil, _key), do: nil

  defp metadata_value(map, key) when is_map(map) do
    Map.get(map, key) || Map.get(map, String.to_existing_atom(key))
  rescue
    ArgumentError -> Map.get(map, key)
  end

  defp metadata_value(_value, _key), do: nil

  defp format_value(nil), do: "-"

  defp format_value(value) do
    value
    |> to_string()
    |> String.replace("_", " ")
  end
end
