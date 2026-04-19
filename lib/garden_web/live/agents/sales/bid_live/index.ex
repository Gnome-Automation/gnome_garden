defmodule GnomeGardenWeb.Agents.Sales.BidLive.Index do
  use GnomeGardenWeb, :live_view

  alias GnomeGarden.Procurement
  alias GnomeGarden.Procurement.Bid
  alias GnomeGarden.Procurement.BidReview

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
     |> assign(:action_dialog, nil)}
  end

  @impl true
  def handle_info(%{topic: "bid:" <> _}, socket) do
    {:noreply, Cinder.refresh_table(socket, "bids")}
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
        {:noreply,
         socket
         |> put_flash(:info, "Bid updated")}

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
           title: bid.title
         })}

      {:error, error} ->
        {:noreply, put_flash(socket, :error, "Could not load bid: #{inspect(error)}")}
    end
  end

  def handle_event("close_dialog", _, socket) do
    {:noreply, assign(socket, :action_dialog, nil)}
  end

  def handle_event("submit_pass", %{"reason" => reason}, socket) do
    case BidReview.pass_bid(
           socket.assigns.action_dialog.bid_id,
           reason,
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
    <div class="space-y-4">
      <div class="flex justify-end">
        <a href="/admin/agents/bid" class="btn btn-sm btn-ghost gap-1">
          Open in Admin <.icon name="hero-arrow-top-right-on-square" class="size-4" />
        </a>
      </div>

      <Cinder.collection
        id="bids"
        resource={Bid}
        actor={@current_user}
        search={[placeholder: "Search bids..."]}
      >
        <:col :let={bid} field="title" label="Title" sort search>
          <div class="space-y-1 py-1">
            <.link
              navigate={~p"/procurement/bids/#{bid}"}
              class="font-medium text-sm leading-tight max-w-[250px] break-words whitespace-normal hover:text-emerald-600"
              title={bid.title}
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
            <p :if={bid.score_recommendation} class="max-w-[320px] text-xs text-zinc-500">
              {short_recommendation(bid.score_recommendation)}
            </p>
          </div>
        </:col>
        <:col :let={bid} field="score_total" label="Score" sort>
          <span class={score_color(bid.score_total)}>{bid.score_total || "-"}</span>
        </:col>
        <:col :let={bid} field="score_tier" label="Tier" sort>
          <span class={tier_badge(bid.score_tier)}>{format_tier(bid.score_tier)}</span>
        </:col>
        <:col :let={bid} field="agency" label="Agency" search>
          <span class="max-w-[150px] truncate">{bid.agency}</span>
        </:col>
        <:col :let={bid} field="region" label="Region" sort>
          {format_region(bid.region)}
        </:col>
        <:col :let={bid} field="due_at" label="Due" sort>
          {format_date(bid.due_at)}
        </:col>
        <:col :let={bid} field="status" label="Status" sort>
          <span class={badge_class(bid.status)}>{format_status(bid.status)}</span>
        </:col>
        <:col :let={bid} label="Actions">
          <div class="flex max-w-[240px] flex-wrap gap-2 py-1">
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
        </:col>
      </Cinder.collection>

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
    </div>
    """
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

  defp badge_class(nil), do: "badge badge-ghost badge-sm"
  defp badge_class(:new), do: "badge badge-primary badge-sm"
  defp badge_class(:reviewing), do: "badge badge-info badge-sm"
  defp badge_class(:submitted), do: "badge badge-success badge-sm"
  defp badge_class(:won), do: "badge badge-success badge-sm"
  defp badge_class(:lost), do: "badge badge-error badge-sm"
  defp badge_class(:rejected), do: "badge badge-error badge-sm"
  defp badge_class(:parked), do: "badge badge-warning badge-sm"
  defp badge_class(_), do: "badge badge-ghost badge-sm"

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
end
