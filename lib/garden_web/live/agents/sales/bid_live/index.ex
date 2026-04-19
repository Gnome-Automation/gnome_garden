defmodule GnomeGardenWeb.Agents.Sales.BidLive.Index do
  use GnomeGardenWeb, :live_view

  alias GnomeGarden.Procurement.Bid

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      GnomeGardenWeb.Endpoint.subscribe("bid:created")
      GnomeGardenWeb.Endpoint.subscribe("bid:scored")
    end

    {:ok, assign(socket, :page_title, "Bids")}
  end

  @impl true
  def handle_info(%{topic: "bid:" <> _}, socket) do
    {:noreply, Cinder.refresh_table(socket, "bids")}
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

  defp badge_class(nil), do: "badge badge-ghost badge-sm"
  defp badge_class(:new), do: "badge badge-primary badge-sm"
  defp badge_class(:reviewing), do: "badge badge-info badge-sm"
  defp badge_class(:submitted), do: "badge badge-success badge-sm"
  defp badge_class(:won), do: "badge badge-success badge-sm"
  defp badge_class(:lost), do: "badge badge-error badge-sm"
  defp badge_class(:passed), do: "badge badge-ghost badge-sm"
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
end
