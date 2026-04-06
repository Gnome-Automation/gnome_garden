defmodule GnomeGardenWeb.Agents.Sales.BidLive.Show do
  use GnomeGardenWeb, :live_view

  alias GnomeGarden.Agents
  alias GnomeGarden.Agents.Bid
  alias GnomeGarden.Sales

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    bid = Agents.get_bid!(id, actor: socket.assigns.current_user)

    {:ok,
     socket
     |> assign(:page_title, bid.title)
     |> assign(:bid, bid)
     |> assign(:action_dialog, nil)}
  end

  # -- Action events --

  @impl true
  def handle_event("open_pursue", _, socket) do
    bid = socket.assigns.bid

    company_name =
      if bid.agency_company_id do
        case Ash.get(GnomeGarden.Sales.Company, bid.agency_company_id) do
          {:ok, company} -> company.name
          _ -> bid.agency || bid.title
        end
      else
        bid.agency || bid.title
      end

    {:noreply,
     assign(socket, :action_dialog, %{
       type: :pursue,
       prefill: %{
         "company_name" => company_name,
         "company_linked" => bid.agency_company_id != nil,
         "name" => bid.title,
         "workflow" => "bid_response",
         "source" => "bid",
         "amount" => bid.estimated_value && Decimal.to_string(bid.estimated_value),
         "description" => bid.description
       }
     })}
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

  def handle_event("submit_pursue", params, socket) do
    bid = socket.assigns.bid

    pursue_params = %{
      company_name: params["company_name"],
      opportunity_name: params["name"],
      workflow: String.to_existing_atom(params["workflow"]),
      source: String.to_existing_atom(params["source"]),
      reason: params["reason"],
      description: params["description"],
      amount: parse_amount(params["amount"]),
      expected_close_date: parse_date(params["expected_close_date"]),
      region: bid.region,
      bid_id: bid.id
    }

    case Sales.accept_review_item(pursue_params, actor: socket.assigns.current_user) do
      {:ok, %{opportunity: opp}} ->
        {:noreply,
         socket
         |> put_flash(:info, "Now pursuing — #{opp.name}")
         |> push_navigate(to: ~p"/crm/opportunities/#{opp}")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed: #{inspect(reason)}")}
    end
  end

  def handle_event("submit_pass", %{"reason" => reason}, socket) do
    bid = socket.assigns.bid
    Ash.update!(bid, %{notes: reason}, action: :reject)

    Sales.log_pipeline_event(%{
      event_type: :passed,
      subject_type: "bid",
      subject_id: bid.id,
      summary: "Passed on #{bid.title}",
      reason: reason,
      from_state: to_string(bid.status),
      to_state: "rejected",
      actor_id: socket.assigns.current_user && socket.assigns.current_user.id
    })

    {:noreply,
     socket
     |> put_flash(:info, "Passed — #{bid.title}")
     |> push_navigate(to: ~p"/agents/sales/bids")}
  end

  def handle_event("submit_park", params, socket) do
    bid = socket.assigns.bid
    reason = params["reason"]
    research_note = params["research"]

    Ash.update!(bid, %{notes: reason}, action: :park)

    {:ok, event} =
      Sales.log_pipeline_event(%{
        event_type: :parked,
        subject_type: "bid",
        subject_id: bid.id,
        summary: "Parked — #{bid.title}",
        reason: reason,
        from_state: to_string(bid.status),
        to_state: "parked",
        actor_id: socket.assigns.current_user && socket.assigns.current_user.id
      })

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
     |> put_flash(:info, "Parked — #{bid.title}")
     |> push_navigate(to: ~p"/agents/sales/bids")}
  end

  def handle_event("delete_bid", _, socket) do
    Ash.destroy!(socket.assigns.bid)

    {:noreply,
     socket
     |> put_flash(:info, "Deleted")
     |> push_navigate(to: ~p"/agents/sales/bids")}
  end

  def handle_event("unpark", _, socket) do
    {:ok, bid} = Ash.update(socket.assigns.bid, %{}, action: :unpark)

    {:noreply,
     socket
     |> assign(:bid, bid)
     |> put_flash(:info, "Unparked — back in review")}
  end

  # -- Render --

  @impl true
  def render(assigns) do
    ~H"""
    <.header>
      <span class={tier_badge(@bid.score_tier)}>{format_tier(@bid.score_tier)}</span>
      {@bid.title}
      <:subtitle :if={@bid.agency}>{@bid.agency}</:subtitle>
      <:actions>
        <.button navigate={~p"/agents/sales/bids"}>
          <.icon name="hero-arrow-left" class="size-4" /> Back
        </.button>
        <a :if={@bid.url} href={@bid.url} target="_blank" class="btn btn-sm btn-primary gap-1">
          <.icon name="hero-arrow-top-right-on-square" class="size-4" /> View Original
        </a>
      </:actions>
    </.header>

    <%!-- Action bar --%>
    <div class="mt-4 flex items-center gap-2">
      <span class={["badge", bid_status_class(@bid.status)]}>
        {format_atom(@bid.status)}
      </span>
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
                <.icon name="hero-rocket-launch" class="size-4" /> Pursue
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
            <.property name="Location">{@bid.location || "-"}</.property>
            <.property name="Region">{format_region(@bid.region)}</.property>
            <.property name="Posted">{format_datetime(@bid.posted_at)}</.property>
            <.property name="Due">{format_datetime(@bid.due_at)}</.property>
            <.property name="Estimated Value">{format_value(@bid.estimated_value)}</.property>
            <.property name="URL">
              <a
                :if={@bid.url}
                href={@bid.url}
                target="_blank"
                class="text-emerald-600 hover:text-emerald-500 dark:text-emerald-400 break-all"
              >
                {@bid.url}
              </a>
            </.property>
          </.properties>
        </div>

        <div :if={@bid.description}>
          <.heading level={3}>Description</.heading>
          <p class="text-sm whitespace-pre-wrap">{@bid.description}</p>
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
          <div class="space-y-2 text-sm">
            <.score_bar label="Service Match" value={@bid.score_service_match} max={30} />
            <.score_bar label="Geography" value={@bid.score_geography} max={20} />
            <.score_bar label="Value" value={@bid.score_value} max={20} />
            <.score_bar label="Tech Fit" value={@bid.score_tech_fit} max={15} />
            <.score_bar label="Industry" value={@bid.score_industry} max={10} />
            <.score_bar label="Opp Type" value={@bid.score_opportunity_type} max={5} />
          </div>
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
      </div>
    </div>

    <%!-- Pursue dialog --%>
    <dialog
      :if={@action_dialog && @action_dialog.type == :pursue}
      id="bid-pursue-dialog"
      class="modal"
      phx-hook="ShowModal"
    >
      <div class="modal-box">
        <h3 class="font-bold text-lg mb-4">Pursue this opportunity</h3>
        <p class="text-sm text-zinc-500 mb-4">
          Creates an opportunity in your pipeline linked to the company.
        </p>
        <form id="pursue-form" phx-submit="submit_pursue">
          <div class="space-y-3">
            <div>
              <label class="block text-sm/6 font-medium text-gray-900 dark:text-white mb-1">
                Company
              </label>
              <div class="flex items-center gap-2">
                <span
                  :if={@action_dialog.prefill["company_linked"]}
                  class="badge badge-success badge-sm"
                >
                  linked
                </span>
                <span class="font-medium">{@action_dialog.prefill["company_name"]}</span>
              </div>
              <input type="hidden" name="company_name" value={@action_dialog.prefill["company_name"]} />
            </div>
            <.input
              name="name"
              value={@action_dialog.prefill["name"]}
              label="Opportunity Name"
              required
            />
            <div class="grid grid-cols-2 gap-3">
              <.input
                name="workflow"
                type="select"
                value={@action_dialog.prefill["workflow"]}
                label="Workflow"
                options={[
                  {"Bid Response", "bid_response"},
                  {"Outreach", "outreach"},
                  {"Inbound", "inbound"}
                ]}
              />
              <.input
                name="source"
                type="select"
                value={@action_dialog.prefill["source"]}
                label="Source"
                options={[
                  {"Bid/RFP", "bid"},
                  {"Prospect", "prospect"},
                  {"Referral", "referral"},
                  {"Inbound", "inbound"},
                  {"Outbound", "outbound"},
                  {"Other", "other"}
                ]}
              />
            </div>
            <div class="grid grid-cols-2 gap-3">
              <.input
                name="amount"
                value={@action_dialog.prefill["amount"]}
                label="Amount"
                type="number"
                step="0.01"
              />
              <.input name="expected_close_date" value="" label="Expected Close" type="date" />
            </div>
            <.input
              name="reason"
              value=""
              label="Why are we pursuing this?"
              type="select"
              prompt="Select a reason..."
              options={[
                {"Strong service match — core controls/SCADA",
                 "Strong service match — core controls/SCADA"},
                {"Strong service match — software/IT", "Strong service match — software/IT"},
                {"Good geographic fit", "Good geographic fit"},
                {"Existing relationship with agency", "Existing relationship with agency"},
                {"High value opportunity", "High value opportunity"},
                {"Strategic — new market/capability", "Strategic — new market/capability"},
                {"Low competition expected", "Low competition expected"},
                {"Referral / warm intro", "Referral / warm intro"},
                {"Other", "Other"}
              ]}
              required
            />
            <.input
              name="description"
              value={@action_dialog.prefill["description"]}
              label="Notes (optional)"
              type="textarea"
            />
          </div>
          <div class="modal-action">
            <button type="button" phx-click="close_dialog" class="btn btn-ghost">Cancel</button>
            <.button type="submit" variant="primary" phx-disable-with="Pursuing...">Pursue</.button>
          </div>
        </form>
      </div>
      <form method="dialog" class="modal-backdrop">
        <button phx-click="close_dialog">close</button>
      </form>
    </dialog>

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
            <.button type="submit" variant="error" phx-disable-with="Passing...">
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
            <.button type="submit" variant="warning" phx-disable-with="Parking...">Park</.button>
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

  defp tier_badge(:hot), do: "badge badge-error badge-lg"
  defp tier_badge(:warm), do: "badge badge-warning badge-lg"
  defp tier_badge(:prospect), do: "badge badge-info badge-lg"
  defp tier_badge(_), do: "badge badge-ghost badge-lg"

  defp format_tier(nil), do: "-"
  defp format_tier(tier), do: tier |> to_string() |> String.upcase()

  defp bid_status_class(:new), do: "badge-primary"
  defp bid_status_class(:reviewing), do: "badge-info"
  defp bid_status_class(:pursuing), do: "badge-warning"
  defp bid_status_class(:submitted), do: "badge-success"
  defp bid_status_class(:won), do: "badge-success"
  defp bid_status_class(:lost), do: "badge-error"
  defp bid_status_class(:parked), do: "badge-warning"
  defp bid_status_class(:rejected), do: "badge-ghost"
  defp bid_status_class(_), do: "badge-ghost"

  defp score_color(nil), do: "opacity-50"
  defp score_color(score) when score >= 75, do: "text-success"
  defp score_color(score) when score >= 50, do: "text-warning"
  defp score_color(_), do: "text-error"

  defp format_atom(nil), do: "-"
  defp format_atom(atom), do: atom |> to_string() |> String.replace("_", " ")

  defp format_region(nil), do: "-"
  defp format_region(region), do: region |> to_string() |> String.upcase()

  defp format_datetime(nil), do: "-"
  defp format_datetime(dt), do: Calendar.strftime(dt, "%b %d, %Y %H:%M")

  defp format_value(nil), do: "-"
  defp format_value(val), do: "$#{Decimal.round(val, 0) |> Decimal.to_string()}"

  defp parse_amount(nil), do: nil
  defp parse_amount(""), do: nil
  defp parse_amount(s) when is_binary(s), do: Decimal.new(s)
  defp parse_amount(d), do: d

  defp parse_date(nil), do: nil
  defp parse_date(""), do: nil
  defp parse_date(s) when is_binary(s), do: Date.from_iso8601!(s)
  defp parse_date(d), do: d
end
