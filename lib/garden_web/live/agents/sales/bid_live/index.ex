defmodule GnomeGardenWeb.Agents.Sales.BidLive.Index do
  use GnomeGardenWeb, :live_view

  alias GnomeGarden.Procurement
  alias GnomeGarden.Procurement.BidReview
  alias GnomeGarden.Procurement.TargetingFeedback

  @queues [:review, :active, :parked, :rejected, :closed]

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      GnomeGardenWeb.Endpoint.subscribe("bid:created")
      GnomeGardenWeb.Endpoint.subscribe("bid:scored")
      GnomeGardenWeb.Endpoint.subscribe("bid:updated")
    end

    {:ok,
     socket
     |> assign(:page_title, "Bids")
     |> assign(:selected_queue, :review)
     |> assign(:action_dialog, nil)
     |> assign(:queue_counts, zero_counts())
     |> assign(:bids_empty?, true)
     |> stream(:bids, [], reset: true)}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    queue = parse_queue(Map.get(params, "queue"))
    bids = load_bids_for_queue(queue, socket.assigns.current_user)
    queue_counts = load_queue_counts(socket.assigns.current_user)

    {:noreply,
     socket
     |> assign(:selected_queue, queue)
     |> assign(:queue_counts, queue_counts)
     |> assign(:bids_empty?, bids == [])
     |> stream(:bids, bids, reset: true)}
  end

  @impl true
  def handle_info(%{topic: "bid:" <> _}, socket) do
    {:noreply, refresh_backlog(socket)}
  end

  @impl true
  def handle_event("transition", %{"id" => id, "action" => "open_signal"}, socket) do
    case BidReview.open_signal(id, socket.assigns.current_user) do
      {:ok, %{signal: signal}} ->
        {:noreply,
         socket
         |> put_flash(:info, "Opened bid signal")
         |> push_navigate(to: ~p"/commercial/signals/#{signal}")}

      {:error, error} ->
        {:noreply, put_flash(socket, :error, "Could not open signal: #{inspect(error)}")}
    end
  end

  def handle_event("transition", %{"id" => id, "action" => action}, socket) do
    action = String.to_existing_atom(action)

    case transition_bid(id, action, socket.assigns.current_user) do
      {:ok, _bid} ->
        {:noreply, put_flash(socket, :info, "Bid updated")}

      {:error, error} ->
        {:noreply, put_flash(socket, :error, "Could not update bid: #{inspect(error)}")}
    end
  end

  def handle_event("open_dialog", %{"id" => id, "action" => action}, socket) do
    case Procurement.get_bid(id, actor: socket.assigns.current_user) do
      {:ok, bid} ->
        {:noreply,
         assign(socket, :action_dialog, %{
           type: String.to_existing_atom(action),
           bid_id: bid.id,
           title: bid.title,
           suggested_terms: TargetingFeedback.suggested_exclude_terms_csv(bid)
         })}

      {:error, error} ->
        {:noreply, put_flash(socket, :error, "Could not load bid: #{inspect(error)}")}
    end
  end

  def handle_event("close_dialog", _, socket) do
    {:noreply, assign(socket, :action_dialog, nil)}
  end

  def handle_event("submit_pass", params, socket) do
    case BidReview.pass_bid(
           socket.assigns.action_dialog.bid_id,
           params,
           socket.assigns.current_user
         ) do
      {:ok, _bid} ->
        {:noreply,
         socket
         |> assign(:action_dialog, nil)
         |> put_flash(:info, "Passed bid")}

      {:error, error} ->
        {:noreply, put_flash(socket, :error, "Could not pass bid: #{inspect(error)}")}
    end
  end

  def handle_event("submit_park", params, socket) do
    reason = params["reason"]
    research_note = params["research"]

    case BidReview.park_bid(
           socket.assigns.action_dialog.bid_id,
           reason,
           research_note,
           socket.assigns.current_user
         ) do
      {:ok, _bid} ->
        {:noreply,
         socket
         |> assign(:action_dialog, nil)
         |> put_flash(:info, "Parked bid")}

      {:error, error} ->
        {:noreply, put_flash(socket, :error, "Could not park bid: #{inspect(error)}")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.page class="pb-8">
      <.page_header eyebrow="Procurement">
        Bid Queue
        <:subtitle>
          Procurement intake runs through explicit bid states now. Review, park, reject, and advance bids directly from the queue instead of drilling into each record first.
        </:subtitle>
        <:actions>
          <.button navigate={~p"/procurement/targeting"}>
            <.icon name="hero-funnel" class="size-4" /> Targeting
          </.button>
          <.button navigate={~p"/procurement/sources"}>
            <.icon name="hero-globe-alt" class="size-4" /> Sources
          </.button>
          <a href="/admin/agents/bid" class="btn btn-sm btn-ghost gap-1">
            Open in Admin <.icon name="hero-arrow-top-right-on-square" class="size-4" />
          </a>
        </:actions>
      </.page_header>

      <div class="grid gap-4 md:grid-cols-3">
        <.stat_card
          title="Review Queue"
          value={Integer.to_string(@queue_counts.review)}
          description="New and reviewing bids waiting for qualification."
          icon="hero-eye"
        />
        <.stat_card
          title="Active Pursuit"
          value={Integer.to_string(@queue_counts.active)}
          description="Bids already in pursuing or submitted states."
          icon="hero-rocket-launch"
          accent="sky"
        />
        <.stat_card
          title="Parked"
          value={Integer.to_string(@queue_counts.parked)}
          description="Deferred bids that should stay visible without polluting the live queue."
          icon="hero-pause-circle"
          accent="amber"
        />
      </div>

      <.section
        title="Bid Backlog"
        description="Queues map directly to the bid state machine and refresh from Ash PubSub updates."
        compact
        body_class="p-0"
      >
        <div class="border-b border-zinc-200 px-5 py-4 dark:border-white/10">
          <div class="flex flex-wrap items-center gap-2">
            <.queue_link
              :for={queue <- queues()}
              queue={queue}
              selected_queue={@selected_queue}
              count={Map.fetch!(@queue_counts, queue)}
            />
          </div>
        </div>

        <div :if={@bids_empty?} class="p-6 sm:p-7">
          <.empty_state
            icon="hero-document-text"
            title={"No #{queue_label(@selected_queue)} bids"}
            description={empty_description(@selected_queue)}
          />
        </div>

        <div :if={!@bids_empty?} class="overflow-x-auto">
          <table class="min-w-full divide-y divide-zinc-200 text-sm dark:divide-white/10">
            <thead class="bg-zinc-50 dark:bg-white/[0.03]">
              <tr>
                <th class="px-5 py-3 text-left font-medium text-zinc-500 dark:text-zinc-400">
                  Bid
                </th>
                <th class="px-5 py-3 text-left font-medium text-zinc-500 dark:text-zinc-400">
                  Score
                </th>
                <th class="px-5 py-3 text-left font-medium text-zinc-500 dark:text-zinc-400">
                  Agency
                </th>
                <th class="px-5 py-3 text-left font-medium text-zinc-500 dark:text-zinc-400">
                  Due
                </th>
                <th class="px-5 py-3 text-left font-medium text-zinc-500 dark:text-zinc-400">
                  Status
                </th>
                <th class="px-5 py-3 text-left font-medium text-zinc-500 dark:text-zinc-400">
                  Actions
                </th>
              </tr>
            </thead>
            <tbody id="bids" phx-update="stream" class="divide-y divide-zinc-200 dark:divide-white/10">
              <tr :for={{dom_id, bid} <- @streams.bids} id={dom_id}>
                <td class="px-5 py-4 align-top">
                  <div class="space-y-1">
                    <.link
                      navigate={~p"/procurement/bids/#{bid}"}
                      class="font-medium text-zinc-900 hover:text-emerald-600 dark:text-white"
                    >
                      {bid.title}
                    </.link>
                    <div :if={bid.score_icp_matches != []} class="flex max-w-[320px] flex-wrap gap-1">
                      <span
                        :for={match <- Enum.take(bid.score_icp_matches || [], 2)}
                        class="badge badge-success badge-xs"
                      >
                        {match}
                      </span>
                    </div>
                    <p :if={bid.score_recommendation} class="max-w-[360px] text-xs text-zinc-500">
                      {short_recommendation(bid.score_recommendation)}
                    </p>
                  </div>
                </td>
                <td class="px-5 py-4 align-top">
                  <div class="space-y-2">
                    <span class={score_color(bid.score_total)}>{bid.score_total || "-"}</span>
                    <div>
                      <span class={tier_badge(bid.score_tier)}>{format_tier(bid.score_tier)}</span>
                    </div>
                  </div>
                </td>
                <td class="px-5 py-4 align-top text-zinc-600 dark:text-zinc-300">
                  <div class="space-y-1">
                    <p>{bid.agency || "-"}</p>
                    <p class="text-xs text-zinc-400 dark:text-zinc-500">
                      {format_region(bid.region)}
                    </p>
                  </div>
                </td>
                <td class="px-5 py-4 align-top text-zinc-600 dark:text-zinc-300">
                  {format_date(bid.due_at)}
                </td>
                <td class="px-5 py-4 align-top">
                  <div class="space-y-2">
                    <.status_badge status={bid.status_variant}>
                      {format_status(bid.status)}
                    </.status_badge>
                    <.link
                      :if={bid.signal}
                      navigate={~p"/commercial/signals/#{bid.signal}"}
                      class="block text-xs font-medium text-emerald-600 hover:text-emerald-500 dark:text-emerald-300"
                    >
                      Open Signal
                    </.link>
                  </div>
                </td>
                <td class="px-5 py-4 align-top">
                  <div class="flex max-w-[240px] flex-wrap gap-2">
                    <.button
                      :for={action <- bid_actions(bid)}
                      id={"bid-action-#{action.action}-#{bid.id}"}
                      phx-click={action_click(action.kind)}
                      phx-value-id={bid.id}
                      phx-value-action={action.action}
                      class="px-2.5 py-1.5 text-xs"
                      variant={action.variant}
                    >
                      <.icon name={action.icon} class="size-4" /> {action.label}
                    </.button>
                  </div>
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </.section>

      <dialog
        :if={@action_dialog && @action_dialog.type == :pass}
        id="bid-index-pass-dialog"
        class="modal"
        phx-hook="ShowModal"
      >
        <div class="modal-box">
          <h3 class="font-bold text-lg mb-2">Pass on this bid?</h3>
          <p class="text-sm text-zinc-500 mb-4">{@action_dialog.title}</p>
          <form id="bid-index-pass-form" phx-submit="submit_pass">
            <div class="space-y-3">
              <.input
                name="reason"
                value=""
                label="Why are we passing?"
                type="select"
                prompt="Select a reason..."
                options={[
                  {"Not in our service area", "Not in our service area"},
                  {"Too large / out of scope", "Too large / out of scope"},
                  {"Too small / not worth it", "Too small / not worth it"},
                  {"Wrong industry", "Wrong industry"},
                  {"No capacity right now", "No capacity right now"},
                  {"Already pursuing similar", "Already pursuing similar"},
                  {"Not a fit", "Not a fit"},
                  {"Other", "Other"}
                ]}
                required
              />
              <.input
                name="feedback_scope"
                value=""
                label="Teach the search/profile (optional)"
                type="select"
                prompt="Just pass this bid"
                options={[
                  {"Out of scope for us", "out_of_scope"},
                  {"Not targeting this type right now", "not_targeting_right_now"}
                ]}
              />
              <.input
                name="exclude_terms"
                value={@action_dialog.suggested_terms}
                label="Keywords to suppress next time"
                type="text"
                placeholder="e.g. cctv, video surveillance, security camera"
              />
              <p class="text-xs text-zinc-500">
                When set, these terms are added to the active company profile mode so similar bids stop surfacing in the live queue.
              </p>
            </div>
            <div class="modal-action">
              <button type="button" phx-click="close_dialog" class="btn btn-ghost">Cancel</button>
              <.button
                type="submit"
                class="rounded-md bg-red-600 px-3 py-2 text-sm font-semibold text-white shadow-xs hover:bg-red-500"
                phx-disable-with="Passing..."
              >
                Confirm Pass
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
        id="bid-index-park-dialog"
        class="modal"
        phx-hook="ShowModal"
      >
        <div class="modal-box">
          <h3 class="font-bold text-lg mb-2">Park for later</h3>
          <p class="text-sm text-zinc-500 mb-4">{@action_dialog.title}</p>
          <form id="bid-index-park-form" phx-submit="submit_park">
            <div class="space-y-3">
              <.input
                name="reason"
                value=""
                label="Why are we parking this?"
                type="select"
                prompt="Select a reason..."
                options={[
                  {"Need to build capability first", "Need to build capability first"},
                  {"Need a partner / subcontractor", "Need a partner / subcontractor"},
                  {"Timing — too busy right now", "Timing — too busy right now"},
                  {"Need more information", "Need more information"},
                  {"Waiting on external factor", "Waiting on external factor"},
                  {"Interesting but low priority", "Interesting but low priority"},
                  {"Other", "Other"}
                ]}
                required
              />
              <.input
                name="research"
                value=""
                label="Research needed (optional)"
                type="textarea"
                placeholder="e.g., Research cybersecurity partnerships, look into NIST compliance"
              />
            </div>
            <div class="modal-action">
              <button type="button" phx-click="close_dialog" class="btn btn-ghost">Cancel</button>
              <.button
                type="submit"
                class="rounded-md bg-amber-500 px-3 py-2 text-sm font-semibold text-zinc-950 shadow-xs hover:bg-amber-400"
                phx-disable-with="Parking..."
              >
                Park
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

  attr :queue, :atom, required: true
  attr :selected_queue, :atom, required: true
  attr :count, :integer, required: true

  defp queue_link(assigns) do
    selected? = assigns.queue == assigns.selected_queue

    assigns =
      assign(assigns,
        selected?: selected?,
        label: queue_label(assigns.queue)
      )

    ~H"""
    <.link
      patch={~p"/procurement/bids?queue=#{@queue}"}
      class={[
        "inline-flex items-center gap-2 rounded-full border px-3 py-1.5 text-sm font-medium transition",
        if(
          @selected?,
          do: "border-emerald-500 bg-emerald-500 text-white shadow-sm shadow-emerald-500/25",
          else:
            "border-zinc-200 bg-white text-zinc-600 hover:border-emerald-300 hover:text-emerald-600 dark:border-white/10 dark:bg-white/[0.03] dark:text-zinc-300 dark:hover:border-emerald-400/40 dark:hover:text-emerald-300"
        )
      ]}
    >
      <span>{@label}</span>
      <span class={[
        "inline-flex min-w-6 items-center justify-center rounded-full px-1.5 py-0.5 text-xs",
        if(@selected?,
          do: "bg-white/20 text-white",
          else: "bg-zinc-100 text-zinc-500 dark:bg-white/10 dark:text-zinc-300"
        )
      ]}>
        {@count}
      </span>
    </.link>
    """
  end

  defp load_bids_for_queue(:review, actor),
    do: load_bids(fn -> Procurement.list_review_bids(actor: actor, load: bid_loads()) end)

  defp load_bids_for_queue(:active, actor),
    do: load_bids(fn -> Procurement.list_active_bids(actor: actor, load: bid_loads()) end)

  defp load_bids_for_queue(:parked, actor),
    do: load_bids(fn -> Procurement.list_parked_bids(actor: actor, load: bid_loads()) end)

  defp load_bids_for_queue(:rejected, actor),
    do: load_bids(fn -> Procurement.list_rejected_bids(actor: actor, load: bid_loads()) end)

  defp load_bids_for_queue(:closed, actor),
    do: load_bids(fn -> Procurement.list_closed_bids(actor: actor, load: bid_loads()) end)

  defp load_bids(fun) do
    case fun.() do
      {:ok, bids} -> bids
      {:error, error} -> raise "failed to load bids: #{inspect(error)}"
    end
  end

  defp load_queue_counts(actor) do
    @queues
    |> Enum.map(fn queue -> {queue, queue |> load_bids_for_queue(actor) |> length()} end)
    |> Map.new()
  end

  defp refresh_backlog(socket) do
    bids = load_bids_for_queue(socket.assigns.selected_queue, socket.assigns.current_user)
    queue_counts = load_queue_counts(socket.assigns.current_user)

    socket
    |> assign(:queue_counts, queue_counts)
    |> assign(:bids_empty?, bids == [])
    |> stream(:bids, bids, reset: true)
  end

  defp bid_loads do
    [:signal, :status_variant]
  end

  defp parse_queue(nil), do: :review

  defp parse_queue(queue) when is_binary(queue) do
    queue
    |> String.to_existing_atom()
    |> then(fn queue_atom -> if queue_atom in @queues, do: queue_atom, else: :review end)
  rescue
    ArgumentError -> :review
  end

  defp queue_label(:review), do: "Review"
  defp queue_label(:active), do: "Active"
  defp queue_label(:parked), do: "Parked"
  defp queue_label(:rejected), do: "Rejected"
  defp queue_label(:closed), do: "Closed"

  defp empty_description(:review),
    do: "New and reviewing bids will appear here until they are advanced, parked, or rejected."

  defp empty_description(:active),
    do: "Bids in pursuing or submitted states will appear here."

  defp empty_description(:parked),
    do: "Deferred bids stay here so they are easy to reopen later."

  defp empty_description(:rejected),
    do: "Rejected bids stay visible here so scoring and sourcing can learn from misses."

  defp empty_description(:closed),
    do: "Won, lost, and expired bids stay here as procurement history."

  defp zero_counts do
    %{review: 0, active: 0, parked: 0, rejected: 0, closed: 0}
  end

  defp score_color(nil), do: "opacity-50"
  defp score_color(score) when score >= 80, do: "text-success font-bold"
  defp score_color(score) when score >= 50, do: "text-warning font-semibold"
  defp score_color(_), do: "opacity-70"

  defp tier_badge(nil), do: "badge badge-ghost badge-sm"
  defp tier_badge(:hot), do: "badge badge-error badge-sm"
  defp tier_badge(:warm), do: "badge badge-warning badge-sm"
  defp tier_badge(:prospect), do: "badge badge-info badge-sm"
  defp tier_badge(_), do: "badge badge-ghost badge-sm"

  defp format_tier(nil), do: "-"
  defp format_tier(tier), do: tier |> to_string() |> String.upcase()

  defp format_status(nil), do: "new"
  defp format_status(status), do: status |> to_string() |> String.replace("_", " ")

  defp format_region(nil), do: "-"
  defp format_region(region), do: region |> to_string() |> String.upcase()

  defp format_date(nil), do: "-"
  defp format_date(datetime), do: Calendar.strftime(datetime, "%b %d, %Y")

  defp short_recommendation(nil), do: nil

  defp short_recommendation(recommendation) when is_binary(recommendation) do
    recommendation
    |> String.split(".")
    |> List.first()
    |> case do
      nil -> nil
      "" -> recommendation
      headline -> headline <> "."
    end
  end

  defp bid_actions(%{status: :new}) do
    [
      %{
        action: "start_review",
        label: "Start Review",
        icon: "hero-eye",
        variant: nil,
        kind: :direct
      },
      %{
        action: "open_signal",
        label: "Open Signal",
        icon: "hero-inbox-stack",
        variant: "primary",
        kind: :direct
      },
      %{action: "park", label: "Park", icon: "hero-pause-circle", variant: nil, kind: :dialog},
      %{action: "pass", label: "Pass", icon: "hero-x-circle", variant: nil, kind: :dialog}
    ]
  end

  defp bid_actions(%{status: :reviewing}) do
    [
      %{
        action: "open_signal",
        label: "Open Signal",
        icon: "hero-inbox-stack",
        variant: "primary",
        kind: :direct
      },
      %{action: "park", label: "Park", icon: "hero-pause-circle", variant: nil, kind: :dialog},
      %{action: "pass", label: "Pass", icon: "hero-x-circle", variant: nil, kind: :dialog}
    ]
  end

  defp bid_actions(%{status: :parked}) do
    [
      %{action: "unpark", label: "Unpark", icon: "hero-play", variant: "primary", kind: :direct},
      %{
        action: "open_signal",
        label: "Open Signal",
        icon: "hero-inbox-stack",
        variant: nil,
        kind: :direct
      }
    ]
  end

  defp bid_actions(_bid), do: []

  defp action_click(:dialog), do: "open_dialog"
  defp action_click(:direct), do: "transition"

  defp transition_bid(id, :start_review, actor), do: BidReview.start_review(id, actor)
  defp transition_bid(id, :unpark, actor), do: BidReview.unpark_bid(id, actor)

  defp queues, do: @queues
end
