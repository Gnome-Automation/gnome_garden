defmodule GnomeGardenWeb.Components.Acquisition.ReviewHistory do
  @moduledoc """
  Review decision history for acquisition findings.
  """

  use GnomeGardenWeb, :html

  import GnomeGardenWeb.Commercial.Helpers, only: [format_datetime: 1]

  attr :review_decisions, :list, default: []

  def review_history_section(assigns) do
    ~H"""
    <.section
      title="Review History"
      description="Why operators advanced, rejected, suppressed, parked, reopened, or promoted this finding."
    >
      <div :if={Enum.empty?(@review_decisions)}>
        <.empty_state
          icon="hero-chat-bubble-left-right"
          title="No review history yet"
          description="Decision history will appear here as the finding moves through intake review."
        />
      </div>

      <div :if={!Enum.empty?(@review_decisions)} class="space-y-3">
        <div
          :for={decision <- @review_decisions}
          class="rounded-2xl border border-zinc-200 bg-zinc-50/70 px-4 py-4 dark:border-white/10 dark:bg-white/[0.03]"
        >
          <div class="flex flex-wrap items-start justify-between gap-3">
            <div class="space-y-2">
              <div class="flex flex-wrap items-center gap-2">
                <.tag color={decision_tag_color(decision.decision)}>
                  {format_review_decision(decision.decision)}
                </.tag>
                <span class="text-xs text-base-content/40">
                  {format_datetime(decision.recorded_at || decision.inserted_at)}
                </span>
              </div>
              <p :if={decision.reason} class="text-sm text-base-content/80">
                {decision.reason}
              </p>
              <div class="flex flex-wrap gap-2 text-xs text-base-content/50">
                <span :if={decision.reason_code}>
                  Code: {format_value(decision.reason_code)}
                </span>
                <span :if={decision.feedback_scope}>
                  Scope: {format_value(decision.feedback_scope)}
                </span>
                <span :if={decision.exclude_terms != []}>
                  Terms: {Enum.join(decision.exclude_terms, ", ")}
                </span>
                <span :if={decision.metadata["research"]}>
                  Research: {decision.metadata["research"]}
                </span>
              </div>
              <div
                :if={decision_snapshot_summary(decision) != []}
                class="flex flex-wrap gap-2 text-xs text-base-content/50"
              >
                <span
                  :for={summary <- decision_snapshot_summary(decision)}
                  class="rounded-full bg-white px-2 py-1 ring-1 ring-zinc-200 dark:bg-white/[0.04] dark:ring-white/10"
                >
                  {summary}
                </span>
              </div>
            </div>
            <p class="text-xs text-base-content/40">
              {review_actor_name(decision)}
            </p>
          </div>
        </div>
      </div>
    </.section>
    """
  end

  defp format_review_decision(decision) do
    decision
    |> to_string()
    |> String.replace("_", " ")
    |> String.capitalize()
  end

  defp decision_tag_color(:accepted), do: :emerald
  defp decision_tag_color(:promoted), do: :sky
  defp decision_tag_color(:started_review), do: :zinc
  defp decision_tag_color(:reopened), do: :sky
  defp decision_tag_color(:parked), do: :amber
  defp decision_tag_color(:suppressed), do: :amber
  defp decision_tag_color(:rejected), do: :rose
  defp decision_tag_color(_decision), do: :zinc

  defp review_actor_name(%{actor_user: %{full_name: full_name}}) when is_binary(full_name),
    do: full_name

  defp review_actor_name(%{actor_user: %{email: email}}), do: to_string(email)

  defp review_actor_name(%{actor_user_id: actor_user_id}) when is_binary(actor_user_id),
    do: "Operator"

  defp review_actor_name(_decision), do: "System"

  defp decision_snapshot_summary(%{metadata: %{"decision_snapshot" => snapshot}})
       when is_map(snapshot) do
    finding = Map.get(snapshot, "finding", %{})
    readiness = Map.get(snapshot, "readiness", %{})
    material = Map.get(snapshot, "material", %{})

    [
      snapshot_label("State", Map.get(finding, "status")),
      snapshot_label("Fit", Map.get(finding, "fit_score")),
      snapshot_label("Intent", Map.get(finding, "intent_score")),
      snapshot_label("Docs", Map.get(material, "document_count")),
      snapshot_label("Packet Docs", Map.get(material, "promotion_document_count")),
      snapshot_label("Evidence", Map.get(material, "discovery_evidence_count")),
      readiness_label("Accept Ready", Map.get(readiness, "acceptance_ready")),
      readiness_label("Promote Ready", Map.get(readiness, "promotion_ready"))
    ]
    |> Enum.reject(&is_nil/1)
  end

  defp decision_snapshot_summary(_decision), do: []

  defp snapshot_label(_label, nil), do: nil
  defp snapshot_label(_label, 0), do: nil
  defp snapshot_label(label, value), do: "#{label}: #{format_value(value)}"

  defp readiness_label(_label, nil), do: nil
  defp readiness_label(label, true), do: "#{label}: Yes"
  defp readiness_label(label, false), do: "#{label}: No"

  defp format_value(nil), do: "-"

  defp format_value(value) do
    value
    |> to_string()
    |> String.replace("_", " ")
    |> String.capitalize()
  end
end
