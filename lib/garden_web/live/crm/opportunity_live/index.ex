defmodule GnomeGardenWeb.CRM.OpportunityLive.Index do
  use GnomeGardenWeb, :live_view

  import GnomeGardenWeb.CRM.Helpers

  alias GnomeGarden.Sales.Opportunity

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, page_title: "Opportunities")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <div class="flex justify-end">
        <.button navigate={~p"/crm/opportunities/new"} variant="primary">
          <.icon name="hero-plus" class="size-4" /> Add Opportunity
        </.button>
      </div>

      <Cinder.collection
        id="opportunities"
        resource={Opportunity}
        actor={@current_user}
        search={[placeholder: "Search opportunities..."]}
      >
        <:col :let={opp} field="name" label="Name" sort search>
          <.link navigate={~p"/crm/opportunities/#{opp}"} class="font-medium hover:text-emerald-600">
            {opp.name}
          </.link>
        </:col>
        <:col :let={opp} field="stage" label="Stage" sort>
          <.status_badge status={opportunity_stage(opp.stage)}>
            {format_atom(opp.stage)}
          </.status_badge>
        </:col>
        <:col :let={opp} field="amount" label="Amount" sort>
          {format_amount(opp.amount)}
        </:col>
        <:col :let={opp} field="probability" label="Probability" sort>
          {opp.probability || 0}%
        </:col>
        <:col :let={opp} field="expected_close_date" label="Expected Close" sort>
          {format_date(opp.expected_close_date)}
        </:col>
        <:col :let={opp} label="">
          <.link
            navigate={~p"/crm/opportunities/#{opp}/edit"}
            class="inline-flex items-center justify-center rounded-md p-1.5 text-zinc-400 transition hover:bg-zinc-900/5 hover:text-zinc-600 dark:hover:bg-white/5 dark:hover:text-zinc-300"
          >
            <.icon name="hero-pencil" class="size-4" />
          </.link>
        </:col>
      </Cinder.collection>
    </div>
    """
  end
end
