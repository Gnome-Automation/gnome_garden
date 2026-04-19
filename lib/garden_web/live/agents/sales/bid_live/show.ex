defmodule GnomeGardenWeb.Agents.Sales.BidLive.Show do
  use GnomeGardenWeb, :live_view

  alias GnomeGarden.CRM.PipelineEvents
  alias GnomeGarden.Commercial
  alias GnomeGarden.Procurement

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    bid = load_bid!(id, socket.assigns.current_user)

    {:ok,
     socket
     |> assign(:page_title, bid.title)
     |> assign(:bid, bid)
     |> assign(:action_dialog, nil)}
  end

  # -- Action events --

  @impl true
  def handle_event("open_pursue", _, socket) do
    case ensure_signal_for_bid(socket.assigns.bid, socket.assigns.current_user) do
      {:ok, bid, signal} ->
        {:noreply,
         socket
         |> assign(:bid, bid)
         |> put_flash(:info, "Opened the commercial signal for this bid.")
         |> push_navigate(to: ~p"/commercial/signals/#{signal}")}

      {:error, error} ->
        {:noreply, put_flash(socket, :error, "Could not open signal: #{inspect(error)}")}
    end
  end

  def handle_event("open_pass", _, socket) do
    {:noreply, assign(socket, :action_dialog, %{type: :pass})}
  end

  def handle_event("open_park", _, socket) do
    {:noreply, assign(socket, :action_dialog, %{type: :park})}
  end

  def handle_event("close_dialog", _, socket) do
    {:noreply, assign(socket, :action_dialog, nil)}
  end

  def handle_event("submit_pass", %{"reason" => reason}, socket) do
    bid = socket.assigns.bid
    actor = socket.assigns.current_user

    case Procurement.reject_bid(bid, %{notes: reason}, actor: actor) do
      {:ok, rejected_bid} ->
        maybe_reject_signal(bid.signal, reason, actor)

        PipelineEvents.log(
          %{
            event_type: :passed,
            subject_type: "bid",
            subject_id: bid.id,
            summary: "Passed on #{bid.title}",
            reason: reason,
            from_state: to_string(bid.status),
            to_state: "rejected",
            actor_id: actor && actor.id
          },
          actor: actor
        )

        {:noreply,
         socket
         |> assign(:bid, load_bid!(rejected_bid.id, actor))
         |> put_flash(:info, "Passed — #{bid.title}")
         |> push_navigate(to: ~p"/procurement/bids")}

      {:error, error} ->
        {:noreply, put_flash(socket, :error, "Could not pass bid: #{inspect(error)}")}
    end
  end

  def handle_event("submit_park", params, socket) do
    bid = socket.assigns.bid
    reason = params["reason"]
    research_note = params["research"]
    actor = socket.assigns.current_user

    case Procurement.park_bid(bid, %{notes: reason}, actor: actor) do
      {:ok, parked_bid} ->
        maybe_archive_signal(bid.signal, actor)

        {:ok, event} =
          PipelineEvents.log(
            %{
              event_type: :parked,
              subject_type: "bid",
              subject_id: bid.id,
              summary: "Parked — #{bid.title}",
              reason: reason,
              from_state: to_string(bid.status),
              to_state: "parked",
              actor_id: actor && actor.id
            },
            actor: actor
          )

        if research_note && research_note != "" do
          {:ok, research} =
            Ash.create(GnomeGarden.Sales.ResearchRequest, %{
              research_type: :qualification,
              priority: :normal,
              notes: research_note,
              researchable_type: "bid",
              researchable_id: bid.id
            })

          Ash.create!(GnomeGarden.Sales.ResearchLink, %{
            research_request_id: research.id,
            bid_id: bid.id,
            event_id: event.id,
            context: reason
          })
        end

        {:noreply,
         socket
         |> assign(:bid, load_bid!(parked_bid.id, actor))
         |> put_flash(:info, "Parked — #{bid.title}")
         |> push_navigate(to: ~p"/procurement/bids")}

      {:error, error} ->
        {:noreply, put_flash(socket, :error, "Could not park bid: #{inspect(error)}")}
    end
  end

  def handle_event("delete_bid", _, socket) do
    Ash.destroy!(socket.assigns.bid)

    {:noreply,
     socket
     |> put_flash(:info, "Deleted")
     |> push_navigate(to: ~p"/procurement/bids")}
  end

  def handle_event("unpark", _, socket) do
    actor = socket.assigns.current_user

    case Procurement.unpark_bid(socket.assigns.bid, actor: actor) do
      {:ok, bid} ->
        maybe_reopen_signal(socket.assigns.bid.signal, actor)

        {:noreply,
         socket
         |> assign(:bid, load_bid!(bid.id, actor))
         |> put_flash(:info, "Unparked — back in review")}

      {:error, error} ->
        {:noreply, put_flash(socket, :error, "Could not unpark bid: #{inspect(error)}")}
    end
  end

  # -- Render --

  @impl true
  def render(assigns) do
    ~H"""
    <.header>
      <.status_badge status={@bid.score_tier_variant}>{format_tier(@bid.score_tier)}</.status_badge>
      {@bid.title}
      <:subtitle :if={@bid.agency}>{@bid.agency}</:subtitle>
      <:actions>
        <.button navigate={~p"/procurement/bids"}>
          <.icon name="hero-arrow-left" class="size-4" /> Back
        </.button>
        <.button
          :if={List.first(@bid.pursuits)}
          navigate={~p"/commercial/pursuits/#{List.first(@bid.pursuits)}"}
        >
          <.icon name="hero-arrow-trending-up" class="size-4" /> Pursuit
        </.button>
        <.button :if={@bid.signal} navigate={~p"/commercial/signals/#{@bid.signal}"}>
          <.icon name="hero-inbox-stack" class="size-4" /> Signal
        </.button>
      </:actions>
    </.header>

    <div
      id="bid-summary-card"
      class="mt-4 rounded-2xl border border-zinc-200 bg-zinc-50/70 p-4 dark:border-white/10 dark:bg-white/[0.03]"
    >
      <div class="flex flex-col gap-3 lg:flex-row lg:items-start lg:justify-between">
        <div class="space-y-2">
          <div :if={@bid.description} class="space-y-1">
            <div class="text-xs font-semibold uppercase tracking-wide text-zinc-500">
              Description
            </div>
            <p class="text-sm whitespace-pre-wrap text-zinc-700 dark:text-zinc-200">
              {@bid.description}
            </p>
          </div>
          <div :if={!@bid.description} class="text-sm text-zinc-500">
            No description captured for this bid yet.
          </div>
        </div>

        <div class="shrink-0">
          <a
            :if={@bid.url}
            href={@bid.url}
            target="_blank"
            class="btn btn-sm btn-primary gap-1"
          >
            <.icon name="hero-arrow-top-right-on-square" class="size-4" /> Open Original Listing
          </a>
        </div>
      </div>
    </div>

    <%!-- Action bar --%>
    <div class="mt-4 flex items-center gap-2">
      <.status_badge status={@bid.status_variant}>
        {format_atom(@bid.status)}
      </.status_badge>
      <span :if={@bid.notes && @bid.status not in [:new, :reviewing]} class="text-sm text-zinc-500">
        {@bid.notes}
      </span>

      <div :if={@bid.status in [:new, :reviewing]} class="ml-auto">
        <div class="dropdown dropdown-end">
          <div tabindex="0" role="button" class="btn btn-sm btn-ghost btn-square">
            <.icon name="hero-ellipsis-vertical" class="size-5" />
          </div>
          <ul
            tabindex="0"
            class="dropdown-content z-[1] menu p-2 shadow-lg bg-base-100 rounded-box w-48 border border-base-200"
          >
            <li>
              <button phx-click="open_pursue" class="text-success font-semibold">
                <.icon name="hero-inbox-stack" class="size-4" /> Open Signal
              </button>
            </li>
            <li>
              <button phx-click="open_park" class="text-warning">
                <.icon name="hero-pause-circle" class="size-4" /> Park for later
              </button>
            </li>
            <li>
              <button phx-click="open_pass" class="text-error">
                <.icon name="hero-x-circle" class="size-4" /> Pass
              </button>
            </li>
            <div class="divider my-0" />
            <li>
              <button
                phx-click="delete_bid"
                data-confirm="Delete this bid permanently?"
                class="text-error/50"
              >
                <.icon name="hero-trash" class="size-4" /> Delete
              </button>
            </li>
          </ul>
        </div>
      </div>

      <div :if={@bid.status == :parked} class="ml-auto">
        <button phx-click="unpark" class="btn btn-sm btn-outline">
          <.icon name="hero-play" class="size-4" /> Unpark
        </button>
      </div>
    </div>

    <div class="mt-6 grid grid-cols-1 gap-8 lg:grid-cols-3">
      <div class="lg:col-span-2 space-y-6">
        <div>
          <.heading level={3}>Bid Details</.heading>
          <.properties>
            <.property name="Agency">{@bid.agency || "-"}</.property>
            <.property name="Organization">
              <span :if={@bid.organization}>{@bid.organization.name}</span>
              <span :if={!@bid.organization}>-</span>
            </.property>
            <.property name="Location">{@bid.location || "-"}</.property>
            <.property name="Region">{format_region(@bid.region)}</.property>
            <.property name="Posted">{format_datetime(@bid.posted_at)}</.property>
            <.property name="Due">{format_datetime(@bid.due_at)}</.property>
            <.property name="Estimated Value">{format_value(@bid.estimated_value)}</.property>
            <.property name="Signal">
              <.link
                :if={@bid.signal}
                navigate={~p"/commercial/signals/#{@bid.signal}"}
                class="text-emerald-600 hover:text-emerald-500 dark:text-emerald-400"
              >
                Open signal
              </.link>
              <span :if={!@bid.signal}>-</span>
            </.property>
            <.property name="Pursuits">{Integer.to_string(length(@bid.pursuits || []))}</.property>
          </.properties>
        </div>

        <div :if={@bid.notes}>
          <.heading level={3}>Notes</.heading>
          <p class="text-sm whitespace-pre-wrap">{@bid.notes}</p>
        </div>
      </div>

      <div class="space-y-6">
        <div>
          <.heading level={3}>Score Breakdown</.heading>
          <div class="text-3xl font-bold mb-2">
            <span class={score_color(@bid.score_total)}>{@bid.score_total}</span>
            <span class="text-sm font-normal opacity-50">/ 100</span>
          </div>
          <div
            :if={@bid.score_recommendation}
            id="bid-score-recommendation"
            class="mb-4 rounded-xl border border-emerald-200 bg-emerald-50/70 px-3 py-3 text-sm text-emerald-900 dark:border-emerald-400/20 dark:bg-emerald-400/10 dark:text-emerald-100"
          >
            <div class="mb-1 text-xs font-semibold uppercase tracking-wide text-emerald-700 dark:text-emerald-300">
              Recommendation
            </div>
            <p>{@bid.score_recommendation}</p>
          </div>
          <div class="space-y-2 text-sm">
            <.score_bar label="Service Match" value={@bid.score_service_match} max={30} />
            <.score_bar label="Geography" value={@bid.score_geography} max={20} />
            <.score_bar label="Value" value={@bid.score_value} max={20} />
            <.score_bar label="Tech Fit" value={@bid.score_tech_fit} max={15} />
            <.score_bar label="Industry" value={@bid.score_industry} max={10} />
            <.score_bar label="Opp Type" value={@bid.score_opportunity_type} max={5} />
          </div>
        </div>

        <div
          :if={@bid.score_icp_matches != [] or @bid.score_risk_flags != []}
          class="grid gap-4 sm:grid-cols-2"
        >
          <div :if={@bid.score_icp_matches != []} id="bid-score-icp">
            <.heading level={3}>Why It Fits</.heading>
            <div class="flex flex-wrap gap-1">
              <span :for={match <- @bid.score_icp_matches} class="badge badge-success badge-sm">
                {match}
              </span>
            </div>
          </div>

          <div :if={@bid.score_risk_flags != []} id="bid-score-risks">
            <.heading level={3}>Risk Flags</.heading>
            <div class="flex flex-wrap gap-1">
              <span :for={flag <- @bid.score_risk_flags} class="badge badge-error badge-sm">
                {flag}
              </span>
            </div>
          </div>
        </div>

        <div :if={score_context_present?(@bid)}>
          <.heading level={3}>Scoring Context</.heading>
          <.properties>
            <.property :if={@bid.score_company_profile_mode} name="Profile Mode">
              {format_profile_mode(@bid.score_company_profile_mode)}
            </.property>
            <.property :if={@bid.score_company_profile_key} name="Profile Key">
              {@bid.score_company_profile_key}
            </.property>
            <.property :if={@bid.score_source_confidence} name="Source Confidence">
              {format_source_confidence(@bid.score_source_confidence)}
            </.property>
          </.properties>
        </div>

        <div :if={@bid.keywords_matched != []}>
          <.heading level={3}>Keywords Matched</.heading>
          <div class="flex flex-wrap gap-1">
            <span :for={kw <- @bid.keywords_matched} class="badge badge-success badge-sm">
              {kw}
            </span>
          </div>
        </div>

        <div :if={@bid.keywords_rejected != []}>
          <.heading level={3}>Keywords Rejected</.heading>
          <div class="flex flex-wrap gap-1">
            <span :for={kw <- @bid.keywords_rejected} class="badge badge-error badge-sm">
              {kw}
            </span>
          </div>
        </div>

        <div>
          <.heading level={3}>Dates</.heading>
          <.properties>
            <.property name="Discovered">{format_datetime(@bid.discovered_at)}</.property>
            <.property name="Created">{format_datetime(@bid.inserted_at)}</.property>
          </.properties>
        </div>

        <div>
          <.heading level={3}>Commercial Follow-Up</.heading>
          <div :if={Enum.empty?(@bid.pursuits || [])} class="text-sm text-zinc-500">
            No pursuits yet. Review the linked signal when someone is ready to own this bid.
          </div>
          <div :if={!Enum.empty?(@bid.pursuits || [])} class="space-y-2">
            <.link
              :for={pursuit <- @bid.pursuits}
              navigate={~p"/commercial/pursuits/#{pursuit}"}
              class="flex items-center justify-between rounded-xl border border-zinc-200 bg-zinc-50/70 px-3 py-3 transition hover:border-emerald-300 hover:bg-white dark:border-white/10 dark:bg-white/[0.03] dark:hover:border-emerald-400/40"
            >
              <span class="font-medium text-zinc-900 dark:text-white">{pursuit.name}</span>
              <.status_badge status={pursuit.stage_variant}>
                {format_atom(pursuit.stage)}
              </.status_badge>
            </.link>
          </div>
        </div>
      </div>
    </div>

    <%!-- Pass dialog --%>
    <dialog
      :if={@action_dialog && @action_dialog.type == :pass}
      id="bid-pass-dialog"
      class="modal"
      phx-hook="ShowModal"
    >
      <div class="modal-box">
        <h3 class="font-bold text-lg mb-2">Pass on this bid?</h3>
        <p class="text-sm text-zinc-500 mb-4">{@bid.title}</p>
        <form id="pass-form" phx-submit="submit_pass">
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

    <%!-- Park dialog --%>
    <dialog
      :if={@action_dialog && @action_dialog.type == :park}
      id="bid-park-dialog"
      class="modal"
      phx-hook="ShowModal"
    >
      <div class="modal-box">
        <h3 class="font-bold text-lg mb-2">Park for later</h3>
        <p class="text-sm text-zinc-500 mb-4">{@bid.title}</p>
        <form id="park-form" phx-submit="submit_park">
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
    """
  end

  # -- Components --

  attr :label, :string, required: true
  attr :value, :integer, required: true
  attr :max, :integer, required: true

  defp score_bar(assigns) do
    pct = if assigns.max > 0, do: (assigns.value || 0) / assigns.max * 100, else: 0
    assigns = assign(assigns, :pct, pct)

    ~H"""
    <div class="flex items-center gap-2">
      <span class="w-24 text-zinc-500">{@label}</span>
      <div class="flex-1 bg-base-200 rounded-full h-2">
        <div class={["h-2 rounded-full", bar_color(@pct)]} style={"width: #{@pct}%"}></div>
      </div>
      <span class="w-8 text-right font-mono">{@value || 0}</span>
    </div>
    """
  end

  # -- Helpers --

  defp bar_color(pct) when pct >= 75, do: "bg-success"
  defp bar_color(pct) when pct >= 50, do: "bg-warning"
  defp bar_color(_), do: "bg-error"

  defp format_tier(nil), do: "-"
  defp format_tier(tier), do: tier |> to_string() |> String.upcase()

  defp score_color(nil), do: "opacity-50"
  defp score_color(score) when score >= 75, do: "text-success"
  defp score_color(score) when score >= 50, do: "text-warning"
  defp score_color(_), do: "text-error"

  defp format_atom(nil), do: "-"
  defp format_atom(atom), do: atom |> to_string() |> String.replace("_", " ")

  defp format_region(nil), do: "-"
  defp format_region(region), do: region |> to_string() |> String.upcase()

  defp format_profile_mode(nil), do: "-"

  defp format_profile_mode(mode) do
    mode
    |> to_string()
    |> String.replace("_", " ")
  end

  defp format_source_confidence(nil), do: "-"

  defp format_source_confidence(confidence) do
    confidence
    |> to_string()
    |> String.replace("_", " ")
  end

  defp format_datetime(nil), do: "-"
  defp format_datetime(dt), do: Calendar.strftime(dt, "%b %d, %Y %H:%M")

  defp format_value(nil), do: "-"
  defp format_value(val), do: "$#{Decimal.round(val, 0) |> Decimal.to_string()}"

  defp score_context_present?(bid) do
    not is_nil(bid.score_company_profile_mode) or
      not is_nil(bid.score_company_profile_key) or
      not is_nil(bid.score_source_confidence)
  end

  defp load_bid!(id, actor) do
    Procurement.get_bid!(
      id,
      actor: actor,
      load: [
        :organization,
        :signal,
        :status_variant,
        :score_tier_variant,
        pursuits: [:stage_variant]
      ]
    )
  end

  defp ensure_signal_for_bid(%{signal: signal} = bid, _actor) when not is_nil(signal),
    do: {:ok, bid, signal}

  defp ensure_signal_for_bid(bid, actor) do
    with {:ok, signal} <- Commercial.create_signal_from_bid(bid.id, actor: actor),
         refreshed_bid <- load_bid!(bid.id, actor) do
      {:ok, refreshed_bid, signal}
    end
  end

  defp maybe_reject_signal(nil, _reason, _actor), do: :ok

  defp maybe_reject_signal(signal, reason, actor) when signal.status in [:new, :reviewing] do
    case Commercial.reject_signal(signal, %{notes: reason}, actor: actor) do
      {:ok, _signal} -> :ok
      {:error, _error} -> :ok
    end
  end

  defp maybe_reject_signal(_signal, _reason, _actor), do: :ok

  defp maybe_archive_signal(nil, _actor), do: :ok

  defp maybe_archive_signal(signal, actor)
       when signal.status in [:new, :reviewing, :accepted] do
    case Commercial.archive_signal(signal, actor: actor) do
      {:ok, _signal} -> :ok
      {:error, _error} -> :ok
    end
  end

  defp maybe_archive_signal(_signal, _actor), do: :ok

  defp maybe_reopen_signal(nil, _actor), do: :ok

  defp maybe_reopen_signal(signal, actor) when signal.status in [:archived, :rejected] do
    case Commercial.reopen_signal(signal, actor: actor) do
      {:ok, _signal} -> :ok
      {:error, _error} -> :ok
    end
  end

  defp maybe_reopen_signal(_signal, _actor), do: :ok
end
