defmodule GnomeGardenWeb.CRM.OpportunitiesLive do
  use GnomeGardenWeb, :live_view

  alias GnomeGarden.Sales.Opportunity

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, :page_title, "Opportunities")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-4">
      <div class="flex justify-between items-center">
        <h1 class="text-2xl font-bold">Opportunities</h1>
        <div class="flex gap-2">
          <a href="/admin/sales/opportunity?action=create" class="btn btn-sm btn-primary">
            <.icon name="hero-plus" class="size-4" /> Add Opportunity
          </a>
        </div>
      </div>

      <Cinder.collection
        resource={Opportunity}
        actor={@current_user}
        search={[placeholder: "Search opportunities..."]}
      >
        <:col :let={opp} field="name" label="Name" filter sort search>
          <span class="font-medium">{opp.name}</span>
        </:col>
        <:col :let={opp} field="stage" label="Stage" filter sort>
          <span class={stage_badge(opp.stage)}>{format_stage(opp.stage)}</span>
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
          <a href={"/admin/sales/opportunity/#{opp.id}"} class="btn btn-xs btn-ghost">
            <.icon name="hero-pencil" class="size-4" />
          </a>
        </:col>
      </Cinder.collection>
    </div>
    """
  end

  defp stage_badge(:discovery), do: "badge badge-info badge-sm"
  defp stage_badge(:qualification), do: "badge badge-info badge-sm"
  defp stage_badge(:demo), do: "badge badge-warning badge-sm"
  defp stage_badge(:proposal), do: "badge badge-warning badge-sm"
  defp stage_badge(:negotiation), do: "badge badge-primary badge-sm"
  defp stage_badge(:closed_won), do: "badge badge-success badge-sm"
  defp stage_badge(:closed_lost), do: "badge badge-error badge-sm"
  defp stage_badge(_), do: "badge badge-ghost badge-sm"

  defp format_stage(nil), do: "-"
  defp format_stage(stage), do: stage |> to_string() |> String.replace("_", " ")

  defp format_amount(nil), do: "-"
  defp format_amount(amount), do: "$#{Decimal.to_string(amount)}"

  defp format_date(nil), do: "-"
  defp format_date(date), do: Calendar.strftime(date, "%b %d, %Y")
end
