defmodule GnomeGardenWeb.CRM.CompanyLive.Show do
  use GnomeGardenWeb, :live_view

  import GnomeGardenWeb.CRM.Helpers

  require Ash.Query

  alias GnomeGarden.Sales

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    company =
      Sales.get_company!(id,
        actor: socket.assigns.current_user,
        load: [:leads, :lead_sources, :activities, :opportunities]
      )

    # Load bids linked to this company
    bids =
      GnomeGarden.Agents.Bid
      |> Ash.Query.filter(agency_company_id == ^id)
      |> Ash.Query.sort(inserted_at: :desc)
      |> Ash.read!()

    # Load contacts via employment
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
    <.header>
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
    </.header>

    <%!-- Tabs --%>
    <div class="mt-6 border-b border-base-200">
      <div class="flex gap-4">
        <.tab_button tab="overview" current={@tab}>Overview</.tab_button>
        <.tab_button tab="leads" current={@tab}>Leads ({length(@company.leads)})</.tab_button>
        <.tab_button tab="bids" current={@tab}>Bids ({length(@bids)})</.tab_button>
        <.tab_button tab="contacts" current={@tab}>Contacts ({length(@contacts)})</.tab_button>
        <.tab_button tab="sources" current={@tab}>
          Sources ({length(@company.lead_sources)})
        </.tab_button>
        <.tab_button tab="activity" current={@tab}>
          Activity ({length(@company.activities)})
        </.tab_button>
      </div>
    </div>

    <%!-- Tab Content --%>
    <div class="mt-6">
      <div :if={@tab == "overview"}>
        <div class="grid grid-cols-1 gap-8 lg:grid-cols-2">
          <div>
            <.heading level={3}>Company Details</.heading>
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
          </div>

          <div>
            <.heading level={3}>Contact Info</.heading>
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
          </div>
        </div>

        <div :if={@company.description} class="mt-6">
          <.heading level={3}>Description</.heading>
          <p class="mt-2 text-sm whitespace-pre-wrap">{@company.description}</p>
        </div>
      </div>

      <div :if={@tab == "leads"}>
        <div :if={@company.leads == []} class="text-center py-8 text-zinc-400">No leads yet</div>
        <div
          :for={lead <- @company.leads}
          class="card bg-base-100 shadow-sm border border-base-200 mb-3"
        >
          <div class="card-body p-4">
            <div class="flex justify-between items-center">
              <div>
                <.link navigate={~p"/crm/leads/#{lead}"} class="font-medium hover:text-emerald-600">
                  {lead.first_name} {lead.last_name}
                </.link>
                <span class="badge badge-sm badge-primary ml-2">{lead.source}</span>
                <span class="badge badge-sm badge-ghost ml-1">{lead.status}</span>
                <div class="text-sm text-zinc-500 mt-1">
                  {String.slice(lead.source_details || "", 0, 100)}
                </div>
              </div>
            </div>
          </div>
        </div>
      </div>

      <div :if={@tab == "bids"}>
        <div :if={@bids == []} class="text-center py-8 text-zinc-400">No bids yet</div>
        <div :for={bid <- @bids} class="card bg-base-100 shadow-sm border border-base-200 mb-3">
          <div class="card-body p-4">
            <div class="flex justify-between items-center">
              <div>
                <.link
                  navigate={~p"/agents/sales/bids/#{bid}"}
                  class="font-medium hover:text-emerald-600"
                >
                  {bid.title}
                </.link>
                <span class={bid_tier_badge(bid.score_tier)}>{bid.score_tier}</span>
                <span class="text-sm text-zinc-500 ml-2">Score: {bid.score_total}</span>
              </div>
              <span class="badge badge-sm badge-ghost">{bid.status}</span>
            </div>
          </div>
        </div>
      </div>

      <div :if={@tab == "contacts"}>
        <div :if={@contacts == []} class="text-center py-8 text-zinc-400">No contacts yet</div>
        <div
          :for={contact <- @contacts}
          class="card bg-base-100 shadow-sm border border-base-200 mb-3"
        >
          <div class="card-body p-4">
            <.link navigate={~p"/crm/contacts/#{contact}"} class="font-medium hover:text-emerald-600">
              {contact.first_name} {contact.last_name}
            </.link>
            <span :if={contact.email} class="text-sm text-zinc-500 ml-2">{contact.email}</span>
          </div>
        </div>
      </div>

      <div :if={@tab == "sources"}>
        <div :if={@company.lead_sources == []} class="text-center py-8 text-zinc-400">
          No monitored sources
        </div>
        <div
          :for={source <- @company.lead_sources}
          class="card bg-base-100 shadow-sm border border-base-200 mb-3"
        >
          <div class="card-body p-4">
            <div class="flex justify-between items-center">
              <div>
                <span class="font-medium">{source.name}</span>
                <span class="badge badge-sm badge-ghost ml-2">{source.source_type}</span>
                <div class="text-sm text-zinc-500 mt-1">{source.url}</div>
              </div>
              <div class="text-right text-sm">
                <div class={source_config_badge(source.config_status)}>
                  {format_atom(source.config_status)}
                </div>
                <div :if={source.last_scanned_at} class="text-zinc-400 mt-1">
                  Last scanned: {Calendar.strftime(source.last_scanned_at, "%b %d, %H:%M")}
                </div>
              </div>
            </div>
          </div>
        </div>
      </div>

      <div :if={@tab == "activity"}>
        <div :if={@company.activities == []} class="text-center py-8 text-zinc-400">
          No activities yet
        </div>
        <div :for={activity <- @company.activities} class="flex gap-3 mb-4">
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
    </div>
    """
  end

  attr :tab, :string, required: true
  attr :current, :string, required: true
  slot :inner_block, required: true

  defp tab_button(assigns) do
    ~H"""
    <button
      phx-click="tab"
      phx-value-tab={@tab}
      class={[
        "pb-2 px-1 text-sm font-medium border-b-2 transition",
        if(@tab == @current,
          do: "border-emerald-500 text-emerald-600",
          else: "border-transparent text-zinc-500 hover:text-zinc-700"
        )
      ]}
    >
      {render_slot(@inner_block)}
    </button>
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
