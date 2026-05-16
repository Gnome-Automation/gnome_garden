defmodule GnomeGardenWeb.Acquisition.FindingLive.Index do
  use GnomeGardenWeb, :live_view

  import GnomeGardenWeb.Components.AcquisitionUI,
    only: [finding_action_bar: 1, format_error: 1, parse_dialog_action: 1, review_dialogs: 1]

  import GnomeGardenWeb.Commercial.Helpers, only: [format_date: 1, format_datetime: 1]

  alias GnomeGarden.Acquisition
  alias GnomeGarden.Procurement.TargetingFeedback
  alias Phoenix.LiveView.JS

  @queues [:review, :promoted, :rejected, :suppressed, :parked]
  @families [:all, :procurement, :discovery]
  @finding_limit 50

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
     |> assign(:findings, [])
     |> assign(:findings_page, nil)}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    queue = parse_queue(Map.get(params, "queue"))
    family = parse_family(Map.get(params, "family"))
    source = load_source_filter(Map.get(params, "source_id"), socket.assigns.current_user)
    program = load_program_filter(Map.get(params, "program_id"), socket.assigns.current_user)

    findings_page =
      list_findings_page(queue, family, source, program, socket.assigns.current_user)

    {:noreply,
     socket
     |> assign(:selected_queue, queue)
     |> assign(:selected_family, family)
     |> assign(:selected_source, source)
     |> assign(:selected_program, program)
     |> assign(:findings_page, findings_page)
     |> assign(:findings, page_results(findings_page))
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

      <.section
        title="Review Surface"
        description="Work the queue from left to right: scope the lane, scan the evidence, decide the next state."
        compact
        body_class="p-0"
      >
        <div class="grid min-h-[34rem] lg:grid-cols-[17rem_minmax(0,1fr)]">
          <aside class="border-b border-zinc-200 bg-zinc-50/70 p-3 dark:border-white/10 dark:bg-white/[0.03] lg:border-b-0 lg:border-r">
            <div class="grid gap-2 sm:grid-cols-5 lg:grid-cols-1">
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

            <div class="mt-4">
              <p class="mb-2 text-xs font-semibold uppercase tracking-[0.18em] text-base-content/40">
                Lane
              </p>
              <div class="grid grid-cols-3 gap-2 lg:grid-cols-1">
                <.family_link
                  :for={family <- @families}
                  family={family}
                  selected_family={@selected_family}
                  selected_queue={@selected_queue}
                  selected_source={@selected_source}
                  selected_program={@selected_program}
                />
              </div>
            </div>

            <.filter_context
              source={@selected_source}
              program={@selected_program}
              queue={@selected_queue}
              family={@selected_family}
            />
          </aside>

          <div class="min-w-0">
            <div class="flex flex-col gap-3 border-b border-zinc-200 px-3 py-3 dark:border-white/10 sm:flex-row sm:items-center sm:justify-between sm:px-4">
              <div class="min-w-0">
                <p class="text-sm font-semibold text-base-content">
                  {status_label(@selected_queue)} · {family_filter_label(@selected_family)}
                </p>
                <p class="mt-0.5 text-xs text-base-content/50">
                  Showing {length(@findings)} of {page_count(@findings_page)} findings
                </p>
              </div>
              <div class="grid grid-cols-3 gap-2 sm:w-[22rem]">
                <.queue_count label="Review" value={@queue_counts.review} />
                <.queue_count label="Promoted" value={@queue_counts.promoted} />
                <.queue_count label="Noise" value={@queue_counts.rejected + @queue_counts.suppressed} />
              </div>
            </div>

            <div
              :if={@findings != []}
              id="acquisition-finding-cards"
              class="divide-y divide-zinc-200 bg-base-100 dark:divide-white/10"
            >
              <.finding_card :for={finding <- @findings} finding={finding} />
            </div>

            <div :if={@findings == []} class="p-4">
              <.empty_state
                icon="hero-inbox-stack"
                title={"No #{queue_label(@selected_queue)} findings"}
                description={empty_description(@selected_queue)}
              />
            </div>
          </div>
        </div>
      </.section>

      <.review_dialogs action_dialog={@action_dialog} id_prefix="finding" />
    </.page>
    """
  end

  attr :finding, :map, required: true

  defp finding_card(assigns) do
    ~H"""
    <article
      id={"finding-card-#{@finding.id}"}
      phx-click={JS.navigate(~p"/acquisition/findings/#{@finding.id}")}
      role="link"
      tabindex="0"
      class="grid cursor-pointer gap-3 px-3 py-3 transition hover:bg-zinc-50/80 focus:outline-none focus:ring-2 focus:ring-emerald-500/50 focus:ring-inset dark:hover:bg-white/[0.025] sm:px-4 lg:grid-cols-[minmax(0,1fr)_16rem]"
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
              <.status_badge status={@finding.status_variant}>
                {@finding.status_label}
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
                {@finding.summary || "No summary yet."}
              </p>
            </div>
          </div>

          <div class="grid grid-cols-2 gap-2 sm:w-48 sm:shrink-0">
            <.finding_metric label="Score" value={finding_score_value(@finding)} />
            <.finding_metric label="Due" value={finding_due_label(@finding)} />
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

      <div
        onclick="event.stopPropagation()"
        class="flex flex-col gap-3 border-t border-zinc-200 pt-3 dark:border-white/10 lg:border-l lg:border-t-0 lg:pl-4 lg:pt-0"
      >
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

  defp queue_count(assigns) do
    ~H"""
    <div class="rounded-md border border-base-content/10 bg-base-200/70 px-2.5 py-2">
      <p class="text-[10px] font-semibold uppercase tracking-[0.14em] text-base-content/45">
        {@label}
      </p>
      <p class="mt-0.5 text-sm font-semibold tabular-nums text-base-content">{@value}</p>
    </div>
    """
  end

  attr :source, :map, default: nil
  attr :program, :map, default: nil
  attr :queue, :atom, required: true
  attr :family, :atom, required: true

  defp filter_context(assigns) do
    ~H"""
    <div :if={@source || @program} class="mt-4 space-y-3">
      <.context_panel
        :if={@source}
        label="Source Context"
        name={@source.name}
        status={status_label(@source.status)}
        status_variant={@source.status_variant}
        health={status_label(@source.health_status)}
        health_variant={@source.health_variant}
        note={@source.health_note}
        review_count={@source.review_finding_count}
        promoted_count={@source.promoted_finding_count}
        noise_count={@source.noise_finding_count}
        registry_path={~p"/acquisition/sources"}
        latest_run_id={@source.latest_run_id}
      />
      <.context_panel
        :if={@program}
        label="Program Context"
        name={@program.name}
        status={status_label(@program.status)}
        status_variant={@program.status_variant}
        health={status_label(@program.health_status)}
        health_variant={@program.health_variant}
        note={@program.health_note}
        review_count={@program.review_finding_count}
        promoted_count={@program.promoted_finding_count}
        noise_count={@program.noise_finding_count}
        registry_path={~p"/acquisition/programs"}
        latest_run_id={@program.latest_run_id}
      />
      <.link patch={queue_path(@queue, @family, nil, nil)} class="btn btn-xs btn-ghost w-full">
        Clear Filter
      </.link>
    </div>
    """
  end

  attr :label, :string, required: true
  attr :name, :string, required: true
  attr :status, :string, required: true
  attr :status_variant, :atom, required: true
  attr :health, :string, required: true
  attr :health_variant, :atom, required: true
  attr :note, :string, default: nil
  attr :review_count, :integer, default: 0
  attr :promoted_count, :integer, default: 0
  attr :noise_count, :integer, default: 0
  attr :registry_path, :string, required: true
  attr :latest_run_id, :string, default: nil

  defp context_panel(assigns) do
    ~H"""
    <div class="rounded-lg border border-zinc-200 bg-white/80 p-3 dark:border-white/10 dark:bg-zinc-950/20">
      <div class="space-y-2">
        <p class="text-xs font-semibold uppercase tracking-[0.18em] text-base-content/40">
          {@label}
        </p>
        <p class="text-sm font-semibold leading-5 text-base-content">{@name}</p>
        <div class="flex flex-wrap gap-1.5">
          <.status_badge status={@status_variant}>{@status}</.status_badge>
          <.status_badge status={@health_variant}>{@health}</.status_badge>
        </div>
      </div>
      <p class="mt-3 text-xs leading-5 text-base-content/55">
        {@review_count} review · {@promoted_count} promoted · {@noise_count} noise
      </p>
      <p :if={@note} class="mt-2 text-xs leading-5 text-base-content/50">
        {@note}
      </p>
      <div class="mt-3 flex flex-wrap gap-1.5">
        <.link navigate={@registry_path} class="btn btn-xs btn-ghost">
          Registry
        </.link>
        <.link
          :if={@latest_run_id}
          navigate={~p"/console/agents/runs/#{@latest_run_id}"}
          class="btn btn-xs btn-ghost"
        >
          Open Run
        </.link>
      </div>
    </div>
    """
  end

  defp finding_metric(assigns) do
    ~H"""
    <div class="rounded-md border border-base-content/10 bg-base-200/70 px-3 py-2">
      <p class="text-[11px] font-semibold uppercase tracking-[0.14em] text-base-content/45">
        {@label}
      </p>
      <p class="mt-1 truncate text-sm font-semibold text-base-content">{@value}</p>
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
      :findings_page,
      list_findings_page(
        socket.assigns.selected_queue,
        socket.assigns.selected_family,
        socket.assigns.selected_source,
        socket.assigns.selected_program,
        socket.assigns.current_user
      )
    )
    |> then(&assign(&1, :findings, page_results(&1.assigns.findings_page)))
  end

  defp list_findings_page(queue, family, source, program, actor) do
    case Acquisition.list_findings_queue(
           queue,
           family,
           filter_id(source),
           filter_id(program),
           actor: actor,
           page: [limit: @finding_limit, count: true]
         ) do
      {:ok, page} -> page
      {:error, _error} -> empty_page()
    end
  end

  defp count_findings(queue, family, source, program, actor) do
    queue
    |> list_findings_count_page(family, source, program, actor)
    |> page_count()
  end

  defp list_findings_count_page(queue, family, source, program, actor) do
    case Acquisition.list_findings_queue(
           queue,
           family,
           filter_id(source),
           filter_id(program),
           actor: actor,
           page: [limit: 1, count: true]
         ) do
      {:ok, page} -> page
      {:error, _error} -> empty_page()
    end
  end

  defp filter_id(%{id: id}), do: id
  defp filter_id(_filter), do: nil

  defp page_results(%{results: results}), do: results
  defp page_results(results) when is_list(results), do: results
  defp page_results(_page), do: []

  defp page_count(%{count: count}) when is_integer(count), do: count
  defp page_count(page), do: length(page_results(page))

  defp empty_page, do: %{results: [], count: 0}

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
        "inline-flex min-w-0 items-center justify-between gap-2 rounded-md border px-3 py-2 text-sm font-medium transition",
        if(@selected_queue == @queue,
          do: "border-emerald-600 bg-emerald-600 text-white shadow-sm shadow-emerald-600/20",
          else:
            "border-zinc-200 bg-white text-zinc-600 hover:border-emerald-300 hover:text-emerald-700 dark:border-white/10 dark:bg-white/[0.03] dark:text-zinc-300 dark:hover:border-emerald-400/40 dark:hover:text-emerald-300"
        )
      ]}
    >
      <span class="truncate">{status_label(@queue)}</span>
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
        "inline-flex items-center justify-center gap-2 rounded-md border px-3 py-2 text-sm font-medium transition",
        if(@selected_family == @family,
          do: "border-sky-600 bg-sky-600 text-white shadow-sm shadow-sky-600/20",
          else:
            "border-zinc-200 bg-white text-zinc-600 hover:border-sky-300 hover:text-sky-700 dark:border-white/10 dark:bg-white/[0.03] dark:text-zinc-300 dark:hover:border-sky-400/40 dark:hover:text-sky-300"
        )
      ]}
    >
      {family_filter_label(@family)}
    </.link>
    """
  end

  defp source_or_program_label(%{source: %{name: name}}) when is_binary(name), do: name
  defp source_or_program_label(%{program: %{name: name}}) when is_binary(name), do: name
  defp source_or_program_label(_finding), do: "Direct agent intake"

  defp organization_name(%{organization: %{name: name}}) when is_binary(name), do: name
  defp organization_name(_finding), do: nil

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
