defmodule GnomeGardenWeb.Agents.Sales.BidsLive do
  use GnomeGardenWeb, :live_view

  alias GnomeGarden.Agents.Bid

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, :page_title, "Bids")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-4">
      <div class="flex justify-between items-center">
        <h1 class="text-2xl font-bold">Bids</h1>
        <a href="/admin/agents/bid" class="btn btn-sm btn-ghost">
          Open in Admin <.icon name="hero-arrow-top-right-on-square" class="size-4" />
        </a>
      </div>

      <Cinder.collection
        resource={Bid}
        actor={@current_user}
        search={[placeholder: "Search bids..."]}
      >
        <:col :let={bid} field="title" label="Title" filter sort search>
          <span class="font-medium max-w-xs truncate" title={bid.title}>{bid.title}</span>
        </:col>
        <:col :let={bid} field="score_total" label="Score" sort>
          <span class={score_color(bid.score_total)}>{bid.score_total || "-"}</span>
        </:col>
        <:col :let={bid} field="score_tier" label="Tier" filter sort>
          <span class={tier_badge(bid.score_tier)}>{format_tier(bid.score_tier)}</span>
        </:col>
        <:col :let={bid} field="agency" label="Agency" filter search>
          <span class="max-w-[150px] truncate">{bid.agency}</span>
        </:col>
        <:col :let={bid} field="region" label="Region" filter sort>
          {format_region(bid.region)}
        </:col>
        <:col :let={bid} field="due_at" label="Due" sort>
          {format_date(bid.due_at)}
        </:col>
        <:col :let={bid} field="status" label="Status" filter sort>
          <span class={status_badge(bid.status)}>{format_status(bid.status)}</span>
        </:col>
        <:col :let={bid} label="">
          <a href={"/admin/agents/bid/#{bid.id}"} class="btn btn-xs btn-ghost">
            <.icon name="hero-pencil" class="size-4" />
          </a>
        </:col>
      </Cinder.collection>
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

  defp status_badge(nil), do: "badge badge-ghost badge-sm"
  defp status_badge(:new), do: "badge badge-primary badge-sm"
  defp status_badge(:reviewing), do: "badge badge-info badge-sm"
  defp status_badge(:submitted), do: "badge badge-success badge-sm"
  defp status_badge(:won), do: "badge badge-success badge-sm"
  defp status_badge(:lost), do: "badge badge-error badge-sm"
  defp status_badge(:passed), do: "badge badge-ghost badge-sm"
  defp status_badge(_), do: "badge badge-ghost badge-sm"

  defp format_status(nil), do: "new"
  defp format_status(status), do: status |> to_string() |> String.replace("_", " ")

  defp format_region(nil), do: "-"
  defp format_region(region), do: region |> to_string() |> String.upcase()

  defp format_date(nil), do: "-"
  defp format_date(datetime), do: Calendar.strftime(datetime, "%b %d, %Y")
end
