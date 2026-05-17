defmodule GnomeGardenWeb.Components.AcquisitionOperatorBrief do
  @moduledoc """
  Top-of-page operator brief for acquisition finding detail.
  """

  use Phoenix.Component

  import GnomeGardenWeb.Commercial.Helpers, only: [format_datetime: 1]
  import GnomeGardenWeb.Components.WorkspaceUI, only: [section: 1]

  attr :finding, :map, required: true
  attr :finding_documents, :list, default: []

  def operator_brief(assigns) do
    assigns =
      assign(assigns, :brief, build_operator_brief(assigns.finding, assigns.finding_documents))

    ~H"""
    <.section
      title="Operator Brief"
      description="Fast read before you decide what to do with this finding."
      body_class="p-0"
    >
      <div class="grid gap-0 divide-y divide-base-content/10 lg:grid-cols-6 lg:divide-x lg:divide-y-0">
        <div class={["p-4", operator_brief_tone_class(@brief.tone)]}>
          <p class="text-xs font-semibold uppercase tracking-[0.18em] opacity-70">
            {@brief.action_label}
          </p>
          <p class="mt-2 text-lg font-semibold leading-6">{@brief.action}</p>
          <p class="mt-4 text-xs font-semibold uppercase tracking-[0.18em] opacity-70">
            {@brief.reason_label}
          </p>
          <p class="mt-2 text-sm leading-6 opacity-80">{@brief.reason}</p>
        </div>

        <div class="p-4">
          <p class="text-xs font-semibold uppercase tracking-[0.18em] text-base-content/40">
            Context
          </p>
          <p class="mt-2 text-base font-semibold text-base-content">{@brief.context}</p>
          <p class="mt-2 text-sm leading-6 text-base-content/65">{@brief.context_note}</p>
        </div>

        <div class="p-4">
          <p class="text-xs font-semibold uppercase tracking-[0.18em] text-base-content/40">
            Deadline
          </p>
          <p class="mt-2 text-base font-semibold text-base-content">{@brief.deadline}</p>
          <p class="mt-2 text-sm leading-6 text-base-content/65">{@brief.deadline_note}</p>
        </div>

        <div class="p-4">
          <p class="text-xs font-semibold uppercase tracking-[0.18em] text-base-content/40">
            Readiness
          </p>
          <p class="mt-2 text-base font-semibold text-base-content">{@brief.readiness}</p>
          <p class="mt-2 text-sm leading-6 text-base-content/65">{@brief.readiness_note}</p>
        </div>

        <div class="p-4">
          <p class="text-xs font-semibold uppercase tracking-[0.18em] text-base-content/40">
            Packet
          </p>
          <p class="mt-2 text-base font-semibold text-base-content">{@brief.packet}</p>
          <p class="mt-2 text-sm leading-6 text-base-content/65">{@brief.packet_note}</p>
        </div>

        <div class="p-4">
          <p class="text-xs font-semibold uppercase tracking-[0.18em] text-base-content/40">
            Analysis
          </p>
          <p class="mt-2 text-base font-semibold text-base-content">{@brief.analysis}</p>
          <p class="mt-2 text-sm leading-6 text-base-content/65">{@brief.analysis_note}</p>
        </div>
      </div>
    </.section>
    """
  end

  defp build_operator_brief(finding, finding_documents) do
    finding
    |> build_operator_brief()
    |> Map.merge(context_brief(finding))
    |> Map.merge(document_analysis_brief(finding_documents))
  end

  defp build_operator_brief(%{status: status} = finding)
       when status in [:rejected, :suppressed, :parked, :promoted] do
    %{
      action_label: "Disposition",
      action: finding.status_label,
      reason_label: disposition_reason_label(status),
      reason: disposition_reason(finding),
      tone: disposition_tone(status),
      deadline: deadline_label(finding),
      deadline_note: deadline_note(finding),
      readiness: terminal_readiness_label(status),
      readiness_note: terminal_readiness_note(status),
      packet: packet_label(finding),
      packet_note: packet_note(finding)
    }
  end

  defp build_operator_brief(%{finding_family: :procurement} = finding) do
    cond do
      expired?(finding) ->
        %{
          action_label: "Recommended action",
          action: "Reject as expired",
          reason_label: "Why",
          reason:
            "The opportunity deadline has passed. Keep the source pattern, but do not spend review time promoting this bid.",
          tone: :error,
          deadline: deadline_label(finding),
          deadline_note: deadline_note(finding),
          readiness: readiness_label(finding),
          readiness_note: readiness_note(finding),
          packet: packet_label(finding),
          packet_note: packet_note(finding)
        }

      finding.status == :accepted and finding.promotion_ready ->
        brief(finding, "Promote to signal", "Accepted and promotion-ready.", :success)

      finding.status == :accepted ->
        brief(
          finding,
          "Upload packet",
          "Accepted, but still needs durable procurement proof before promotion.",
          :warning
        )

      finding.acceptance_ready ->
        brief(
          finding,
          "Accept if worth pursuing",
          "The minimum review prep is complete. Decide if this should stay active.",
          :success
        )

      true ->
        brief(
          finding,
          "Complete review prep",
          "Clear the listed blockers before accepting or promoting this finding.",
          :warning
        )
    end
  end

  defp build_operator_brief(finding) do
    cond do
      finding.status == :accepted and finding.promotion_ready ->
        brief(finding, "Promote to signal", "Accepted and promotion-ready.", :success)

      finding.acceptance_ready ->
        brief(
          finding,
          "Accept if worth pursuing",
          "The minimum review prep is complete. Decide if this should stay active.",
          :success
        )

      true ->
        brief(
          finding,
          "Complete review prep",
          "Clear the listed blockers before accepting or promoting this finding.",
          :warning
        )
    end
  end

  defp brief(finding, action, reason, tone) do
    %{
      action_label: "Recommended action",
      action: action,
      reason_label: "Why",
      reason: reason,
      tone: tone,
      deadline: deadline_label(finding),
      deadline_note: deadline_note(finding),
      readiness: readiness_label(finding),
      readiness_note: readiness_note(finding),
      packet: packet_label(finding),
      packet_note: packet_note(finding)
    }
  end

  defp expired?(%{due_at: nil}), do: false

  defp expired?(%{due_at: due_at}) do
    Date.compare(DateTime.to_date(due_at), Date.utc_today()) == :lt
  end

  defp deadline_label(%{due_at: nil}), do: "No deadline captured"
  defp deadline_label(%{due_at: due_at}), do: format_datetime(due_at)

  defp deadline_note(%{due_at: nil}), do: "Use source evidence to decide urgency."

  defp deadline_note(%{due_at: due_at} = finding) do
    due_date = DateTime.to_date(due_at)
    today = Date.utc_today()

    case Date.compare(due_date, today) do
      :lt -> "Deadline passed #{abs(Date.diff(due_date, today))} days ago."
      :eq -> "Deadline is today."
      :gt -> "Deadline is in #{Date.diff(due_date, today)} days."
    end
    |> then(fn note ->
      if finding.finding_family == :procurement, do: note, else: "Observed date: #{note}"
    end)
  end

  defp readiness_label(%{promotion_ready: true}), do: "Ready to promote"
  defp readiness_label(%{acceptance_ready: true}), do: "Ready to accept"
  defp readiness_label(_finding), do: "Prep needed"

  defp readiness_note(%{promotion_ready: true}), do: "All promotion gates are clear."

  defp readiness_note(%{
         acceptance_ready: true,
         promotion_ready: false,
         promotion_blockers: blockers
       })
       when is_list(blockers) and blockers != [] do
    Enum.join(blockers, " ")
  end

  defp readiness_note(%{acceptance_blockers: blockers})
       when is_list(blockers) and blockers != [] do
    Enum.join(blockers, " ")
  end

  defp readiness_note(_finding), do: "No blockers currently listed."

  defp packet_label(%{finding_family: :procurement, document_count: count})
       when is_integer(count) and count > 0,
       do: "#{count} linked"

  defp packet_label(%{finding_family: :procurement, metadata: metadata}) do
    case metadata_value(metadata, "packet") |> metadata_value("status") do
      "present" -> "Capture queued"
      "login_required" -> "Login required"
      "download_failed" -> "Download failed"
      "missing" -> "Missing"
      _ -> "No packet yet"
    end
  end

  defp packet_label(_finding), do: "Not required"

  defp packet_note(%{finding_family: :procurement, document_count: count})
       when is_integer(count) and count > 0,
       do: "Linked documents are available below for review."

  defp packet_note(%{finding_family: :procurement, metadata: metadata}) do
    case metadata_value(metadata, "packet") |> metadata_value("status") do
      "present" ->
        "Document links were captured and ingestion is pending or in progress."

      "login_required" ->
        "The source exposed protected documents. Restart with portal credentials loaded, then rescan."

      "download_failed" ->
        "The source exposed documents, but at least one download failed. Check source access or URL expiry."

      "missing" ->
        "No source packet was captured from this finding yet."

      _ ->
        "No source packet status has been recorded yet."
    end
  end

  defp packet_note(_finding),
    do: "Discovery findings can use evidence or uploaded source material."

  defp context_brief(finding) do
    %{
      context: source_context_label(finding),
      context_note: source_context_note(finding)
    }
  end

  defp source_context_label(%{source: %{name: name}}) when is_binary(name), do: name
  defp source_context_label(%{program: %{name: name}}) when is_binary(name), do: name
  defp source_context_label(%{source_bid: %{agency: agency}}) when is_binary(agency), do: agency
  defp source_context_label(_finding), do: "Direct intake"

  defp source_context_note(finding) do
    [
      prefixed_context("Agency", agency_context(finding)),
      prefixed_context("Location", location_context(finding))
    ]
    |> Enum.reject(&is_nil/1)
    |> case do
      [] -> "No agency or location captured yet."
      parts -> Enum.join(parts, " ")
    end
  end

  defp agency_context(%{source_bid: %{agency: agency}}) when is_binary(agency) and agency != "",
    do: agency

  defp agency_context(%{organization: %{name: name}}) when is_binary(name) and name != "",
    do: name

  defp agency_context(_finding), do: nil

  defp location_context(%{location: location}) when is_binary(location) and location != "",
    do: location

  defp location_context(%{source_bid: %{location: location}})
       when is_binary(location) and location != "",
       do: location

  defp location_context(_finding), do: nil

  defp prefixed_context(_label, nil), do: nil
  defp prefixed_context(label, value), do: "#{label}: #{value}."

  defp document_analysis_brief(finding_documents) do
    finding_documents
    |> Enum.map(&document_analysis(Map.get(&1, :document)))
    |> Enum.find(&is_map/1)
    |> case do
      analysis when is_map(analysis) ->
        next_action = metadata_value(analysis, "next_action")
        red_flags = analysis_list(analysis, "red_flags")

        %{
          analysis: analysis_label(next_action, red_flags),
          analysis_note: analysis_note(analysis, next_action, red_flags)
        }

      _other ->
        %{
          analysis: "No analysis yet",
          analysis_note:
            "Upload or fetch source documents to extract scope, dates, and review blockers."
        }
    end
  end

  defp analysis_label(_next_action, red_flags) when is_list(red_flags) and red_flags != [],
    do: "Red flags found"

  defp analysis_label(next_action, _red_flags) when is_binary(next_action) and next_action != "",
    do: "Analyzed"

  defp analysis_label(_next_action, _red_flags), do: "Analyzed"

  defp analysis_note(analysis, next_action, red_flags) do
    [
      metadata_value(analysis, "scope_summary"),
      next_action_text(next_action),
      red_flags_text(red_flags)
    ]
    |> Enum.reject(&(&1 in [nil, ""]))
    |> case do
      [] -> "Document text was analyzed. Review linked document details below."
      parts -> Enum.join(parts, " ")
    end
  end

  defp next_action_text(nil), do: nil
  defp next_action_text(""), do: nil
  defp next_action_text(next_action), do: "Next: #{next_action}"

  defp red_flags_text([]), do: nil
  defp red_flags_text(red_flags), do: "Red flags: #{Enum.join(red_flags, "; ")}"

  defp disposition_reason(%{latest_review_reason: reason})
       when is_binary(reason) and reason != "",
       do: reason

  defp disposition_reason(%{status: :rejected, finding_family: :procurement} = finding) do
    if expired?(finding),
      do: "Deadline passed before review.",
      else: "Rejected by operator review."
  end

  defp disposition_reason(%{status: :promoted}), do: "Already promoted into commercial review."
  defp disposition_reason(%{status: :parked}), do: "Parked for later review."
  defp disposition_reason(%{status: :suppressed}), do: "Suppressed as source or profile noise."
  defp disposition_reason(%{status: :rejected}), do: "Rejected by operator review."
  defp disposition_reason(_finding), do: "Disposition recorded."

  defp disposition_tone(:promoted), do: :success
  defp disposition_tone(:parked), do: :info
  defp disposition_tone(:suppressed), do: :warning
  defp disposition_tone(:rejected), do: :error
  defp disposition_tone(_status), do: :default

  defp disposition_reason_label(:rejected), do: "Rejection reason"
  defp disposition_reason_label(:suppressed), do: "Suppression reason"
  defp disposition_reason_label(:parked), do: "Parking reason"
  defp disposition_reason_label(:promoted), do: "Promotion note"
  defp disposition_reason_label(_status), do: "Reason"

  defp terminal_readiness_label(:promoted), do: "Commercial review"
  defp terminal_readiness_label(:parked), do: "Parked"
  defp terminal_readiness_label(:suppressed), do: "Suppressed"
  defp terminal_readiness_label(:rejected), do: "Closed"
  defp terminal_readiness_label(_status), do: "Disposition recorded"

  defp terminal_readiness_note(:promoted), do: "Already handed into commercial review."
  defp terminal_readiness_note(:parked), do: "Reopen when timing or evidence changes."

  defp terminal_readiness_note(:suppressed),
    do: "Stays out of active review and can teach source or profile noise."

  defp terminal_readiness_note(:rejected), do: "No further action unless you reopen it."
  defp terminal_readiness_note(_status), do: "No active review action pending."

  defp document_analysis(%{file: %{blob: %{metadata: metadata}}}) when is_map(metadata) do
    case metadata_value(metadata, "document_analysis") do
      analysis when is_map(analysis) -> analysis
      _other -> nil
    end
  end

  defp document_analysis(_document), do: nil

  defp analysis_list(analysis, key) when is_map(analysis) do
    analysis
    |> metadata_value(key)
    |> List.wrap()
    |> Enum.reject(&(&1 in [nil, ""]))
  end

  defp metadata_value(nil, _key), do: nil

  defp metadata_value(map, key) when is_map(map) do
    Map.get(map, key) || Map.get(map, to_string(key))
  end

  defp metadata_value(_value, _key), do: nil

  defp operator_brief_tone_class(:success),
    do: "bg-emerald-50 text-emerald-900 dark:bg-emerald-400/10 dark:text-emerald-100"

  defp operator_brief_tone_class(:warning),
    do: "bg-amber-50 text-amber-900 dark:bg-amber-400/10 dark:text-amber-100"

  defp operator_brief_tone_class(:error),
    do: "bg-rose-50 text-rose-900 dark:bg-rose-400/10 dark:text-rose-100"

  defp operator_brief_tone_class(:info),
    do: "bg-sky-50 text-sky-900 dark:bg-sky-400/10 dark:text-sky-100"

  defp operator_brief_tone_class(_tone),
    do: "bg-base-200/70 text-base-content"
end
