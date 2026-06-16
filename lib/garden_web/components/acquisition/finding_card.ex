defmodule GnomeGardenWeb.Components.Acquisition.FindingCard do
  @moduledoc """
  Queue card component for acquisition findings.
  """

  use GnomeGardenWeb, :html

  import GnomeGardenWeb.Commercial.Helpers, only: [format_date: 1, format_datetime: 1]
  import GnomeGardenWeb.Components.AcquisitionUI, only: [finding_action_bar: 1]

  attr :finding, :map, required: true

  def finding_card(assigns) do
    ~H"""
    <article
      id={"finding-card-#{@finding.id}"}
      class="grid gap-3 px-3 py-3 transition hover:bg-zinc-50/80 dark:hover:bg-white/[0.025] sm:px-4 lg:grid-cols-[minmax(0,1fr)_16rem]"
    >
      <div class="min-w-0 space-y-3">
        <div class="flex flex-col gap-3 sm:flex-row sm:items-start sm:justify-between">
          <div class="min-w-0 space-y-2">
            <div class="flex flex-wrap gap-2">
              <.status_badge status={@finding.finding_family_variant}>
                {@finding.finding_family_label}
              </.status_badge>
              <span class="badge badge-outline badge-sm">
                {@finding.finding_type_label}
              </span>
              <.status_badge :if={@finding.confidence} status={@finding.confidence_variant}>
                {@finding.confidence_label}
              </.status_badge>
              <.status_badge :if={stale_finding?(@finding)} status={:error}>
                Stale
              </.status_badge>
              <.status_badge :if={due_soon_finding?(@finding)} status={:warning}>
                Due soon
              </.status_badge>
            </div>

            <div>
              <.link
                navigate={~p"/acquisition/findings/#{@finding.id}"}
                class="text-base font-semibold leading-6 text-base-content hover:text-emerald-700 dark:hover:text-emerald-300"
              >
                {@finding.title}
              </.link>
              <p class="mt-1 max-w-4xl text-sm leading-6 text-base-content/65">
                {@finding.display_summary}
              </p>
            </div>
          </div>

          <div class="grid gap-2 sm:w-48 sm:shrink-0">
            <.finding_metric label="Score" value={finding_score_value(@finding)} />
            <.finding_metric label="Due" value={finding_due_label(@finding)} />
            <.finding_metric
              :if={@finding.finding_family == :procurement}
              label="Packet"
              value={finding_packet_label(@finding)}
            />
          </div>
        </div>

        <div class="grid gap-2 text-sm sm:grid-cols-2 xl:grid-cols-4">
          <.finding_fact
            icon="hero-map-pin"
            label="Location"
            value={@finding.location || "No location"}
          />
          <.finding_fact
            icon="hero-wrench-screwdriver"
            label="Work"
            value={@finding.work_summary || type_label(@finding.finding_type)}
          />
          <.finding_fact
            icon="hero-arrow-trending-up"
            label="Lane"
            value={source_or_program_label(@finding)}
          />
          <.finding_fact
            icon="hero-clock"
            label="Observed"
            value={format_datetime(@finding.observed_at || @finding.inserted_at)}
          />
        </div>

        <div class="flex flex-col gap-2 rounded-md border border-base-content/10 bg-base-200/60 px-3 py-2 text-sm sm:flex-row sm:items-center sm:justify-between">
          <div class="min-w-0">
            <p class="text-[11px] font-semibold uppercase tracking-[0.14em] text-base-content/45">
              Provenance
            </p>
            <p class="mt-1 truncate font-medium text-base-content">
              {source_or_program_label(@finding)}
            </p>
            <p class="mt-0.5 truncate text-xs text-base-content/55">
              {run_provenance_label(@finding)}
            </p>
          </div>
          <.link
            :if={@finding.agent_run_id}
            navigate={~p"/console/agents/runs/#{@finding.agent_run_id}"}
            class="btn btn-xs btn-ghost shrink-0"
          >
            Open Run
          </.link>
        </div>

        <div class="grid gap-2 text-xs leading-5 text-base-content/55 md:grid-cols-2">
          <p :if={@finding.score_note}>
            <span class="font-semibold text-base-content/70">Score:</span> {@finding.score_note}
          </p>
          <p :if={@finding.work_note}>
            <span class="font-semibold text-base-content/70">Work:</span> {@finding.work_note}
          </p>
          <p :if={@finding.due_status_label}>
            <span class="font-semibold text-base-content/70">Due:</span> {@finding.due_status_label}
          </p>
          <p :if={organization_name(@finding)}>
            <span class="font-semibold text-base-content/70">Org:</span> {organization_name(@finding)}
          </p>
        </div>

        <div
          :if={@finding.latest_review_reason || @finding.latest_review_decision_at}
          class="rounded-md border border-zinc-200 bg-zinc-50/70 px-3 py-2 text-xs leading-5 text-base-content/60 dark:border-white/10 dark:bg-white/[0.03]"
        >
          <p :if={@finding.latest_review_reason}>
            {@finding.latest_review_reason}
          </p>
          <p
            :if={@finding.latest_review_decision_at}
            class="mt-1 uppercase tracking-[0.12em] text-base-content/40"
          >
            {status_label(@finding.latest_review_decision || @finding.status)} · {format_datetime(
              @finding.latest_review_decision_at
            )}
          </p>
          <div
            :if={@finding.latest_review_reason_code || @finding.latest_review_feedback_scope}
            class="mt-2 flex flex-wrap gap-1.5"
          >
            <span :if={@finding.latest_review_reason_code} class="badge badge-outline badge-xs">
              {status_label(@finding.latest_review_reason_code)}
            </span>
            <span :if={@finding.latest_review_feedback_scope} class="badge badge-ghost badge-xs">
              Scope: {status_label(@finding.latest_review_feedback_scope)}
            </span>
          </div>
        </div>
      </div>

      <div class="flex flex-col gap-3 border-t border-zinc-200 pt-3 dark:border-white/10 lg:border-l lg:border-t-0 lg:pl-4 lg:pt-0">
        <div class="space-y-1">
          <p class="text-[10px] font-semibold uppercase tracking-[0.14em] text-base-content/40">
            Status
          </p>
          <.status_badge status={@finding.status_variant}>
            {@finding.status_label}
          </.status_badge>
          <p
            :if={@finding.latest_review_reason}
            class="pt-1 text-xs leading-5 text-base-content/60"
          >
            {@finding.latest_review_reason}
          </p>
          <div
            :if={@finding.latest_review_reason_code || stale_finding?(@finding)}
            class="flex flex-wrap gap-1 pt-1"
          >
            <span :if={stale_finding?(@finding)} class="badge badge-error badge-xs">
              Stale
            </span>
            <span :if={@finding.latest_review_reason_code} class="badge badge-outline badge-xs">
              {status_label(@finding.latest_review_reason_code)}
            </span>
          </div>
        </div>

        <div class="flex flex-wrap gap-1.5">
          <.button
            navigate={~p"/acquisition/findings/#{@finding.id}"}
            class="px-2.5 py-1.5 text-xs whitespace-nowrap"
          >
            Open Finding
          </.button>
          <.button
            :if={@finding.signal_id}
            navigate={~p"/commercial/signals/#{@finding.signal_id}"}
            class="px-2.5 py-1.5 text-xs whitespace-nowrap"
          >
            Open Signal
          </.button>
        </div>

        <.finding_action_bar
          finding={@finding}
          id_prefix="finding"
          target_id={@finding.id}
          compact
        />

        <p
          :if={@finding.status == :reviewing and not @finding.acceptance_ready}
          class="text-xs leading-5 text-amber-700 dark:text-amber-200"
        >
          {Enum.join(@finding.acceptance_blockers, " ")}
        </p>
        <p
          :if={@finding.status == :accepted and not @finding.promotion_ready}
          class="text-xs leading-5 text-amber-700 dark:text-amber-200"
        >
          {Enum.join(@finding.promotion_blockers, " ")}
        </p>
      </div>
    </article>
    """
  end

  attr :label, :string, required: true
  attr :value, :string, required: true

  defp finding_metric(assigns) do
    ~H"""
    <div class="rounded-md border border-base-content/10 bg-base-200/70 px-3 py-2">
      <p class="text-[11px] font-semibold uppercase tracking-[0.14em] text-base-content/45">
        {@label}
      </p>
      <p class="mt-1 text-sm font-semibold leading-5 text-base-content">{@value}</p>
    </div>
    """
  end

  attr :icon, :string, required: true
  attr :label, :string, required: true
  attr :value, :string, required: true

  defp finding_fact(assigns) do
    ~H"""
    <div class="flex min-w-0 items-start gap-2 rounded-md border border-base-content/10 bg-base-200/60 px-3 py-2">
      <.icon name={@icon} class="mt-0.5 size-4 shrink-0 text-base-content/45" />
      <div class="min-w-0">
        <p class="text-[11px] font-semibold uppercase tracking-[0.14em] text-base-content/45">
          {@label}
        </p>
        <p class="truncate font-medium text-base-content">{@value}</p>
      </div>
    </div>
    """
  end

  defp source_or_program_label(%{source: %{name: name}}) when is_binary(name), do: name
  defp source_or_program_label(%{program: %{name: name}}) when is_binary(name), do: name
  defp source_or_program_label(_finding), do: "Direct agent intake"

  defp run_provenance_label(%{agent_run: %{state: state}, agent_run_id: run_id})
       when is_atom(state) and is_binary(run_id),
       do: "Run #{String.slice(run_id, 0, 8)} · #{status_label(state)}"

  defp run_provenance_label(%{agent_run_id: run_id}) when is_binary(run_id),
    do: "Run #{String.slice(run_id, 0, 8)}"

  defp run_provenance_label(_finding), do: "No linked agent run"

  defp organization_name(%{organization: %{name: name}}) when is_binary(name), do: name
  defp organization_name(_finding), do: nil

  defp finding_due_label(%{due_at: nil}), do: "No due date"
  defp finding_due_label(%{due_at: due_at}), do: format_date(due_at)

  defp stale_finding?(%{due_at: nil}), do: false

  defp stale_finding?(%{status: status, due_at: due_at})
       when status in [:new, :reviewing, :accepted] do
    Date.compare(DateTime.to_date(due_at), Date.utc_today()) == :lt
  end

  defp stale_finding?(_finding), do: false

  defp due_soon_finding?(%{due_at: nil}), do: false

  defp due_soon_finding?(%{status: status, due_at: due_at})
       when status in [:new, :reviewing, :accepted] do
    days = Date.diff(DateTime.to_date(due_at), Date.utc_today())
    days in 0..7
  end

  defp due_soon_finding?(_finding), do: false

  defp finding_score_value(%{fit_score: score}) when is_integer(score),
    do: Integer.to_string(score)

  defp finding_score_value(_finding), do: "-"

  defp finding_packet_label(%{document_count: count}) when is_integer(count) and count > 0,
    do: "#{count} linked"

  defp finding_packet_label(%{metadata: metadata}) do
    case metadata_value(metadata, "packet") |> metadata_value("status") do
      "present" -> "Capture queued"
      "login_required" -> "Login required"
      "download_failed" -> "Download failed"
      "missing" -> "Missing"
      _ -> "No packet"
    end
  end

  defp finding_packet_label(_finding), do: "No packet"

  defp type_label(type) do
    type
    |> to_string()
    |> String.replace("_", " ")
    |> String.capitalize()
  end

  defp status_label(status) do
    status
    |> to_string()
    |> String.replace("_", " ")
    |> String.capitalize()
  end

  defp metadata_value(metadata, key) when is_map(metadata) do
    Map.get(metadata, key) || Map.get(metadata, String.to_existing_atom(key))
  rescue
    ArgumentError -> Map.get(metadata, key)
  end

  defp metadata_value(_metadata, _key), do: nil
end
