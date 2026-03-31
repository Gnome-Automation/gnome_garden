defmodule GnomeGardenWeb.CRM.OpportunityLive.Show do
  use GnomeGardenWeb, :live_view

  alias GnomeGarden.Sales

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    opportunity = Sales.get_opportunity!(id, actor: socket.assigns.current_user, load: [:company])

    {:ok,
     socket
     |> assign(:page_title, opportunity.name)
     |> assign(:opportunity, opportunity)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.header>
      {@opportunity.name}
      <:subtitle :if={@opportunity.company}>
        <.link navigate={~p"/crm/companies/#{@opportunity.company}"} class="hover:text-emerald-600">
          {@opportunity.company.name}
        </.link>
      </:subtitle>
      <:actions>
        <.button navigate={~p"/crm/opportunities"}>
          <.icon name="hero-arrow-left" class="size-4" /> Back
        </.button>
        <.button variant="primary" navigate={~p"/crm/opportunities/#{@opportunity}/edit"}>
          <.icon name="hero-pencil-square" class="size-4" /> Edit
        </.button>
      </:actions>
    </.header>

    <div class="mt-6 grid grid-cols-1 gap-8 lg:grid-cols-2">
      <div>
        <h2 class="text-base font-semibold mb-4">Deal Information</h2>
        <.list>
          <:item title="Stage">
            <span class={stage_badge(@opportunity.stage)}>{format_atom(@opportunity.stage)}</span>
          </:item>
          <:item title="Amount">{format_amount(@opportunity.amount)}</:item>
          <:item title="Probability">{@opportunity.probability || 0}%</:item>
          <:item title="Weighted Value">{format_weighted(@opportunity)}</:item>
          <:item title="Source">{format_atom(@opportunity.source)}</:item>
        </.list>
      </div>

      <div>
        <h2 class="text-base font-semibold mb-4">Timeline</h2>
        <.list>
          <:item title="Expected Close">{format_date(@opportunity.expected_close_date)}</:item>
          <:item :if={@opportunity.actual_close_date} title="Actual Close">
            {format_date(@opportunity.actual_close_date)}
          </:item>
          <:item title="Created">{format_datetime(@opportunity.inserted_at)}</:item>
        </.list>
      </div>
    </div>

    <div :if={@opportunity.description} class="mt-8">
      <h2 class="text-base font-semibold mb-2">Description</h2>
      <p class="text-sm text-zinc-600 dark:text-zinc-400 whitespace-pre-wrap">
        {@opportunity.description}
      </p>
    </div>

    <div :if={@opportunity.loss_reason} class="mt-8">
      <h2 class="text-base font-semibold mb-2">Loss Reason</h2>
      <p class="text-sm text-error whitespace-pre-wrap">
        {@opportunity.loss_reason}
      </p>
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

  defp format_atom(nil), do: "-"
  defp format_atom(atom), do: atom |> to_string() |> String.replace("_", " ") |> String.capitalize()

  defp format_amount(nil), do: "-"
  defp format_amount(amount), do: "$#{Decimal.to_string(amount)}"

  defp format_weighted(%{amount: nil}), do: "-"
  defp format_weighted(%{amount: amount, probability: prob}) when is_nil(prob), do: format_amount(amount)
  defp format_weighted(%{amount: amount, probability: prob}) do
    weighted = Decimal.mult(amount, Decimal.div(Decimal.new(prob), 100))
    "$#{Decimal.to_string(Decimal.round(weighted, 2))}"
  end

  defp format_date(nil), do: "-"
  defp format_date(date), do: Calendar.strftime(date, "%b %d, %Y")

  defp format_datetime(nil), do: "-"
  defp format_datetime(datetime), do: Calendar.strftime(datetime, "%b %d, %Y %H:%M")
end
