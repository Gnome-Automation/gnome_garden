defmodule GnomeGardenWeb.CRM.CompanyLive.Show do
  use GnomeGardenWeb, :live_view

  import GnomeGardenWeb.CRM.Helpers

  require Ash.Query

  alias GnomeGarden.Operations
  alias GnomeGarden.Procurement
  alias GnomeGarden.Sales

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    actor = socket.assigns.current_user

    company =
      Sales.get_company!(id,
        actor: actor,
        load: [:leads, :procurement_sources, :activities, :opportunities]
      )

    bids = load_company_bids(company, actor)

    contacts =
      GnomeGarden.Sales.Contact
      |> Ash.Query.filter(exists(employments, company_id == ^id and is_current == true))
      |> Ash.read!()

    {:ok,
     socket
     |> assign(:page_title, company.name)
     |> assign(:company, company)
     |> assign(:bids, bids)
     |> assign(:contacts, contacts)
     |> assign(:tab, "overview")}
  end

  @impl true
  def handle_event("tab", %{"tab" => tab}, socket) do
    {:noreply, assign(socket, :tab, tab)}
  end

  def handle_event("accept", _, socket) do
    company = Ash.update!(socket.assigns.company, %{}, action: :accept)
    {:noreply, assign(socket, :company, company)}
  end

  def handle_event("reject", %{"reason" => reason}, socket) do
    company =
      Ash.update!(socket.assigns.company, %{rejection_reason: String.to_existing_atom(reason)},
        action: :reject
      )

    {:noreply, assign(socket, :company, company)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.page class="pb-8">
      <.page_header eyebrow="CRM">
        {@company.name}
        <:subtitle>
          <span class={review_badge(@company.review_status)}>
            {format_atom(@company.review_status)}
          </span>
          <span :if={@company.company_type} class="badge badge-sm badge-ghost ml-1">
            {format_atom(@company.company_type)}
          </span>
          <span :if={@company.region} class="badge badge-sm badge-outline ml-1">
            {format_region(@company.region)}
          </span>
        </:subtitle>
        <:actions>
          <.button navigate={~p"/crm/companies"}>
            <.icon name="hero-arrow-left" class="size-4" /> Back
          </.button>
          <.button :if={@company.review_status == :new} phx-click="accept" variant="primary">
            Accept
          </.button>
          <.button variant="primary" navigate={~p"/crm/companies/#{@company}/edit"}>
            <.icon name="hero-pencil-square" class="size-4" /> Edit
          </.button>
        </:actions>
      </.page_header>

      <.section
        title="Company Workspace"
        description="Switch between overview, CRM signals, sourcing, and the activity timeline."
      >
        <div class="flex flex-wrap gap-3">
          <.tab_button tab="overview" current={@tab}>Overview</.tab_button>
          <.tab_button tab="leads" current={@tab}>Leads ({length(@company.leads)})</.tab_button>
          <.tab_button tab="bids" current={@tab}>Bids ({length(@bids)})</.tab_button>
          <.tab_button tab="contacts" current={@tab}>Contacts ({length(@contacts)})</.tab_button>
          <.tab_button tab="sources" current={@tab}>
            Sources ({length(@company.procurement_sources)})
          </.tab_button>
          <.tab_button tab="activity" current={@tab}>
            Activity ({length(@company.activities)})
          </.tab_button>
        </div>
      </.section>

      <.company_overview :if={@tab == "overview"} company={@company} />
      <.company_leads :if={@tab == "leads"} leads={@company.leads} />
      <.company_bids :if={@tab == "bids"} bids={@bids} />
      <.company_contacts :if={@tab == "contacts"} contacts={@contacts} />
      <.company_sources :if={@tab == "sources"} sources={@company.procurement_sources} />
      <.company_activity :if={@tab == "activity"} activities={@company.activities} />
    </.page>
    """
  end

  attr :company, :map, required: true

  defp company_overview(assigns) do
    ~H"""
    <div class="grid grid-cols-1 gap-6 lg:grid-cols-2">
      <.section title="Company Details">
        <.properties>
          <.property name="Type">{format_atom(@company.company_type)}</.property>
          <.property name="Status">
            <.status_badge status={if @company.status == :active, do: :success, else: :warning}>
              {format_atom(@company.status)}
            </.status_badge>
          </.property>
          <.property name="Region">{format_region(@company.region)}</.property>
          <.property name="Source">{format_atom(@company.source)}</.property>
          <.property :if={@company.employee_count} name="Employees">
            {@company.employee_count}
          </.property>
        </.properties>
      </.section>

      <.section title="Contact Info">
        <.properties>
          <.property name="Website">
            <a
              :if={@company.website}
              href={@company.website}
              target="_blank"
              class="text-emerald-600 hover:text-emerald-500"
            >
              {@company.website}
            </a>
            <span :if={!@company.website} class="text-zinc-400">-</span>
          </.property>
          <.property name="Phone">{@company.phone || "-"}</.property>
          <.property name="Address">
            {[@company.address, @company.city, @company.state, @company.postal_code]
            |> Enum.filter(& &1)
            |> Enum.join(", ")}
          </.property>
        </.properties>
      </.section>
    </div>

    <.section :if={@company.description} title="Description">
      <p class="whitespace-pre-wrap text-sm text-zinc-600 dark:text-zinc-300">
        {@company.description}
      </p>
    </.section>
    """
  end

  defp load_company_bids(company, actor) do
    case Operations.get_organization_by_name(company.name, actor: actor) do
      {:ok, organization} ->
        Procurement.list_bids_for_organization(organization.id, actor: actor)
        |> case do
          {:ok, bids} -> bids
          {:error, _error} -> []
        end

      {:error, _error} ->
        []
    end
  end

  attr :leads, :list, required: true

  defp company_leads(assigns) do
    ~H"""
    <.section
      title="Leads"
      description="Incoming people and signals already attached to this company."
    >
      <div :if={@leads == []}>
        <.empty_state
          title="No leads yet"
          description="Qualifying leads tied to this company will show up here."
          icon="hero-user-plus"
        />
      </div>
      <div :if={@leads != []} class="space-y-3">
        <div
          :for={lead <- @leads}
          class="rounded-3xl border border-zinc-200/80 bg-white px-5 py-4 dark:border-white/10 dark:bg-white/[0.03]"
        >
          <div class="space-y-2">
            <.link navigate={~p"/crm/leads/#{lead}"} class="font-medium hover:text-emerald-600">
              {lead.first_name} {lead.last_name}
            </.link>
            <div class="flex flex-wrap items-center gap-2">
              <span class="badge badge-sm badge-primary">{lead.source}</span>
              <span class="badge badge-sm badge-ghost">{lead.status}</span>
            </div>
            <p class="text-sm text-zinc-500 dark:text-zinc-400">
              {String.slice(lead.source_details || "", 0, 140)}
            </p>
          </div>
        </div>
      </div>
    </.section>
    """
  end

  attr :bids, :list, required: true

  defp company_bids(assigns) do
    ~H"""
    <.section title="Bids" description="Procurement opportunities connected to this company.">
      <div :if={@bids == []}>
        <.empty_state
          title="No bids yet"
          description="Bid intelligence linked to this company will appear here."
          icon="hero-document-text"
        />
      </div>
      <div :if={@bids != []} class="space-y-3">
        <div
          :for={bid <- @bids}
          class="rounded-3xl border border-zinc-200/80 bg-white px-5 py-4 dark:border-white/10 dark:bg-white/[0.03]"
        >
          <div class="flex flex-col gap-3 sm:flex-row sm:items-start sm:justify-between">
            <div class="space-y-2">
              <.link
                navigate={~p"/procurement/bids/#{bid}"}
                class="font-medium hover:text-emerald-600"
              >
                {bid.title}
              </.link>
              <div class="flex flex-wrap items-center gap-2">
                <span class={bid_tier_badge(bid.score_tier)}>{bid.score_tier}</span>
                <span class="text-sm text-zinc-500">Score: {bid.score_total}</span>
              </div>
            </div>
            <span class="badge badge-sm badge-ghost">{bid.status}</span>
          </div>
        </div>
      </div>
    </.section>
    """
  end

  attr :contacts, :list, required: true

  defp company_contacts(assigns) do
    ~H"""
    <.section title="Contacts" description="People currently connected to this company.">
      <div :if={@contacts == []}>
        <.empty_state
          title="No contacts yet"
          description="Add employment history or contact records to build the relationship map."
          icon="hero-users"
        />
      </div>
      <div :if={@contacts != []} class="space-y-3">
        <div
          :for={contact <- @contacts}
          class="rounded-3xl border border-zinc-200/80 bg-white px-5 py-4 dark:border-white/10 dark:bg-white/[0.03]"
        >
          <.link navigate={~p"/crm/contacts/#{contact}"} class="font-medium hover:text-emerald-600">
            {contact.first_name} {contact.last_name}
          </.link>
          <p :if={contact.email} class="mt-1 text-sm text-zinc-500 dark:text-zinc-400">
            {contact.email}
          </p>
        </div>
      </div>
    </.section>
    """
  end

  attr :sources, :list, required: true

  defp company_sources(assigns) do
    ~H"""
    <.section
      title="Procurement Sources"
      description="Bid portals and monitored sources tied to this company."
    >
      <div :if={@sources == []}>
        <.empty_state
          title="No monitored sources"
          description="Attach procurement sources to keep scans and bid discovery organized."
          icon="hero-globe-alt"
        />
      </div>
      <div :if={@sources != []} class="space-y-3">
        <div
          :for={source <- @sources}
          class="rounded-3xl border border-zinc-200/80 bg-white px-5 py-4 dark:border-white/10 dark:bg-white/[0.03]"
        >
          <div class="flex flex-col gap-3 sm:flex-row sm:items-start sm:justify-between">
            <div class="space-y-2">
              <div class="flex flex-wrap items-center gap-2">
                <span class="font-medium text-zinc-900 dark:text-white">{source.name}</span>
                <span class="badge badge-sm badge-ghost">{source.source_type}</span>
              </div>
              <p class="text-sm text-zinc-500 dark:text-zinc-400">{source.url}</p>
            </div>
            <div class="text-sm sm:text-right">
              <div class={source_config_badge(source.config_status)}>
                {format_atom(source.config_status)}
              </div>
              <div :if={source.last_scanned_at} class="mt-1 text-zinc-400">
                Last scanned: {Calendar.strftime(source.last_scanned_at, "%b %d, %H:%M")}
              </div>
            </div>
          </div>
        </div>
      </div>
    </.section>
    """
  end

  attr :activities, :list, required: true

  defp company_activity(assigns) do
    ~H"""
    <.section title="Activity" description="Recent CRM events and company-related touchpoints.">
      <div :if={@activities == []}>
        <.empty_state
          title="No activity yet"
          description="Calls, notes, and sourced events will build the company timeline here."
          icon="hero-clock"
        />
      </div>
      <div :if={@activities != []} class="space-y-4">
        <div
          :for={activity <- @activities}
          class="flex gap-3 rounded-3xl border border-zinc-200/80 bg-white px-5 py-4 dark:border-white/10 dark:bg-white/[0.03]"
        >
          <div class="badge badge-sm badge-outline mt-1">{format_atom(activity.activity_type)}</div>
          <div>
            <div class="font-medium text-sm">{activity.subject}</div>
            <div :if={activity.description} class="text-sm text-zinc-500">{activity.description}</div>
            <div class="text-xs text-zinc-400 mt-1">
              {Calendar.strftime(activity.occurred_at, "%b %d, %Y %H:%M")}
            </div>
          </div>
        </div>
      </div>
    </.section>
    """
  end

  defp review_badge(:new), do: "badge badge-warning badge-sm"
  defp review_badge(:accepted), do: "badge badge-success badge-sm"
  defp review_badge(:rejected), do: "badge badge-error badge-sm"
  defp review_badge(:snoozed), do: "badge badge-ghost badge-sm"
  defp review_badge(:active), do: "badge badge-info badge-sm"
  defp review_badge(_), do: "badge badge-ghost badge-sm"

  defp bid_tier_badge(:hot), do: "badge badge-sm badge-error"
  defp bid_tier_badge(:warm), do: "badge badge-sm badge-warning"
  defp bid_tier_badge(:prospect), do: "badge badge-sm badge-info"
  defp bid_tier_badge(_), do: "badge badge-sm badge-ghost"

  defp source_config_badge(:configured), do: "badge badge-success badge-sm"
  defp source_config_badge(:found), do: "badge badge-ghost badge-sm"
  defp source_config_badge(:pending), do: "badge badge-warning badge-sm"
  defp source_config_badge(_), do: "badge badge-ghost badge-sm"
end
