defmodule GnomeGardenWeb.Acquisition.FindingLive.Index do
  use GnomeGardenWeb, :live_view

  import GnomeGardenWeb.Commercial.Helpers, only: [format_date: 1, format_datetime: 1]

  alias GnomeGarden.Acquisition
  alias GnomeGarden.Commercial.DiscoveryFeedback
  alias GnomeGarden.Procurement.TargetingFeedback

  @queues [:review, :promoted, :rejected, :suppressed, :parked]
  @families [:all, :procurement, :discovery]

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
     |> assign(:findings_empty?, true)
     |> stream(:findings, [], reset: true)}
  end

  @impl true
  def handle_params(params, _uri, socket) do
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
     |> refresh_queue()}
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
            <.icon name="hero-globe-alt" class="size-4" /> Sources
          </.button>
          <.button navigate={~p"/acquisition/programs"}>
            <.icon name="hero-radar" class="size-4" /> Programs
          </.button>
          <.button navigate={~p"/commercial/signals"}>
            <.icon name="hero-inbox-stack" class="size-4" /> Signal Queue
          </.button>
        </:actions>
      </.page_header>

      <div class="grid gap-3 xl:grid-cols-3">
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
        description="Run procurement, discovery, and future lead-finding through one queue before it becomes commercial work."
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
            <span class="text-xs font-semibold uppercase tracking-[0.18em] text-zinc-400 dark:text-zinc-500">
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
              <.icon name="hero-globe-alt" class="size-4" /> {@selected_source.name}
            </span>
            <span
              :if={@selected_program}
              class="inline-flex items-center gap-2 rounded-full border border-sky-200 bg-sky-50 px-3 py-1.5 text-sm font-medium text-sky-700 dark:border-sky-400/30 dark:bg-sky-400/10 dark:text-sky-200"
            >
              <.icon name="hero-radar" class="size-4" /> {@selected_program.name}
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
                  <p class="text-xs font-semibold uppercase tracking-[0.18em] text-zinc-400 dark:text-zinc-500">
                    Source Context
                  </p>
                  <p class="text-sm font-medium text-zinc-900 dark:text-white">
                    {@selected_source.name}
                  </p>
                  <p class="text-xs text-zinc-500 dark:text-zinc-400">
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
              <p class="mt-3 text-xs text-zinc-500 dark:text-zinc-400">
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
                  <p class="text-xs font-semibold uppercase tracking-[0.18em] text-zinc-400 dark:text-zinc-500">
                    Program Context
                  </p>
                  <p class="text-sm font-medium text-zinc-900 dark:text-white">
                    {@selected_program.name}
                  </p>
                  <p class="text-xs text-zinc-500 dark:text-zinc-400">
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
              <p class="mt-3 text-xs text-zinc-500 dark:text-zinc-400">
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

        <div :if={@findings_empty?} class="p-4 sm:p-5">
          <.empty_state
            icon="hero-inbox-stack"
            title={"No #{queue_label(@selected_queue)} findings"}
            description={empty_description(@selected_queue)}
          />
        </div>

        <div :if={!@findings_empty?} class="overflow-x-auto">
          <table class="min-w-[102rem] divide-y divide-zinc-200 text-sm dark:divide-white/10">
            <thead class="bg-zinc-50 dark:bg-white/[0.03]">
              <tr>
                <th class="px-3 py-2 text-left text-xs font-medium uppercase tracking-[0.14em] text-zinc-500 dark:text-zinc-400">
                  Finding
                </th>
                <th class="px-3 py-2 text-left text-xs font-medium uppercase tracking-[0.14em] text-zinc-500 dark:text-zinc-400">
                  Due
                </th>
                <th class="px-3 py-2 text-left text-xs font-medium uppercase tracking-[0.14em] text-zinc-500 dark:text-zinc-400">
                  Score
                </th>
                <th class="px-3 py-2 text-left text-xs font-medium uppercase tracking-[0.14em] text-zinc-500 dark:text-zinc-400">
                  City / State
                </th>
                <th class="px-3 py-2 text-left text-xs font-medium uppercase tracking-[0.14em] text-zinc-500 dark:text-zinc-400">
                  Work
                </th>
                <th class="px-3 py-2 text-left text-xs font-medium uppercase tracking-[0.14em] text-zinc-500 dark:text-zinc-400">
                  Lane
                </th>
                <th class="px-3 py-2 text-left text-xs font-medium uppercase tracking-[0.14em] text-zinc-500 dark:text-zinc-400">
                  Observed
                </th>
                <th class="px-3 py-2 text-left text-xs font-medium uppercase tracking-[0.14em] text-zinc-500 dark:text-zinc-400">
                  Status
                </th>
                <th class="px-3 py-2 text-left text-xs font-medium uppercase tracking-[0.14em] text-zinc-500 dark:text-zinc-400">
                  Open
                </th>
                <th class="px-3 py-2 text-left text-xs font-medium uppercase tracking-[0.14em] text-zinc-500 dark:text-zinc-400">
                  Actions
                </th>
              </tr>
            </thead>
            <tbody
              id="findings"
              phx-update="stream"
              class="divide-y divide-zinc-200 dark:divide-white/10"
            >
              <tr :for={{dom_id, finding} <- @streams.findings} id={dom_id}>
                <td class="px-3 py-2.5 align-top">
                  <div class="space-y-1">
                    <p class="font-medium text-zinc-900 dark:text-white">{finding.title}</p>
                    <p class="max-w-xl text-xs leading-5 text-zinc-500 dark:text-zinc-400">
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
                </td>
                <td class="px-3 py-2.5 align-top text-zinc-600 dark:text-zinc-300">
                  <div class="space-y-1">
                    <p class="font-medium text-zinc-900 dark:text-white">
                      {finding_due_label(finding)}
                    </p>
                    <p :if={finding.due_status_label} class="text-xs text-zinc-500 dark:text-zinc-400">
                      {finding.due_status_label}
                    </p>
                  </div>
                </td>
                <td class="px-3 py-2.5 align-top">
                  <div class="space-y-1">
                    <p class="font-semibold text-zinc-900 dark:text-white">
                      {finding_score_value(finding)}
                    </p>
                    <p :if={finding.score_note} class="text-xs text-zinc-500 dark:text-zinc-400">
                      {finding.score_note}
                    </p>
                    <.status_badge :if={finding.score_tier} status={finding.score_tier_variant}>
                      {status_label(finding.score_tier)}
                    </.status_badge>
                  </div>
                </td>
                <td class="px-3 py-2.5 align-top text-zinc-600 dark:text-zinc-300">
                  <div class="space-y-1">
                    <p class="font-medium text-zinc-900 dark:text-white">
                      {finding.location || "No location"}
                    </p>
                    <p :if={finding.location_note} class="text-xs text-zinc-500 dark:text-zinc-400">
                      {finding.location_note}
                    </p>
                  </div>
                </td>
                <td class="px-3 py-2.5 align-top text-zinc-600 dark:text-zinc-300">
                  <div class="space-y-1">
                    <p class="font-medium text-zinc-900 dark:text-white">
                      {finding.work_summary || type_label(finding.finding_type)}
                    </p>
                    <p :if={finding.work_type} class="text-xs text-zinc-500 dark:text-zinc-400">
                      {finding.work_type}
                    </p>
                    <p
                      :if={finding.work_note}
                      class="max-w-[14rem] text-xs text-zinc-500 dark:text-zinc-400"
                    >
                      {finding.work_note}
                    </p>
                  </div>
                </td>
                <td class="px-3 py-2.5 align-top text-zinc-600 dark:text-zinc-300">
                  <div class="space-y-1">
                    <p>{source_or_program_label(finding)}</p>
                    <p :if={finding.organization} class="text-xs text-zinc-500 dark:text-zinc-400">
                      {finding.organization.name}
                    </p>
                  </div>
                </td>
                <td class="px-3 py-2.5 align-top text-zinc-600 dark:text-zinc-300 whitespace-nowrap">
                  {format_datetime(finding.observed_at || finding.inserted_at)}
                </td>
                <td class="px-3 py-2.5 align-top">
                  <div class="space-y-1">
                    <.status_badge status={finding.status_variant}>
                      {status_label(finding.status)}
                    </.status_badge>
                    <p
                      :if={finding.latest_review_reason}
                      class="max-w-xs text-xs leading-5 text-zinc-500 dark:text-zinc-400"
                    >
                      {finding.latest_review_reason}
                    </p>
                    <p
                      :if={finding.latest_review_decision_at}
                      class="text-[11px] uppercase tracking-[0.12em] text-zinc-400 dark:text-zinc-500"
                    >
                      {status_label(finding.latest_review_decision || finding.status)} · {format_datetime(
                        finding.latest_review_decision_at
                      )}
                    </p>
                  </div>
                </td>
                <td class="px-3 py-2.5 align-top">
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
                </td>
                <td class="px-3 py-2.5 align-top">
                  <div class="flex flex-wrap gap-1.5">
                    <.button
                      :if={finding.status in [:new]}
                      id={"finding-start-review-#{finding.id}"}
                      phx-click="transition"
                      phx-value-id={finding.id}
                      phx-value-action="start_review"
                      class="px-2.5 py-1.5 text-xs"
                    >
                      Start Review
                    </.button>
                    <.button
                      :if={finding.status == :reviewing and finding.acceptance_ready}
                      id={"finding-accept-#{finding.id}"}
                      phx-click="open_dialog"
                      phx-value-id={finding.id}
                      phx-value-action="accept"
                      class="px-2.5 py-1.5 text-xs"
                    >
                      Accept
                    </.button>
                    <.button
                      :if={prep_action_path(finding)}
                      id={"finding-prep-#{finding.id}"}
                      navigate={prep_action_path(finding)}
                      class="border-zinc-200 bg-white px-2.5 py-1.5 text-xs text-zinc-600 hover:border-emerald-300 hover:text-emerald-700 dark:border-white/10 dark:bg-white/[0.03] dark:text-zinc-300 dark:hover:border-emerald-400/40 dark:hover:text-emerald-300"
                    >
                      {prep_action_label(finding)}
                    </.button>
                    <.button
                      :if={
                        finding.status == :accepted and finding.promotion_ready and
                          is_nil(finding.signal_id)
                      }
                      id={"finding-promote-#{finding.id}"}
                      phx-click="transition"
                      phx-value-id={finding.id}
                      phx-value-action="promote"
                      variant="primary"
                      class="px-2.5 py-1.5 text-xs"
                    >
                      Promote To Signal
                    </.button>
                    <.button
                      :if={finding.status in [:reviewing, :accepted]}
                      id={"finding-reject-#{finding.id}"}
                      phx-click="open_dialog"
                      phx-value-id={finding.id}
                      phx-value-action="reject"
                      class="border-zinc-200 bg-white px-2.5 py-1.5 text-xs text-zinc-600 hover:border-rose-300 hover:text-rose-700 dark:border-white/10 dark:bg-white/[0.03] dark:text-zinc-300 dark:hover:border-rose-400/40 dark:hover:text-rose-300"
                    >
                      Reject
                    </.button>
                    <.button
                      :if={finding.status in [:reviewing, :accepted]}
                      id={"finding-suppress-#{finding.id}"}
                      phx-click="open_dialog"
                      phx-value-id={finding.id}
                      phx-value-action="suppress"
                      class="border-zinc-200 bg-white px-2.5 py-1.5 text-xs text-zinc-600 hover:border-amber-300 hover:text-amber-700 dark:border-white/10 dark:bg-white/[0.03] dark:text-zinc-300 dark:hover:border-amber-400/40 dark:hover:text-amber-300"
                    >
                      Suppress
                    </.button>
                    <.button
                      :if={finding.status in [:reviewing, :accepted]}
                      id={"finding-park-#{finding.id}"}
                      phx-click="open_dialog"
                      phx-value-id={finding.id}
                      phx-value-action="park"
                      class="border-zinc-200 bg-white px-2.5 py-1.5 text-xs text-zinc-600 hover:border-sky-300 hover:text-sky-700 dark:border-white/10 dark:bg-white/[0.03] dark:text-zinc-300 dark:hover:border-sky-400/40 dark:hover:text-sky-300"
                    >
                      Park
                    </.button>
                    <.button
                      :if={show_reopen?(finding)}
                      id={"finding-reopen-#{finding.id}"}
                      phx-click="transition"
                      phx-value-id={finding.id}
                      phx-value-action="reopen"
                      class="px-2.5 py-1.5 text-xs"
                    >
                      Reopen
                    </.button>
                  </div>
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
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </.section>

      <dialog
        :if={@action_dialog && @action_dialog.type in [:accept, :reject, :suppress]}
        id="finding-review-dialog"
        class="modal"
        phx-hook="ShowModal"
      >
        <div class="modal-box">
          <h3 class="mb-2 text-lg font-bold">{dialog_heading(@action_dialog)}</h3>
          <p class="mb-4 text-sm text-zinc-500">{@action_dialog.title}</p>
          <form
            id={"finding-#{@action_dialog.type}-form"}
            phx-submit={"submit_#{@action_dialog.type}"}
          >
            <div class="space-y-3">
              <.input
                :if={@action_dialog.type == :accept}
                name="reason"
                value=""
                label="Why are we accepting this finding?"
                type="textarea"
                placeholder="Explain why this intake is worth keeping and refining."
                required
              />
              <.input
                :if={@action_dialog.type in [:reject, :suppress]}
                name="reason_code"
                value={dialog_default_reason_code(@action_dialog)}
                label="Disposition code"
                type="select"
                prompt={dialog_reason_prompt(@action_dialog)}
                options={dialog_reason_options(@action_dialog)}
              />
              <.input
                :if={@action_dialog.type in [:reject, :suppress]}
                name="reason"
                value=""
                label="Operator note (optional)"
                type="text"
                placeholder="Add specific context for this intake decision"
              />
              <.input
                :if={@action_dialog.type in [:reject, :suppress]}
                name="feedback_scope"
                value={dialog_default_feedback_scope(@action_dialog)}
                label="Teach the search/profile (optional)"
                type="select"
                prompt={dialog_feedback_prompt(@action_dialog)}
                options={dialog_feedback_scope_options(@action_dialog)}
              />
              <.input
                :if={@action_dialog.type in [:reject, :suppress]}
                name="exclude_terms"
                value={@action_dialog.suggested_terms}
                label="Keywords to suppress next time"
                type="text"
                placeholder="e.g. cctv, municipal ERP, generic admin software"
              />
            </div>
            <div class="modal-action">
              <button type="button" phx-click="close_dialog" class="btn btn-ghost">Cancel</button>
              <.button type="submit" variant="primary" phx-disable-with="Saving...">
                {dialog_submit_label(@action_dialog)}
              </.button>
            </div>
          </form>
        </div>
        <form method="dialog" class="modal-backdrop">
          <button phx-click="close_dialog">close</button>
        </form>
      </dialog>

      <dialog
        :if={@action_dialog && @action_dialog.type == :park}
        id="finding-park-dialog"
        class="modal"
        phx-hook="ShowModal"
      >
        <div class="modal-box">
          <h3 class="mb-2 text-lg font-bold">Park this finding?</h3>
          <p class="mb-4 text-sm text-zinc-500">{@action_dialog.title}</p>
          <form id="finding-park-form" phx-submit="submit_park">
            <div class="space-y-3">
              <.input
                name="reason"
                value=""
                label="Why are we parking this?"
                type="text"
                placeholder="e.g. Keep watching, timing is not right yet"
              />
              <.input
                :if={@action_dialog.family == :procurement}
                name="research"
                value=""
                label="Research needed (optional)"
                type="textarea"
                placeholder="Capture any follow-up research or capability work needed before this returns."
              />
            </div>
            <div class="modal-action">
              <button type="button" phx-click="close_dialog" class="btn btn-ghost">Cancel</button>
              <.button type="submit" variant="primary" phx-disable-with="Parking...">
                Park Finding
              </.button>
            </div>
          </form>
        </div>
        <form method="dialog" class="modal-backdrop">
          <button phx-click="close_dialog">close</button>
        </form>
      </dialog>
    </.page>
    """
  end

  defp refresh_queue(socket) do
    findings =
      load_findings(
        socket.assigns.selected_queue,
        socket.assigns.selected_family,
        socket.assigns.selected_source,
        socket.assigns.selected_program,
        socket.assigns.current_user
      )

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
    |> assign(:findings_empty?, findings == [])
    |> stream(:findings, findings, reset: true)
  end

  defp load_findings(:review, family, source, program, actor),
    do:
      list_or_raise(fn ->
        Acquisition.list_review_findings(
          actor: actor,
          query: finding_query(family, source, program)
        )
      end)

  defp load_findings(:promoted, family, source, program, actor),
    do:
      list_or_raise(fn ->
        Acquisition.list_promoted_findings(
          actor: actor,
          query: finding_query(family, source, program)
        )
      end)

  defp load_findings(:rejected, family, source, program, actor),
    do:
      list_or_raise(fn ->
        Acquisition.list_rejected_findings(
          actor: actor,
          query: finding_query(family, source, program)
        )
      end)

  defp load_findings(:suppressed, family, source, program, actor),
    do:
      list_or_raise(fn ->
        Acquisition.list_suppressed_findings(
          actor: actor,
          query: finding_query(family, source, program)
        )
      end)

  defp load_findings(:parked, family, source, program, actor),
    do:
      list_or_raise(fn ->
        Acquisition.list_parked_findings(
          actor: actor,
          query: finding_query(family, source, program)
        )
      end)

  defp queue_counts(family \\ :all, source \\ nil, program \\ nil, actor \\ nil) do
    %{
      review: length(load_findings(:review, family, source, program, actor)),
      promoted: length(load_findings(:promoted, family, source, program, actor)),
      rejected: length(load_findings(:rejected, family, source, program, actor)),
      suppressed: length(load_findings(:suppressed, family, source, program, actor)),
      parked: length(load_findings(:parked, family, source, program, actor))
    }
  end

  defp list_or_raise(fun) do
    case fun.() do
      {:ok, findings} -> findings
      {:error, error} -> raise "failed to load acquisition findings: #{inspect(error)}"
    end
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

  defp show_reopen?(%{status: :parked}), do: true

  defp show_reopen?(%{status: :rejected, source_discovery_record_id: target_id})
       when is_binary(target_id), do: true

  defp show_reopen?(%{status: :suppressed, source_discovery_record_id: target_id})
       when is_binary(target_id), do: true

  defp show_reopen?(_finding), do: false

  defp prep_action_path(%{
         status: status,
         signal_id: nil,
         finding_family: :procurement,
         id: id
       })
       when status in [:reviewing, :accepted],
       do: "/acquisition/findings/#{id}/documents/new"

  defp prep_action_path(%{
         status: status,
         signal_id: nil,
         finding_family: :discovery,
         id: id
       })
       when status in [:reviewing, :accepted],
       do: "/acquisition/findings/#{id}/evidence/new"

  defp prep_action_path(_finding), do: nil

  defp prep_action_label(%{finding_family: :procurement}), do: "Add Document"
  defp prep_action_label(%{finding_family: :discovery}), do: "Add Evidence"
  defp prep_action_label(_finding), do: "Add Prep"

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

  defp finding_query(family, source, program) do
    filters =
      []
      |> maybe_put_filter(:finding_family, family != :all, family)
      |> maybe_put_filter(:source_id, is_map(source), source && source.id)
      |> maybe_put_filter(:program_id, is_map(program), program && program.id)

    if filters == [], do: [], else: [filter: filters]
  end

  defp maybe_put_filter(filters, _key, false, _value), do: filters
  defp maybe_put_filter(filters, _key, _condition, nil), do: filters
  defp maybe_put_filter(filters, key, _condition, value), do: Keyword.put(filters, key, value)

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

  defp dialog_heading(%{type: :accept}), do: "Accept this finding?"
  defp dialog_heading(%{type: :reject}), do: "Reject this finding?"
  defp dialog_heading(%{type: :suppress}), do: "Suppress this finding?"

  defp dialog_submit_label(%{type: :accept}), do: "Confirm Accept"
  defp dialog_submit_label(%{type: :reject}), do: "Confirm Reject"
  defp dialog_submit_label(%{type: :suppress}), do: "Confirm Suppress"

  defp dialog_reason_prompt(%{type: :accept}), do: nil
  defp dialog_reason_prompt(%{type: :reject}), do: "Select a disposition..."
  defp dialog_reason_prompt(%{type: :suppress}), do: "Select a suppression reason..."

  defp dialog_feedback_prompt(%{type: :accept}), do: nil
  defp dialog_feedback_prompt(%{type: :reject}), do: "Just reject this finding"
  defp dialog_feedback_prompt(%{type: :suppress}), do: "Just suppress this finding"

  defp dialog_default_reason_code(%{type: :accept}), do: nil

  defp dialog_default_reason_code(%{type: :suppress, family: :procurement}),
    do: "source_noise_or_misclassified"

  defp dialog_default_reason_code(%{type: :suppress, family: :discovery}),
    do: "source_noise_or_misclassified"

  defp dialog_default_reason_code(_dialog), do: nil

  defp dialog_default_feedback_scope(%{type: :suppress}), do: "source"
  defp dialog_default_feedback_scope(_dialog), do: nil

  defp dialog_reason_options(%{type: :accept}), do: []

  defp dialog_reason_options(%{family: :procurement}),
    do: TargetingFeedback.pass_reason_options()

  defp dialog_reason_options(%{family: :discovery}),
    do: DiscoveryFeedback.reject_reason_options()

  defp dialog_feedback_scope_options(%{type: :accept}), do: []

  defp dialog_feedback_scope_options(%{family: :procurement}) do
    [
      {"Out of scope for us", "out_of_scope"},
      {"Not targeting this type right now", "not_targeting_right_now"},
      {"This source is noisy", "source"}
    ]
  end

  defp dialog_feedback_scope_options(%{family: :discovery}) do
    [
      {"Out of scope for us", "out_of_scope"},
      {"Not targeting this type right now", "not_targeting_right_now"},
      {"This source is noisy", "source"}
    ]
  end
end
