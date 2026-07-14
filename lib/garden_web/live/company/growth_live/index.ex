defmodule GnomeGardenWeb.Company.GrowthLive.Index do
  use GnomeGardenWeb, :live_view

  import GnomeGardenWeb.Operations.Helpers, only: [format_atom: 1]

  alias GnomeGarden.Company

  @sections [
    {:idea, "Idea Inbox", "Captured but not yet evaluated."},
    {:evaluating, "Evaluating", "Being sized: benefit, effort, eligibility."},
    {:planned, "Planned", "Approved and waiting to start."},
    {:in_progress, "In Progress", "Being delivered through tasks and playbooks."},
    {:on_hold, "On Hold", "Paused with a reason."},
    {:achieved, "Achieved", "Done — the permanent record."},
    {:declined, "Declined", "Considered and passed on, with reasons."}
  ]

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      GnomeGardenWeb.Endpoint.subscribe("growth_initiative:created")
      GnomeGardenWeb.Endpoint.subscribe("growth_initiative:updated")
    end

    {:ok,
     socket
     |> assign(:page_title, "Company Growth")
     |> assign_initiatives()
     |> assign_capture_form()}
  end

  @impl true
  def handle_event("validate", %{"form" => params}, socket) do
    form = AshPhoenix.Form.validate(socket.assigns.capture_form, params)
    {:noreply, assign(socket, capture_form: to_form(form))}
  end

  @impl true
  def handle_event("capture", %{"form" => params}, socket) do
    params = Map.put(params, "company_profile_id", primary_profile_id(socket))

    case AshPhoenix.Form.submit(socket.assigns.capture_form, params: params) do
      {:ok, initiative} ->
        {:noreply,
         socket
         |> put_flash(:info, "Idea captured: #{initiative.title}")
         |> assign_initiatives()
         |> assign_capture_form()}

      {:error, form} ->
        {:noreply, assign(socket, capture_form: to_form(form))}
    end
  end

  @impl true
  def handle_info(%{topic: "growth_initiative:" <> _event}, socket) do
    {:noreply, assign_initiatives(socket)}
  end

  @impl true
  def render(assigns) do
    assigns = assign(assigns, :sections, @sections)

    ~H"""
    <.page class="pb-8">
      <.page_header eyebrow="Company">
        Company Growth
        <:subtitle>
          Ideas to expand what Gnome can bid on and win — captured, decided, and
          kept as history. Delivery happens through linked tasks and playbooks.
        </:subtitle>
      </.page_header>

      <.section title="Capture an Idea" description="One line is enough; evaluation comes later.">
        <.form
          for={@capture_form}
          id="growth-capture-form"
          phx-change="validate"
          phx-submit="capture"
          class="grid grid-cols-1 gap-4 sm:grid-cols-6"
        >
          <div class="sm:col-span-4">
            <.input field={@capture_form[:title]} label="Idea" required />
          </div>
          <div class="sm:col-span-2">
            <.input
              field={@capture_form[:category]}
              type="select"
              label="Category"
              options={category_options()}
            />
          </div>
          <div class="col-span-full">
            <.button type="submit" variant="primary">Capture</.button>
          </div>
        </.form>
      </.section>

      <.section
        :for={{status, title, description} <- @sections}
        :if={@grouped[status] != nil or status == :idea}
        title={title}
        description={description}
        body_class="p-0"
      >
        <div :if={(@grouped[status] || []) == []} class="p-4">
          <.empty_state icon="hero-light-bulb" title="Nothing here" description="" />
        </div>
        <div
          :if={(@grouped[status] || []) != []}
          class="divide-y divide-zinc-200 dark:divide-white/10"
        >
          <.link
            :for={initiative <- @grouped[status] || []}
            navigate={~p"/company/growth/#{initiative}"}
            class="flex items-center justify-between gap-3 px-4 py-3 transition hover:bg-zinc-50 dark:hover:bg-white/[0.03]"
          >
            <div class="min-w-0">
              <p class="font-medium text-base-content">{initiative.title}</p>
              <p class="text-xs text-base-content/50">
                {format_atom(initiative.category)}
                <span :if={initiative.evidence_count > 0}>
                  · {initiative.evidence_count} evidence
                </span>
                <span :if={initiative.owner_team_member}>
                  · {initiative.owner_team_member.display_name}
                </span>
                <span :if={initiative.target_date}>· target {initiative.target_date}</span>
              </p>
            </div>
            <.status_badge status={initiative.status_variant}>
              {format_atom(initiative.status)}
            </.status_badge>
          </.link>
        </div>
      </.section>
    </.page>
    """
  end

  defp assign_initiatives(socket) do
    case Company.list_growth_initiative_workspace(actor: socket.assigns.current_user) do
      {:ok, initiatives} ->
        socket
        |> assign(:grouped, Enum.group_by(initiatives, & &1.status))

      {:error, error} ->
        raise "failed to load growth initiatives: #{inspect(error)}"
    end
  end

  defp assign_capture_form(socket) do
    form =
      AshPhoenix.Form.for_create(Company.GrowthInitiative, :create,
        actor: socket.assigns.current_user,
        domain: Company
      )

    assign(socket, :capture_form, to_form(form))
  end

  defp primary_profile_id(socket) do
    case Company.get_primary_company_profile(actor: socket.assigns.current_user) do
      {:ok, profile} -> profile.id
      {:error, error} -> raise "no primary company profile: #{inspect(error)}"
    end
  end

  defp category_options do
    [
      {"Certification", :certification},
      {"Registration", :registration},
      {"Licensing", :licensing},
      {"Bonding", :bonding},
      {"Insurance", :insurance},
      {"Partner program", :partner_program},
      {"Market access", :market_access},
      {"Marketing asset", :marketing_asset},
      {"Operational readiness", :operational_readiness}
    ]
  end
end
