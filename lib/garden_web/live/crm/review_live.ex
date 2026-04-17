defmodule GnomeGardenWeb.CRM.ReviewLive do
  use GnomeGardenWeb, :live_view

  alias GnomeGarden.CRM.Forms, as: CRMForms
  alias GnomeGarden.CRM.PipelineEvents
  alias GnomeGarden.CRM.Review
  alias GnomeGarden.Sales.Lead
  alias GnomeGarden.Agents.{Bid, Prospect}

  require Ash.Query

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      GnomeGardenWeb.Endpoint.subscribe("lead:created")
      GnomeGardenWeb.Endpoint.subscribe("bid:created")
      GnomeGardenWeb.Endpoint.subscribe("bid:scored")
      GnomeGardenWeb.Endpoint.subscribe("prospect:created")
    end

    {:ok,
     socket
     |> assign(:page_title, "Review Queue")
     |> assign(:active_tab, :all)
     |> assign(:pursue_item, nil)
     |> assign(:pursue_form, nil)
     |> assign(:pass_item, nil)
     |> assign(:park_item, nil)
     |> assign(:quick_add_open, false)
     |> assign(:quick_add_form, nil)
     |> load_items()}
  end

  @impl true
  def handle_info(%{topic: _}, socket) do
    {:noreply, load_items(socket)}
  end

  # -- Events --

  @impl true
  def handle_event("tab", %{"tab" => tab}, socket) do
    {:noreply, assign(socket, :active_tab, String.to_existing_atom(tab))}
  end

  # Pursue modal
  def handle_event("open_pursue", %{"type" => type, "id" => id}, socket) do
    {item, prefill} = load_pursue_item(type, id)

    {:noreply,
     socket
     |> assign(:pursue_item, %{type: type, record: item, prefill: prefill})}
  end

  def handle_event("close_pursue", _, socket) do
    {:noreply, assign(socket, :pursue_item, nil)}
  end

  def handle_event("submit_pursue", params, socket) do
    %{type: type, record: record} = socket.assigns.pursue_item

    pursue_params =
      %{
        company_name: params["company_name"],
        opportunity_name: params["name"],
        workflow: parse_source(params["workflow"]),
        source: parse_source(params["source"]),
        reason: params["reason"],
        description: params["description"],
        amount: parse_amount(params["amount"]),
        expected_close_date: parse_date(params["expected_close_date"]),
        region: record_region(type, record)
      }
      |> put_source_id(type, record)

    case Review.accept_review_item(pursue_params, actor: socket.assigns.current_user) do
      {:ok, %{opportunity: opp}} ->
        {:noreply,
         socket
         |> assign(:pursue_item, nil)
         |> put_flash(:info, "Now pursuing — #{opp.name}")
         |> push_navigate(to: ~p"/crm/opportunities/#{opp}")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed: #{inspect(reason)}")}
    end
  end

  # Pass — open dialog to capture reason
  def handle_event("open_pass", %{"type" => type, "id" => id}, socket) do
    {item, _prefill} = load_pursue_item(type, id)
    {:noreply, assign(socket, :pass_item, %{type: type, id: id, record: item})}
  end

  def handle_event("close_pass", _, socket) do
    {:noreply, assign(socket, :pass_item, nil)}
  end

  def handle_event("submit_pass", %{"reason" => reason}, socket) do
    %{type: type, id: id, record: record} = socket.assigns.pass_item
    title = record_title(type, record)

    # Reject the record
    case type do
      "bid" ->
        Ash.update!(record, %{notes: reason}, action: :reject)

      "lead" ->
        Ash.update!(record, %{rejection_reason: :not_a_fit, rejection_notes: reason},
          action: :reject_lead
        )

      "prospect" ->
        Ash.update!(record, %{notes: reason}, action: :reject)
    end

    # Log the pass event
    PipelineEvents.log(
      %{
        event_type: :passed,
        subject_type: type,
        subject_id: id,
        summary: "Passed on #{title}",
        reason: reason,
        from_state: "new",
        to_state: "rejected",
        actor_id: socket.assigns.current_user && socket.assigns.current_user.id
      },
      actor: socket.assigns.current_user
    )

    {:noreply,
     socket
     |> assign(:pass_item, nil)
     |> put_flash(:info, "Passed — #{title}")
     |> load_items()}
  end

  # Park — open dialog to capture reason + optional research
  def handle_event("open_park", %{"type" => type, "id" => id}, socket) do
    {item, _prefill} = load_pursue_item(type, id)
    {:noreply, assign(socket, :park_item, %{type: type, id: id, record: item})}
  end

  def handle_event("close_park", _, socket) do
    {:noreply, assign(socket, :park_item, nil)}
  end

  def handle_event("submit_park", params, socket) do
    %{type: type, id: id, record: record} = socket.assigns.park_item
    title = record_title(type, record)
    reason = params["reason"]
    research_note = params["research"]

    # Park the record
    case type do
      "bid" ->
        Ash.update!(record, %{notes: reason}, action: :park)

      "lead" ->
        Ash.update!(record, %{rejection_reason: :not_a_fit, rejection_notes: reason},
          action: :reject_lead
        )

      "prospect" ->
        Ash.update!(record, %{notes: reason}, action: :reject)
    end

    # Log the park event
    {:ok, event} =
      PipelineEvents.log(
        %{
          event_type: :parked,
          subject_type: type,
          subject_id: id,
          summary: "Parked — #{title}",
          reason: reason,
          from_state: "new",
          to_state: "parked",
          actor_id: socket.assigns.current_user && socket.assigns.current_user.id
        },
        actor: socket.assigns.current_user
      )

    # Create research request if provided
    if research_note && research_note != "" do
      {:ok, research} =
        Ash.create(GnomeGarden.Sales.ResearchRequest, %{
          research_type: :qualification,
          priority: :normal,
          notes: research_note,
          researchable_type: type,
          researchable_id: id
        })

      # Link research to the bid/event
      Ash.create!(GnomeGarden.Sales.ResearchLink, %{
        research_request_id: research.id,
        event_id: event.id,
        context: "Spawned from parking decision"
      })

      if type == "bid" do
        Ash.create!(GnomeGarden.Sales.ResearchLink, %{
          research_request_id: research.id,
          bid_id: id,
          context: reason
        })
      end
    end

    {:noreply,
     socket
     |> assign(:park_item, nil)
     |> put_flash(:info, "Parked — #{title}")
     |> load_items()}
  end

  # Delete — permanently remove item
  def handle_event("delete_item", %{"type" => type, "id" => id}, socket) do
    case type do
      "bid" -> Ash.get!(Bid, id) |> Ash.destroy!()
      "lead" -> Ash.get!(Lead, id) |> Ash.destroy!()
      "prospect" -> Ash.get!(Prospect, id) |> Ash.destroy!()
    end

    {:noreply,
     socket
     |> put_flash(:info, "Deleted")
     |> load_items()}
  end

  # Quick add
  def handle_event("toggle_quick_add", _, socket) do
    open = !socket.assigns.quick_add_open

    form =
      if open do
        CRMForms.form_to_quick_add_lead(actor: socket.assigns.current_user)
        |> then(&to_form/1)
      else
        nil
      end

    {:noreply, socket |> assign(:quick_add_open, open) |> assign(:quick_add_form, form)}
  end

  def handle_event("validate_quick_add", %{"form" => params}, socket) do
    form = AshPhoenix.Form.validate(socket.assigns.quick_add_form, params)
    {:noreply, assign(socket, :quick_add_form, to_form(form))}
  end

  def handle_event("submit_quick_add", %{"form" => params}, socket) do
    case AshPhoenix.Form.submit(socket.assigns.quick_add_form, params: params) do
      {:ok, _lead} ->
        {:noreply,
         socket
         |> assign(:quick_add_open, false)
         |> assign(:quick_add_form, nil)
         |> put_flash(:info, "Added to review queue")
         |> load_items()}

      {:error, form} ->
        {:noreply, assign(socket, :quick_add_form, to_form(form))}
    end
  end

  # -- Render --

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <.header>
        Review Queue
        <:subtitle>
          {total_count(assigns)} items to review
        </:subtitle>
        <:actions>
          <button phx-click="toggle_quick_add" class="btn btn-sm btn-primary gap-1">
            <.icon name="hero-plus" class="size-4" /> Quick Add
          </button>
        </:actions>
      </.header>

      <%!-- Quick add form --%>
      <div :if={@quick_add_open} class="card bg-base-100 shadow-sm border border-primary/20">
        <div class="card-body p-4">
          <h3 class="text-sm font-semibold mb-3">Log a new opportunity</h3>
          <.form
            for={@quick_add_form}
            id="quick-add-form"
            phx-change="validate_quick_add"
            phx-submit="submit_quick_add"
          >
            <div class="grid grid-cols-1 gap-3 sm:grid-cols-2">
              <.input field={@quick_add_form[:company_name]} label="Company / Person" required />
              <.input
                field={@quick_add_form[:source]}
                type="select"
                label="Source"
                prompt="How did you find this?"
                options={[
                  {"Referral", :referral},
                  {"Trade Show", :trade_show},
                  {"Cold Call", :cold_call},
                  {"Website", :website},
                  {"Bid", :bid},
                  {"Other", :other}
                ]}
              />
            </div>
            <div class="mt-3">
              <.input
                field={@quick_add_form[:source_details]}
                label="What's the opportunity?"
                placeholder="e.g., They need SCADA upgrades for their new facility"
              />
            </div>
            <div class="mt-3">
              <.input field={@quick_add_form[:source_url]} label="URL (optional)" type="url" />
            </div>
            <div class="flex gap-2 mt-4">
              <.button type="submit" variant="primary" phx-disable-with="Adding...">
                Add to Queue
              </.button>
              <button type="button" phx-click="toggle_quick_add" class="btn btn-sm btn-ghost">
                Cancel
              </button>
            </div>
          </.form>
        </div>
      </div>

      <%!-- Tabs --%>
      <div class="tabs tabs-boxed bg-base-200 p-1">
        <button
          :for={
            {tab, label, count} <- [
              {:all, "All", total_count(assigns)},
              {:bids, "Bids", length(@bids)},
              {:leads, "Leads", length(@leads)},
              {:prospects, "Prospects", length(@prospects)}
            ]
          }
          phx-click="tab"
          phx-value-tab={tab}
          class={["tab", @active_tab == tab && "tab-active"]}
        >
          {label}
          <span :if={count > 0} class="badge badge-sm ml-1">{count}</span>
        </button>
      </div>

      <%!-- Empty state --%>
      <div :if={items_for_tab(assigns) == []} class="text-center py-12 text-zinc-400">
        Nothing to review. The agents are working on finding new prospects.
      </div>

      <%!-- Item cards --%>
      <div class="space-y-3">
        <div :for={item <- items_for_tab(assigns)}>
          {render_card(item, assigns)}
        </div>
      </div>

      <%!-- Pursue modal — uses DaisyUI dialog to escape stacking contexts --%>
      <dialog :if={@pursue_item} id="pursue-dialog" class="modal" phx-hook="ShowModal">
        <div class="modal-box">
          <h3 class="font-bold text-lg mb-4">
            Pursue this opportunity
          </h3>
          <p class="text-sm text-zinc-500 mb-4">
            Creates a company (if new) and an opportunity in your pipeline.
          </p>
          <form id="pursue-form" phx-submit="submit_pursue">
            <div class="space-y-3">
              <.input
                name="company_name"
                value={@pursue_item.prefill["company_name"]}
                label="Company Name"
                required
              />
              <.input
                name="name"
                value={@pursue_item.prefill["name"]}
                label="Opportunity Name"
                required
              />
              <div class="grid grid-cols-2 gap-3">
                <.input
                  name="workflow"
                  type="select"
                  value={@pursue_item.prefill["workflow"]}
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
                  value={@pursue_item.prefill["source"]}
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
                  value={@pursue_item.prefill["amount"]}
                  label="Amount"
                  type="number"
                  step="0.01"
                />
                <.input
                  name="expected_close_date"
                  value=""
                  label="Expected Close"
                  type="date"
                />
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
                value={@pursue_item.prefill["description"]}
                label="Notes (optional)"
                type="textarea"
              />
            </div>
            <div class="modal-action">
              <button type="button" phx-click="close_pursue" class="btn btn-ghost">
                Cancel
              </button>
              <.button type="submit" variant="primary" phx-disable-with="Pursuing...">
                Pursue
              </.button>
            </div>
          </form>
        </div>
        <form method="dialog" class="modal-backdrop">
          <button phx-click="close_pursue">close</button>
        </form>
      </dialog>

      <%!-- Pass dialog --%>
      <dialog :if={@pass_item} id="pass-dialog" class="modal" phx-hook="ShowModal">
        <div class="modal-box">
          <h3 class="font-bold text-lg mb-2">Pass on this?</h3>
          <p class="text-sm text-zinc-500 mb-4">
            {pass_item_title(@pass_item)}
          </p>
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
              <button type="button" phx-click="close_pass" class="btn btn-ghost">
                Cancel
              </button>
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
          <button phx-click="close_pass">close</button>
        </form>
      </dialog>

      <%!-- Park dialog --%>
      <dialog :if={@park_item} id="park-dialog" class="modal" phx-hook="ShowModal">
        <div class="modal-box">
          <h3 class="font-bold text-lg mb-2">Park for later</h3>
          <p class="text-sm text-zinc-500 mb-4">
            {pass_item_title(@park_item)}
          </p>
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
              <button type="button" phx-click="close_park" class="btn btn-ghost">
                Cancel
              </button>
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
          <button phx-click="close_park">close</button>
        </form>
      </dialog>
    </div>
    """
  end

  # -- Card rendering --

  defp render_card(%{type: :bid, record: bid}, assigns) do
    assigns =
      assigns
      |> assign(:bid, bid)
      |> assign(:urgency, due_urgency(bid.due_at))

    ~H"""
    <div class={[
      "card bg-base-100 shadow-sm border",
      case @bid.score_tier do
        :hot -> "border-error/30"
        :warm -> "border-warning/30"
        _ -> "border-base-200"
      end
    ]}>
      <div class="card-body p-4">
        <div class="flex items-start justify-between gap-4">
          <div class="flex-1 min-w-0">
            <%!-- Top line: what kind + score --%>
            <div class="flex items-center gap-2 text-xs">
              <span class={tier_badge(@bid.score_tier)}>{format_tier(@bid.score_tier)}</span>
              <span :if={@bid.bid_type} class="badge badge-sm badge-ghost">
                {@bid.bid_type |> to_string() |> String.upcase()}
              </span>
              <span class="font-mono font-bold text-sm">{@bid.score_total}/100</span>
              <span :if={@urgency == :overdue} class="badge badge-sm badge-error">OVERDUE</span>
              <span :if={@urgency == :this_week} class="badge badge-sm badge-warning">DUE SOON</span>
            </div>

            <%!-- Title --%>
            <.link
              navigate={~p"/procurement/bids/#{@bid}"}
              class="font-bold text-base mt-1 block hover:text-emerald-600 truncate"
            >
              {@bid.title}
            </.link>

            <%!-- Agency + location + due --%>
            <div class="text-sm text-zinc-500 mt-1">
              <span :if={@bid.agency} class="font-medium">{@bid.agency}</span>
              <span :if={@bid.location}> —           {@bid.location}</span>
              <span :if={@bid.due_at} class="ml-2 text-zinc-400">
                Due {format_date(@bid.due_at)}
              </span>
            </div>

            <%!-- Why it matched — keywords are the key signal --%>
            <div :if={@bid.keywords_matched != []} class="flex flex-wrap gap-1 mt-2">
              <span class="text-xs text-zinc-400 mr-1">Matched:</span>
              <span
                :for={kw <- @bid.keywords_matched}
                class="badge badge-xs badge-success badge-outline"
              >
                {kw}
              </span>
            </div>

            <%!-- Score breakdown as compact bar --%>
            <div class="flex items-center gap-3 mt-2 text-xs text-zinc-400">
              <span :if={@bid.score_service_match > 0} title="Service match">
                Svc {@bid.score_service_match}/30
              </span>
              <span :if={@bid.score_geography > 0} title="Geography">
                Geo {@bid.score_geography}/20
              </span>
              <span :if={@bid.score_tech_fit > 0} title="Tech fit">
                Tech {@bid.score_tech_fit}/15
              </span>
              <span :if={@bid.score_industry > 0} title="Industry">
                Ind {@bid.score_industry}/10
              </span>
            </div>

            <%!-- Description if available --%>
            <div
              :if={@bid.description && @bid.description != ""}
              class="text-sm text-zinc-600 mt-2 line-clamp-2"
            >
              {@bid.description}
            </div>

            <%!-- Value if known --%>
            <div
              :if={@bid.estimated_value || @bid.value_range}
              class="text-sm font-medium text-emerald-700 mt-1"
            >
              {if @bid.value_range,
                do: @bid.value_range,
                else: "$#{Decimal.to_string(Decimal.round(@bid.estimated_value, 0))}"}
            </div>
          </div>
          <.card_actions type="bid" id={@bid.id} />
        </div>
      </div>
    </div>
    """
  end

  defp render_card(%{type: :lead, record: lead}, assigns) do
    assigns = assign(assigns, :lead, lead)

    ~H"""
    <div class="card bg-base-100 shadow-sm border border-base-200">
      <div class="card-body p-4">
        <div class="flex items-start justify-between gap-4">
          <div class="flex-1 min-w-0">
            <%!-- Top line: source badge --%>
            <div class="flex items-center gap-2 text-xs">
              <span :if={@lead.source} class="badge badge-sm badge-primary">
                {format_source_label(@lead.source)}
              </span>
              <span class="text-zinc-400">
                {Calendar.strftime(@lead.inserted_at, "%b %d")}
              </span>
            </div>

            <%!-- Company name is the headline --%>
            <div class="font-bold text-base mt-1">
              {@lead.company_name || lead_display_name(@lead)}
            </div>

            <%!-- The signal / opportunity description --%>
            <div :if={@lead.source_details} class="text-sm text-zinc-600 mt-1">
              {@lead.source_details}
            </div>

            <%!-- Contact if known --%>
            <div :if={@lead.first_name != "Unknown"} class="text-sm text-zinc-500 mt-1">
              Contact: {@lead.first_name} {@lead.last_name}
              <span :if={@lead.title}> —           {@lead.title}</span>
            </div>

            <%!-- Link if available --%>
            <a
              :if={@lead.source_url}
              href={@lead.source_url}
              target="_blank"
              class="text-xs text-emerald-600 hover:text-emerald-500 mt-1 inline-flex items-center gap-1"
            >
              <.icon name="hero-arrow-top-right-on-square" class="size-3" /> Source
            </a>
          </div>
          <.card_actions type="lead" id={@lead.id} />
        </div>
      </div>
    </div>
    """
  end

  defp render_card(%{type: :prospect, record: prospect}, assigns) do
    assigns = assign(assigns, :prospect, prospect)

    ~H"""
    <div class={[
      "card bg-base-100 shadow-sm border",
      case @prospect.signal_strength do
        :strong -> "border-error/30"
        :medium -> "border-warning/30"
        _ -> "border-base-200"
      end
    ]}>
      <div class="card-body p-4">
        <div class="flex items-start justify-between gap-4">
          <div class="flex-1 min-w-0">
            <%!-- Top line: industry + signal strength --%>
            <div class="flex items-center gap-2 text-xs">
              <span class={signal_badge(@prospect.signal_strength)}>
                {@prospect.signal_strength |> to_string()} signal
              </span>
              <span :if={@prospect.industry} class="badge badge-sm badge-ghost">
                {@prospect.industry |> to_string() |> String.replace("_", " ")}
              </span>
              <span :if={@prospect.region} class="text-zinc-400">
                {format_region(@prospect.region)}
              </span>
            </div>

            <%!-- Company name --%>
            <div class="font-bold text-base mt-1">{@prospect.name}</div>

            <%!-- Why we found them — signals --%>
            <div :if={@prospect.signals != []} class="mt-2">
              <span class="text-xs text-zinc-400">Signals: </span>
              <span
                :for={signal <- @prospect.signals}
                class="badge badge-xs badge-info badge-outline mr-1"
              >
                {signal |> String.replace("_", " ")}
              </span>
            </div>

            <%!-- Tech stack if known --%>
            <div :if={@prospect.tech_indicators != []} class="mt-1">
              <span class="text-xs text-zinc-400">Tech: </span>
              <span
                :for={tech <- Enum.take(@prospect.tech_indicators, 4)}
                class="badge badge-xs badge-outline mr-1"
              >
                {tech}
              </span>
            </div>

            <%!-- Location + website --%>
            <div class="flex items-center gap-3 mt-2 text-sm text-zinc-500">
              <span :if={@prospect.location}>{@prospect.location}</span>
              <a
                :if={@prospect.website}
                href={@prospect.website}
                target="_blank"
                class="text-emerald-600 hover:text-emerald-500 inline-flex items-center gap-1"
              >
                <.icon name="hero-arrow-top-right-on-square" class="size-3" />
                {URI.parse(@prospect.website).host}
              </a>
            </div>
          </div>
          <.card_actions type="prospect" id={@prospect.id} />
        </div>
      </div>
    </div>
    """
  end

  # Shared action dropdown for Pursue / Pass / Park
  attr :type, :string, required: true
  attr :id, :string, required: true

  defp card_actions(assigns) do
    ~H"""
    <div class="shrink-0">
      <div class="dropdown dropdown-end">
        <div tabindex="0" role="button" class="btn btn-sm btn-ghost btn-square">
          <.icon name="hero-ellipsis-vertical" class="size-5" />
        </div>
        <ul
          tabindex="0"
          class="dropdown-content z-[1] menu p-2 shadow-lg bg-base-100 rounded-box w-48 border border-base-200"
        >
          <li>
            <button
              phx-click="open_pursue"
              phx-value-type={@type}
              phx-value-id={@id}
              class="text-success font-semibold"
            >
              <.icon name="hero-rocket-launch" class="size-4" /> Pursue
            </button>
          </li>
          <li>
            <button
              phx-click="open_park"
              phx-value-type={@type}
              phx-value-id={@id}
              class="text-warning"
            >
              <.icon name="hero-pause-circle" class="size-4" /> Park for later
            </button>
          </li>
          <li>
            <button
              phx-click="open_pass"
              phx-value-type={@type}
              phx-value-id={@id}
              class="text-error"
            >
              <.icon name="hero-x-circle" class="size-4" /> Pass
            </button>
          </li>
          <div class="divider my-0" />
          <li>
            <button
              phx-click="delete_item"
              phx-value-type={@type}
              phx-value-id={@id}
              data-confirm="Delete this permanently?"
              class="text-error/50"
            >
              <.icon name="hero-trash" class="size-4" /> Delete
            </button>
          </li>
        </ul>
      </div>
    </div>
    """
  end

  # -- Data loading --

  defp load_items(socket) do
    bids =
      Bid
      |> Ash.Query.filter(status == :new)
      |> Ash.Query.sort(score_total: :desc, inserted_at: :desc)
      |> Ash.read!()

    leads =
      Lead
      |> Ash.Query.filter(status == :new)
      |> Ash.Query.sort(inserted_at: :desc)
      |> Ash.read!()

    prospects =
      Prospect
      |> Ash.Query.filter(status == :researched)
      |> Ash.Query.sort(inserted_at: :desc)
      |> Ash.read!()

    all_items = build_unified_items(bids, leads, prospects)

    assign(socket,
      bids: bids,
      leads: leads,
      prospects: prospects,
      all_items: all_items
    )
  end

  defp build_unified_items(bids, leads, prospects) do
    bid_items = Enum.map(bids, &%{type: :bid, record: &1, inserted_at: &1.inserted_at})
    lead_items = Enum.map(leads, &%{type: :lead, record: &1, inserted_at: &1.inserted_at})

    prospect_items =
      Enum.map(prospects, &%{type: :prospect, record: &1, inserted_at: &1.inserted_at})

    (bid_items ++ lead_items ++ prospect_items)
    |> Enum.sort_by(& &1.inserted_at, {:desc, DateTime})
  end

  # -- Pursue helpers --

  defp load_pursue_item("bid", id) do
    bid = Ash.get!(Bid, id)

    prefill = %{
      "company_name" => bid.agency || bid.title,
      "name" => bid.title,
      "workflow" => "bid_response",
      "source" => "bid",
      "amount" => bid.estimated_value && Decimal.to_string(bid.estimated_value),
      "description" => bid.description
    }

    {bid, prefill}
  end

  defp load_pursue_item("lead", id) do
    lead = Ash.get!(Lead, id)

    workflow =
      case lead.source do
        :bid -> "bid_response"
        s when s in [:referral, :trade_show, :website] -> "inbound"
        :cold_call -> "outreach"
        _ -> "inbound"
      end

    prefill = %{
      "company_name" => lead.company_name || "#{lead.first_name} #{lead.last_name}",
      "name" => "#{lead.company_name || lead.last_name} - #{lead.source_details || "New Lead"}",
      "workflow" => workflow,
      "source" => to_string(lead.source || :other),
      "description" => lead.description || lead.source_details
    }

    {lead, prefill}
  end

  defp load_pursue_item("prospect", id) do
    prospect = Ash.get!(Prospect, id)

    industry_label =
      if prospect.industry, do: prospect.industry |> to_string() |> String.replace("_", " ")

    prefill = %{
      "company_name" => prospect.name,
      "name" => [prospect.name, industry_label] |> Enum.filter(& &1) |> Enum.join(" - "),
      "workflow" => "outreach",
      "source" => "prospect",
      "description" => Enum.join(prospect.signals || [], ", ")
    }

    {prospect, prefill}
  end

  defp put_source_id(params, "bid", record), do: Map.put(params, :bid_id, record.id)
  defp put_source_id(params, "lead", record), do: Map.put(params, :lead_id, record.id)
  defp put_source_id(params, "prospect", record), do: Map.put(params, :prospect_id, record.id)
  defp put_source_id(params, _type, _record), do: params

  defp record_region("bid", record), do: record.region
  defp record_region("prospect", record), do: record.region
  defp record_region(_type, _record), do: nil

  # -- Display helpers --

  defp items_for_tab(%{active_tab: :all} = assigns), do: assigns.all_items

  defp items_for_tab(%{active_tab: :bids} = assigns),
    do: Enum.map(assigns.bids, &%{type: :bid, record: &1})

  defp items_for_tab(%{active_tab: :leads} = assigns),
    do: Enum.map(assigns.leads, &%{type: :lead, record: &1})

  defp items_for_tab(%{active_tab: :prospects} = assigns),
    do: Enum.map(assigns.prospects, &%{type: :prospect, record: &1})

  defp total_count(assigns) do
    length(assigns.bids) + length(assigns.leads) + length(assigns.prospects)
  end

  defp lead_display_name(lead) do
    name = "#{lead.first_name} #{lead.last_name}"
    if name == "Unknown Unknown", do: lead.company_name || "New Lead", else: name
  end

  defp due_urgency(nil), do: :none

  defp due_urgency(due_at) do
    now = DateTime.utc_now()
    days = DateTime.diff(due_at, now, :day)

    cond do
      days < 0 -> :overdue
      days <= 7 -> :this_week
      days <= 14 -> :soon
      true -> :none
    end
  end

  defp record_title("bid", record), do: record.title

  defp record_title("lead", record),
    do: record.company_name || "#{record.first_name} #{record.last_name}"

  defp record_title("prospect", record), do: record.name
  defp record_title(_, _), do: "item"

  defp pass_item_title(%{type: type, record: record}), do: record_title(type, record)

  defp format_source_label(:bid), do: "Bid"
  defp format_source_label(:referral), do: "Referral"
  defp format_source_label(:trade_show), do: "Trade Show"
  defp format_source_label(:cold_call), do: "Cold Call"
  defp format_source_label(:website), do: "Website"

  defp format_source_label(s) when is_atom(s),
    do: s |> to_string() |> String.replace("_", " ") |> String.capitalize()

  defp format_source_label(_), do: "Other"

  defp tier_badge(:hot), do: "badge badge-sm badge-error"
  defp tier_badge(:warm), do: "badge badge-sm badge-warning"
  defp tier_badge(:prospect), do: "badge badge-sm badge-info"
  defp tier_badge(_), do: "badge badge-sm badge-ghost"

  defp format_tier(nil), do: ""
  defp format_tier(tier), do: tier |> to_string() |> String.upcase()

  defp signal_badge(:strong), do: "badge badge-sm badge-error"
  defp signal_badge(:medium), do: "badge badge-sm badge-warning"
  defp signal_badge(:weak), do: "badge badge-sm badge-ghost"
  defp signal_badge(_), do: "badge badge-sm badge-ghost"

  defp format_region(nil), do: ""
  defp format_region(region), do: region |> to_string() |> String.upcase()

  defp format_date(nil), do: ""
  defp format_date(%DateTime{} = dt), do: Calendar.strftime(dt, "%b %d, %Y")
  defp format_date(%Date{} = d), do: Calendar.strftime(d, "%b %d, %Y")
  defp format_date(dt), do: Calendar.strftime(dt, "%b %d, %Y")

  defp parse_source(nil), do: :other
  defp parse_source(""), do: :other
  defp parse_source(s) when is_binary(s), do: String.to_existing_atom(s)
  defp parse_source(s) when is_atom(s), do: s

  defp parse_amount(nil), do: nil
  defp parse_amount(""), do: nil
  defp parse_amount(s) when is_binary(s), do: Decimal.new(s)
  defp parse_amount(d), do: d

  defp parse_date(nil), do: nil
  defp parse_date(""), do: nil
  defp parse_date(s) when is_binary(s), do: Date.from_iso8601!(s)
  defp parse_date(d), do: d
end
