defmodule GnomeGardenWeb.Acquisition.FindingLive.Index do
  use GnomeGardenWeb, :live_view
  use Cinder.UrlSync

  import Cinder.Refresh
  import GnomeGardenWeb.Components.AcquisitionUI, only: [finding_action_bar: 1, review_dialogs: 1]

  import GnomeGardenWeb.Commercial.Helpers, only: [format_date: 1, format_datetime: 1]
  require Ash.Query

  alias GnomeGarden.Acquisition
  alias GnomeGarden.Procurement.TargetingFeedback

  @queues [:review, :promoted, :rejected, :suppressed, :parked]
  @families [:all, :procurement, :discovery]
  @table_id "acquisition-findings-table"

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      GnomeGardenWeb.Endpoint.subscribe("finding:created")
      GnomeGardenWeb.Endpoint.subscribe("finding:updated")
    end

    {:ok,
     socket
     |> assign(:page_title, "Acquisition Queue")
     |> assign(:queues, @queues)
     |> assign(:families, @families)
     |> assign(:selected_queue, :review)
     |> assign(:selected_family, :all)
     |> assign(:selected_source, nil)
     |> assign(:selected_program, nil)
     |> assign(:action_dialog, nil)
     |> assign(:queue_counts, queue_counts())
     |> assign(:findings_query, build_findings_query(:review, :all, nil, nil))}
  end

  @impl true
  def handle_params(params, uri, socket) do
    socket = Cinder.UrlSync.handle_params(params, uri, socket)

    queue = parse_queue(Map.get(params, "queue"))
    family = parse_family(Map.get(params, "family"))
    source = load_source_filter(Map.get(params, "source_id"), socket.assigns.current_user)
    program = load_program_filter(Map.get(params, "program_id"), socket.assigns.current_user)

    {:noreply,
     socket
     |> assign(:selected_queue, queue)
     |> assign(:selected_family, family)
     |> assign(:selected_source, source)
     |> assign(:selected_program, program)
     |> assign(:findings_query, build_findings_query(queue, family, source, program))
     |> assign(
       :queue_counts,
       queue_counts(family, source, program, socket.assigns.current_user)
     )}
  end

  @impl true
  def handle_info(%{topic: "finding:" <> _}, socket) do
    {:noreply, refresh_queue(socket)}
  end

  @impl true
  def handle_event("transition", %{"id" => id, "action" => "start_review"}, socket) do
    case Acquisition.start_review_for_finding(id, actor: socket.assigns.current_user) do
      {:ok, _finding} ->
        {:noreply, socket |> refresh_queue() |> put_flash(:info, "Finding moved into review")}

      {:error, error} ->
        {:noreply, put_flash(socket, :error, "Could not start review: #{format_error(error)}")}
    end
  end

  def handle_event("transition", %{"id" => id, "action" => "promote"}, socket) do
    case Acquisition.promote_finding_to_signal(id, actor: socket.assigns.current_user) do
      {:ok, %{finding: finding}} when not is_nil(finding.signal_id) ->
        {:noreply,
         socket
         |> refresh_queue()
         |> put_flash(:info, "Promoted finding into commercial review")
         |> push_navigate(to: ~p"/commercial/signals/#{finding.signal_id}")}

      {:ok, _result} ->
        {:noreply, socket |> refresh_queue() |> put_flash(:info, "Promoted finding")}

      {:error, error} ->
        {:noreply, put_flash(socket, :error, "Could not promote finding: #{format_error(error)}")}
    end
  end

  def handle_event("submit_accept", params, socket) do
    case Acquisition.accept_finding_review(
           socket.assigns.action_dialog.finding_id,
           params,
           actor: socket.assigns.current_user
         ) do
      {:ok, _finding} ->
        {:noreply,
         socket
         |> assign(:action_dialog, nil)
         |> refresh_queue()
         |> put_flash(:info, "Marked finding as accepted")}

      {:error, error} ->
        {:noreply, put_flash(socket, :error, "Could not accept finding: #{format_error(error)}")}
    end
  end

  def handle_event("open_dialog", %{"id" => id, "action" => action}, socket) do
    case parse_dialog_action(action) do
      nil ->
        {:noreply, put_flash(socket, :error, "Unknown acquisition action")}

      dialog_action ->
        case Acquisition.get_finding(
               id,
               actor: socket.assigns.current_user,
               load: [:source_bid, :source_discovery_record]
             ) do
          {:ok, finding} ->
            {:noreply,
             assign(
               socket,
               :action_dialog,
               build_action_dialog(finding, dialog_action)
             )}

          {:error, error} ->
            {:noreply, put_flash(socket, :error, "Could not load finding: #{inspect(error)}")}
        end
    end
  end

  def handle_event("close_dialog", _, socket) do
    {:noreply, assign(socket, :action_dialog, nil)}
  end

  def handle_event("submit_reject", params, socket) do
    case Acquisition.reject_finding_review(
           socket.assigns.action_dialog.finding_id,
           params,
           actor: socket.assigns.current_user
         ) do
      {:ok, _finding} ->
        {:noreply,
         socket
         |> assign(:action_dialog, nil)
         |> refresh_queue()
         |> put_flash(:info, "Rejected finding")}

      {:error, error} ->
        {:noreply, put_flash(socket, :error, "Could not reject finding: #{inspect(error)}")}
    end
  end

  def handle_event("submit_suppress", params, socket) do
    case Acquisition.suppress_finding_review(
           socket.assigns.action_dialog.finding_id,
           params,
           actor: socket.assigns.current_user
         ) do
      {:ok, _finding} ->
        {:noreply,
         socket
         |> assign(:action_dialog, nil)
         |> refresh_queue()
         |> put_flash(:info, "Suppressed finding")}

      {:error, error} ->
        {:noreply, put_flash(socket, :error, "Could not suppress finding: #{inspect(error)}")}
    end
  end

  def handle_event("submit_park", params, socket) do
    case Acquisition.park_finding_review(
           socket.assigns.action_dialog.finding_id,
           params,
           actor: socket.assigns.current_user
         ) do
      {:ok, _finding} ->
        {:noreply,
         socket
         |> assign(:action_dialog, nil)
         |> refresh_queue()
         |> put_flash(:info, "Parked finding")}

      {:error, error} ->
        {:noreply, put_flash(socket, :error, "Could not park finding: #{inspect(error)}")}
    end
  end

  def handle_event("transition", %{"id" => id, "action" => "reopen"}, socket) do
    case Acquisition.reopen_finding_review(id, actor: socket.assigns.current_user) do
      {:ok, _finding} ->
        {:noreply, socket |> refresh_queue() |> put_flash(:info, "Reopened finding")}

      {:error, error} ->
        {:noreply, put_flash(socket, :error, "Could not reopen finding: #{inspect(error)}")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.page class="pb-4">
      <.page_header eyebrow="Acquisition">
        Acquisition Queue
        <:subtitle>
          Unified operator intake across procurement and discovery. Findings live here first, then move into commercial review only when intentionally advanced.
        </:subtitle>
        <:actions>
          <.button navigate={~p"/acquisition/sources"}>
            Sources
          </.button>
          <.button navigate={~p"/acquisition/programs"}>
            Programs
          </.button>
          <.button navigate={~p"/commercial/signals"}>
            Signal Queue
          </.button>
        </:actions>
      </.page_header>

      <div class="grid gap-2 sm:grid-cols-3">
        <.stat_card
          title="Review Queue"
          value={Integer.to_string(@queue_counts.review)}
          description="New or actively reviewed findings waiting on an operator decision."
          icon="hero-inbox-stack"
        />
        <.stat_card
          title="Promoted"
          value={Integer.to_string(@queue_counts.promoted)}
          description="Findings already advanced into formal commercial review."
          icon="hero-arrow-up-right"
          accent="sky"
        />
        <.stat_card
          title="Suppressed Noise"
          value={Integer.to_string(@queue_counts.suppressed + @queue_counts.rejected)}
          description="Low-value or out-of-scope intake that should not clog the queue."
          icon="hero-no-symbol"
          accent="amber"
        />
      </div>

      <.section
        title="Unified Intake"
        description="Run procurement, discovery, and future target-finding through one queue before it becomes commercial work."
        compact
        body_class="p-0"
      >
        <div class="border-b border-zinc-200 px-5 py-4 dark:border-white/10">
          <div class="flex flex-wrap items-center gap-2">
            <.queue_link
              :for={queue <- @queues}
              queue={queue}
              selected_queue={@selected_queue}
              selected_family={@selected_family}
              selected_source={@selected_source}
              selected_program={@selected_program}
              count={Map.fetch!(@queue_counts, queue)}
            />
          </div>
          <div class="mt-3 flex flex-wrap items-center gap-2">
            <span class="text-xs font-semibold uppercase tracking-[0.18em] text-base-content/40">
              Family
            </span>
            <.family_link
              :for={family <- @families}
              family={family}
              selected_family={@selected_family}
              selected_queue={@selected_queue}
              selected_source={@selected_source}
              selected_program={@selected_program}
            />
          </div>
          <div
            :if={@selected_source || @selected_program}
            class="mt-3 flex flex-wrap items-center gap-2"
          >
            <span
              :if={@selected_source}
              class="inline-flex items-center gap-2 rounded-full border border-amber-200 bg-amber-50 px-3 py-1.5 text-sm font-medium text-amber-700 dark:border-amber-400/30 dark:bg-amber-400/10 dark:text-amber-200"
            >
              {@selected_source.name}
            </span>
            <span
              :if={@selected_program}
              class="inline-flex items-center gap-2 rounded-full border border-sky-200 bg-sky-50 px-3 py-1.5 text-sm font-medium text-sky-700 dark:border-sky-400/30 dark:bg-sky-400/10 dark:text-sky-200"
            >
              {@selected_program.name}
            </span>
            <.link
              patch={queue_path(@selected_queue, @selected_family, nil, nil)}
              class="btn btn-xs btn-ghost"
            >
              Clear Filter
            </.link>
          </div>
          <div :if={@selected_source || @selected_program} class="mt-3 grid gap-2 lg:grid-cols-2">
            <div
              :if={@selected_source}
              class="rounded-xl border border-zinc-200 bg-zinc-50/70 px-3 py-3 dark:border-white/10 dark:bg-white/[0.03]"
            >
              <div class="flex flex-wrap items-start justify-between gap-3">
                <div class="space-y-1">
                  <p class="text-xs font-semibold uppercase tracking-[0.18em] text-base-content/40">
                    Source Context
                  </p>
                  <p class="text-sm font-medium text-base-content">
                    {@selected_source.name}
                  </p>
                  <p class="text-xs text-base-content/50">
                    {@selected_source.review_finding_count} review · {@selected_source.promoted_finding_count} promoted · {@selected_source.noise_finding_count} noise
                  </p>
                </div>
                <div class="space-y-2 text-right">
                  <.status_badge status={@selected_source.status_variant}>
                    {status_label(@selected_source.status)}
                  </.status_badge>
                  <.status_badge status={@selected_source.health_variant}>
                    {status_label(@selected_source.health_status)}
                  </.status_badge>
                </div>
              </div>
              <p class="mt-3 text-xs text-base-content/50">
                {@selected_source.health_note}
              </p>
              <div class="mt-3 flex flex-wrap gap-2">
                <.link navigate={~p"/acquisition/sources"} class="btn btn-xs btn-ghost">
                  Source Registry
                </.link>
                <.link
                  :if={@selected_source.latest_run_id}
                  navigate={~p"/console/agents/runs/#{@selected_source.latest_run_id}"}
                  class="btn btn-xs btn-ghost"
                >
                  Open Run
                </.link>
              </div>
            </div>

            <div
              :if={@selected_program}
              class="rounded-xl border border-zinc-200 bg-zinc-50/70 px-3 py-3 dark:border-white/10 dark:bg-white/[0.03]"
            >
              <div class="flex flex-wrap items-start justify-between gap-3">
                <div class="space-y-1">
                  <p class="text-xs font-semibold uppercase tracking-[0.18em] text-base-content/40">
                    Program Context
                  </p>
                  <p class="text-sm font-medium text-base-content">
                    {@selected_program.name}
                  </p>
                  <p class="text-xs text-base-content/50">
                    {@selected_program.review_finding_count} review · {@selected_program.promoted_finding_count} promoted · {@selected_program.noise_finding_count} noise
                  </p>
                </div>
                <div class="space-y-2 text-right">
                  <.status_badge status={@selected_program.status_variant}>
                    {status_label(@selected_program.status)}
                  </.status_badge>
                  <.status_badge status={@selected_program.health_variant}>
                    {status_label(@selected_program.health_status)}
                  </.status_badge>
                </div>
              </div>
              <p class="mt-3 text-xs text-base-content/50">
                {@selected_program.health_note}
              </p>
              <div class="mt-3 flex flex-wrap gap-2">
                <.link navigate={~p"/acquisition/programs"} class="btn btn-xs btn-ghost">
                  Program Registry
                </.link>
                <.link
                  :if={@selected_program.latest_run_id}
                  navigate={~p"/console/agents/runs/#{@selected_program.latest_run_id}"}
                  class="btn btn-xs btn-ghost"
                >
                  Open Run
                </.link>
              </div>
            </div>
          </div>
        </div>

        <Cinder.collection
          id="acquisition-findings-table"
          query={@findings_query}
          actor={@current_user}
          url_state={@url_state}
          theme={GnomeGardenWeb.CinderTheme}
          page_size={25}
        >
          <:col :let={finding} field="title" search sort label="Finding">
            <div class="space-y-1">
              <p class="font-medium text-base-content">{finding.title}</p>
              <p class="max-w-xl text-xs leading-5 text-base-content/50">
                {finding.summary || "No summary yet."}
              </p>
              <div class="flex flex-wrap gap-2">
                <span class={family_badge(finding.finding_family)}>
                  {family_label(finding.finding_family)}
                </span>
                <span class="badge badge-outline badge-sm">
                  {type_label(finding.finding_type)}
                </span>
                <span :if={finding.confidence} class={confidence_badge(finding.confidence)}>
                  {confidence_label(finding.confidence)}
                </span>
              </div>
            </div>
          </:col>
          <:col :let={finding} field="due_at" sort label="Due">
            <div class="space-y-1">
              <p class="font-medium text-base-content">
                {finding_due_label(finding)}
              </p>
              <p :if={finding.due_status_label} class="text-xs text-base-content/50">
                {finding.due_status_label}
              </p>
            </div>
          </:col>
          <:col :let={finding} field="fit_score" sort label="Score">
            <div class="space-y-1">
              <p class="font-semibold text-base-content">
                {finding_score_value(finding)}
              </p>
              <p :if={finding.score_note} class="text-xs text-base-content/50">
                {finding.score_note}
              </p>
              <.status_badge :if={finding.score_tier} status={finding.score_tier_variant}>
                {status_label(finding.score_tier)}
              </.status_badge>
            </div>
          </:col>
          <:col :let={finding} field="location" search label="City / State">
            <div class="space-y-1">
              <p class="font-medium text-base-content">
                {finding.location || "No location"}
              </p>
              <p :if={finding.location_note} class="text-xs text-base-content/50">
                {finding.location_note}
              </p>
            </div>
          </:col>
          <:col :let={finding} field="work_summary" search label="Work">
            <div class="space-y-1">
              <p class="font-medium text-base-content">
                {finding.work_summary || type_label(finding.finding_type)}
              </p>
              <p :if={finding.work_type} class="text-xs text-base-content/50">
                {finding.work_type}
              </p>
              <p
                :if={finding.work_note}
                class="max-w-[14rem] text-xs text-base-content/50"
              >
                {finding.work_note}
              </p>
            </div>
          </:col>
          <:col :let={finding} label="Lane">
            <div class="space-y-1">
              <p>{source_or_program_label(finding)}</p>
              <p :if={finding.organization} class="text-xs text-base-content/50">
                {finding.organization.name}
              </p>
            </div>
          </:col>
          <:col :let={finding} field="observed_at" sort label="Observed">
            {format_datetime(finding.observed_at || finding.inserted_at)}
          </:col>
          <:col :let={finding} label="Status">
            <div class="space-y-1">
              <.status_badge status={finding.status_variant}>
                {status_label(finding.status)}
              </.status_badge>
              <p
                :if={finding.latest_review_reason}
                class="max-w-xs text-xs leading-5 text-base-content/50"
              >
                {finding.latest_review_reason}
              </p>
              <p
                :if={finding.latest_review_decision_at}
                class="text-[11px] uppercase tracking-[0.12em] text-base-content/40"
              >
                {status_label(finding.latest_review_decision || finding.status)} · {format_datetime(
                  finding.latest_review_decision_at
                )}
              </p>
              <div
                :if={finding.latest_review_reason_code || finding.latest_review_feedback_scope}
                class="flex flex-wrap gap-1.5"
              >
                <span
                  :if={finding.latest_review_reason_code}
                  class="badge badge-outline badge-xs"
                >
                  {status_label(finding.latest_review_reason_code)}
                </span>
                <span
                  :if={finding.latest_review_feedback_scope}
                  class="badge badge-ghost badge-xs"
                >
                  Scope: {status_label(finding.latest_review_feedback_scope)}
                </span>
              </div>
            </div>
          </:col>
          <:col :let={finding} label="Open">
            <div class="flex flex-col items-start gap-1.5">
              <.button
                navigate={~p"/acquisition/findings/#{finding.id}"}
                class="px-2.5 py-1.5 text-xs whitespace-nowrap"
              >
                Open Finding
              </.button>
              <.button
                :if={finding.signal_id}
                navigate={~p"/commercial/signals/#{finding.signal_id}"}
                class="px-2.5 py-1.5 text-xs whitespace-nowrap"
              >
                Open Signal
              </.button>
            </div>
          </:col>
          <:col :let={finding} label="Actions">
            <.finding_action_bar
              finding={finding}
              id_prefix="finding"
              target_id={finding.id}
              compact
            />
            <p
              :if={finding.status == :reviewing and not finding.acceptance_ready}
              class="mt-2 max-w-xs text-xs leading-5 text-amber-700 dark:text-amber-200"
            >
              {Enum.join(finding.acceptance_blockers, " ")}
            </p>
            <p
              :if={finding.status == :accepted and not finding.promotion_ready}
              class="mt-2 max-w-xs text-xs leading-5 text-amber-700 dark:text-amber-200"
            >
              {Enum.join(finding.promotion_blockers, " ")}
            </p>
          </:col>

          <:empty>
            <.empty_state
              icon="hero-inbox-stack"
              title={"No #{queue_label(@selected_queue)} findings"}
              description={empty_description(@selected_queue)}
            />
          </:empty>
        </Cinder.collection>
      </.section>

      <.review_dialogs action_dialog={@action_dialog} id_prefix="finding" />
    </.page>
    """
  end

  defp refresh_queue(socket) do
    socket
    |> assign(
      :queue_counts,
      queue_counts(
        socket.assigns.selected_family,
        socket.assigns.selected_source,
        socket.assigns.selected_program,
        socket.assigns.current_user
      )
    )
    |> assign(
      :findings_query,
      build_findings_query(
        socket.assigns.selected_queue,
        socket.assigns.selected_family,
        socket.assigns.selected_source,
        socket.assigns.selected_program
      )
    )
    |> refresh_table(@table_id)
  end

  defp build_findings_query(queue, family, source, program) do
    GnomeGarden.Acquisition.Finding
    |> Ash.Query.for_read(queue_action(queue))
    |> apply_finding_filters(family, source, program)
  end

  defp queue_action(:review), do: :review_queue
  defp queue_action(:promoted), do: :promoted
  defp queue_action(:rejected), do: :rejected
  defp queue_action(:suppressed), do: :suppressed
  defp queue_action(:parked), do: :parked

  defp apply_finding_filters(query, family, source, program) do
    query
    |> maybe_filter_family(family)
    |> maybe_filter_source(source)
    |> maybe_filter_program(program)
  end

  defp maybe_filter_family(query, :all), do: query

  defp maybe_filter_family(query, family),
    do: Ash.Query.filter(query, finding_family == ^family)

  defp maybe_filter_source(query, nil), do: query

  defp maybe_filter_source(query, %{id: id}),
    do: Ash.Query.filter(query, source_id == ^id)

  defp maybe_filter_program(query, nil), do: query

  defp maybe_filter_program(query, %{id: id}),
    do: Ash.Query.filter(query, program_id == ^id)

  defp count_findings(queue, family, source, program, actor) do
    case Ash.count(build_findings_query(queue, family, source, program), actor: actor) do
      {:ok, count} -> count
      {:error, _error} -> 0
    end
  end

  defp queue_counts(family \\ :all, source \\ nil, program \\ nil, actor \\ nil) do
    %{
      review: count_findings(:review, family, source, program, actor),
      promoted: count_findings(:promoted, family, source, program, actor),
      rejected: count_findings(:rejected, family, source, program, actor),
      suppressed: count_findings(:suppressed, family, source, program, actor),
      parked: count_findings(:parked, family, source, program, actor)
    }
  end

  defp parse_queue(nil), do: :review

  defp parse_queue(queue) when is_binary(queue) do
    queue
    |> String.to_existing_atom()
  rescue
    ArgumentError -> :review
  end

  defp parse_family(nil), do: :all

  defp parse_family(family) when is_binary(family) do
    family
    |> String.to_existing_atom()
    |> then(fn family_atom -> if family_atom in @families, do: family_atom, else: :all end)
  rescue
    ArgumentError -> :all
  end

  defp queue_label(:review), do: "review"
  defp queue_label(:promoted), do: "promoted"
  defp queue_label(:rejected), do: "rejected"
  defp queue_label(:suppressed), do: "suppressed"
  defp queue_label(:parked), do: "parked"

  defp empty_description(:review),
    do: "Procurement bids, discovery records, and future research findings will appear here."

  defp empty_description(:promoted),
    do: "Promoted findings will show once they have been turned into commercial signals."

  defp empty_description(:rejected),
    do: "Rejected findings will appear once operators explicitly reject them."

  defp empty_description(:suppressed),
    do: "Suppressed findings will show here when noise is intentionally filtered out."

  defp empty_description(:parked),
    do: "Parked findings are intake items worth revisiting later."

  defp queue_link(assigns) do
    ~H"""
    <.link
      patch={queue_path(@queue, @selected_family, @selected_source, @selected_program)}
      class={[
        "inline-flex items-center gap-2 rounded-full border px-3 py-1.5 text-sm font-medium transition",
        if(@selected_queue == @queue,
          do: "border-emerald-500 bg-emerald-500 text-white shadow-sm shadow-emerald-500/20",
          else:
            "border-zinc-200 bg-white text-zinc-600 hover:border-emerald-300 hover:text-emerald-700 dark:border-white/10 dark:bg-white/[0.03] dark:text-zinc-300 dark:hover:border-emerald-400/40 dark:hover:text-emerald-300"
        )
      ]}
    >
      <span>{status_label(@queue)}</span>
      <span class={[
        "rounded-full px-2 py-0.5 text-xs font-semibold",
        if(@selected_queue == @queue,
          do: "bg-white/20 text-white",
          else: "bg-zinc-100 text-zinc-500 dark:bg-white/10 dark:text-zinc-300"
        )
      ]}>
        {if @count > 99, do: "99+", else: @count}
      </span>
    </.link>
    """
  end

  attr :family, :atom, required: true
  attr :selected_family, :atom, required: true
  attr :selected_queue, :atom, required: true
  attr :selected_source, :map, default: nil
  attr :selected_program, :map, default: nil

  defp family_link(assigns) do
    ~H"""
    <.link
      patch={queue_path(@selected_queue, @family, @selected_source, @selected_program)}
      class={[
        "inline-flex items-center gap-2 rounded-full border px-3 py-1.5 text-sm font-medium transition",
        if(@selected_family == @family,
          do: "border-sky-500 bg-sky-500 text-white shadow-sm shadow-sky-500/20",
          else:
            "border-zinc-200 bg-white text-zinc-600 hover:border-sky-300 hover:text-sky-700 dark:border-white/10 dark:bg-white/[0.03] dark:text-zinc-300 dark:hover:border-sky-400/40 dark:hover:text-sky-300"
        )
      ]}
    >
      {family_filter_label(@family)}
    </.link>
    """
  end

  defp family_badge(:procurement), do: "badge badge-warning badge-sm"
  defp family_badge(:discovery), do: "badge badge-info badge-sm"
  defp family_badge(:research), do: "badge badge-secondary badge-sm"
  defp family_badge(_), do: "badge badge-ghost badge-sm"

  defp family_label(family), do: family |> to_string() |> String.capitalize()

  defp type_label(type) do
    type
    |> to_string()
    |> String.replace("_", " ")
    |> String.capitalize()
  end

  defp confidence_badge(:high), do: "badge badge-success badge-sm"
  defp confidence_badge(:medium), do: "badge badge-warning badge-sm"
  defp confidence_badge(:low), do: "badge badge-ghost badge-sm"
  defp confidence_badge(_), do: "badge badge-ghost badge-sm"

  defp confidence_label(confidence) do
    confidence
    |> to_string()
    |> String.capitalize()
  end

  defp status_label(status) do
    status
    |> to_string()
    |> String.replace("_", " ")
    |> String.capitalize()
  end

  defp source_or_program_label(%{source: %{name: name}}) when is_binary(name), do: name
  defp source_or_program_label(%{program: %{name: name}}) when is_binary(name), do: name
  defp source_or_program_label(_finding), do: "Direct agent intake"

  defp finding_due_label(finding) do
    case finding.due_at do
      nil -> "No due date"
      due_at -> format_date(due_at)
    end
  end

  defp finding_score_value(%{fit_score: score}) when is_integer(score),
    do: Integer.to_string(score)

  defp finding_score_value(_finding), do: "-"

  defp family_filter_label(:all), do: "All"
  defp family_filter_label(:procurement), do: "Procurement"
  defp family_filter_label(:discovery), do: "Discovery"

  defp parse_dialog_action("accept"), do: :accept
  defp parse_dialog_action("reject"), do: :reject
  defp parse_dialog_action("suppress"), do: :suppress
  defp parse_dialog_action("park"), do: :park
  defp parse_dialog_action(_), do: nil

  defp load_source_filter(nil, _actor), do: nil
  defp load_source_filter("", _actor), do: nil

  defp load_source_filter(id, actor) when is_binary(id) do
    case Acquisition.get_source(
           id,
           actor: actor,
           load: [
             :status_variant,
             :health_status,
             :health_variant,
             :health_note,
             :review_finding_count,
             :promoted_finding_count,
             :noise_finding_count,
             :latest_run_id
           ]
         ) do
      {:ok, source} -> source
      {:error, _error} -> nil
    end
  end

  defp load_program_filter(nil, _actor), do: nil
  defp load_program_filter("", _actor), do: nil

  defp load_program_filter(id, actor) when is_binary(id) do
    case Acquisition.get_program(
           id,
           actor: actor,
           load: [
             :status_variant,
             :health_status,
             :health_variant,
             :health_note,
             :review_finding_count,
             :promoted_finding_count,
             :noise_finding_count,
             :latest_run_id
           ]
         ) do
      {:ok, program} -> program
      {:error, _error} -> nil
    end
  end

  defp format_error(%{errors: [error | _]}) do
    Exception.message(error)
  rescue
    _ -> inspect(error)
  end

  defp format_error(error) when is_binary(error), do: error
  defp format_error(error), do: inspect(error)

  defp queue_path(queue, family, source, program) do
    %{"queue" => to_string(queue)}
    |> maybe_put_param("family", family != :all, family)
    |> maybe_put_param("source_id", is_map(source), source && source.id)
    |> maybe_put_param("program_id", is_map(program), program && program.id)
    |> then(&("/acquisition/findings?" <> URI.encode_query(&1)))
  end

  defp maybe_put_param(params, _key, false, _value), do: params
  defp maybe_put_param(params, _key, _condition, nil), do: params
  defp maybe_put_param(params, key, _condition, value), do: Map.put(params, key, to_string(value))

  defp build_action_dialog(finding, type) do
    %{
      type: type,
      finding_id: finding.id,
      family: finding.finding_family,
      title: finding.title,
      suggested_terms: suggested_terms_for_finding(finding)
    }
  end

  defp suggested_terms_for_finding(%{finding_family: :procurement, source_bid: bid})
       when not is_nil(bid),
       do: TargetingFeedback.suggested_exclude_terms_csv(bid)

  defp suggested_terms_for_finding(%{
         finding_family: :discovery,
         source_discovery_record: discovery_record
       })
       when not is_nil(discovery_record),
       do: discovery_suggested_terms_csv(discovery_record)

  defp suggested_terms_for_finding(_finding), do: ""

  defp discovery_suggested_terms_csv(discovery_record) do
    [discovery_record.industry, discovery_record.website_domain]
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.join(", ")
  end
end
