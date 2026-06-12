defmodule GnomeGardenWeb.Finance.RetainerLive.Index do
  use GnomeGardenWeb, :live_view

  require Ash.Query

  import GnomeGardenWeb.Finance.Helpers

  alias GnomeGarden.Finance

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Retainers")
     |> assign(:filter_status, "all")
     |> load_retainers()}
  end

  @impl true
  def handle_event("filter", %{"status" => status}, socket) do
    {:noreply, socket |> assign(:filter_status, status) |> load_retainers()}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.page class="pb-8">
      <.page_header eyebrow="Finance">
        Retainers
        <:subtitle>Client pre-payments held on account — applied against future invoices.</:subtitle>
        <:actions>
          <.button navigate={~p"/finance/retainers/new"}>
            New Retainer
          </.button>
        </:actions>
      </.page_header>

      <div class="mb-4 flex gap-2">
        <form phx-change="filter">
          <select name="status"
            class="block appearance-none rounded-md bg-base-100 px-3 py-1.5 text-sm text-base-content outline-1 -outline-offset-1 outline-base-content/20 hover:bg-base-200 focus:outline-2 focus:-outline-offset-2 focus:outline-primary transition-colors cursor-pointer pr-8">
            <option value="all" selected={@filter_status == "all"}>All</option>
            <option value="draft" selected={@filter_status == "draft"}>Draft</option>
            <option value="issued" selected={@filter_status == "issued"}>Issued</option>
            <option value="paid" selected={@filter_status == "paid"}>Paid</option>
            <option value="exhausted" selected={@filter_status == "exhausted"}>Exhausted</option>
            <option value="void" selected={@filter_status == "void"}>Void</option>
          </select>
        </form>
      </div>

      <div class="overflow-hidden rounded-lg border border-gray-200 dark:border-white/10">
        <table class="min-w-full divide-y divide-gray-200 dark:divide-white/10 text-sm">
          <thead class="bg-gray-50 dark:bg-white/5">
            <tr>
              <th class="px-4 py-3 text-left text-xs font-semibold uppercase tracking-wide text-gray-500">Number</th>
              <th class="px-4 py-3 text-left text-xs font-semibold uppercase tracking-wide text-gray-500">Client</th>
              <th class="px-4 py-3 text-right text-xs font-semibold uppercase tracking-wide text-gray-500">Amount</th>
              <th class="px-4 py-3 text-right text-xs font-semibold uppercase tracking-wide text-gray-500">Balance</th>
              <th class="px-4 py-3 text-left text-xs font-semibold uppercase tracking-wide text-gray-500">Status</th>
              <th class="px-4 py-3 text-left text-xs font-semibold uppercase tracking-wide text-gray-500">Received</th>
            </tr>
          </thead>
          <tbody class="divide-y divide-gray-100 bg-white dark:divide-white/5 dark:bg-transparent">
            <tr :if={Enum.empty?(@retainers)}>
              <td colspan="6" class="px-4 py-8 text-center text-sm text-gray-400">No retainers found.</td>
            </tr>
            <tr
              :for={r <- @retainers}
              class="cursor-pointer hover:bg-gray-50 dark:hover:bg-white/5"
              phx-click={JS.navigate(~p"/finance/retainers/#{r.id}")}
            >
              <td class="px-4 py-3 font-mono text-gray-900 dark:text-white"><%= r.retainer_number %></td>
              <td class="px-4 py-3 text-gray-900 dark:text-white"><%= r.organization && r.organization.name %></td>
              <td class="px-4 py-3 text-right font-mono text-gray-900 dark:text-white">
                $<%= Decimal.round(r.amount, 2) %>
              </td>
              <td class="px-4 py-3 text-right font-mono text-gray-900 dark:text-white">
                $<%= Decimal.round(r.balance_amount, 2) %>
              </td>
              <td class="px-4 py-3">
                <span class={status_class(r.status)}>
                  <%= format_atom(r.status) %>
                </span>
              </td>
              <td class="px-4 py-3 text-gray-500"><%= format_date(r.received_on) %></td>
            </tr>
          </tbody>
        </table>
      </div>
    </.page>
    """
  end

  defp load_retainers(socket) do
    retainers =
      GnomeGarden.Finance.Retainer
      |> then(fn q ->
        case socket.assigns.filter_status do
          "draft" -> Ash.Query.filter(q, status == :draft)
          "issued" -> Ash.Query.filter(q, status == :issued)
          "paid" -> Ash.Query.filter(q, status == :paid)
          "exhausted" -> Ash.Query.filter(q, status == :exhausted)
          "void" -> Ash.Query.filter(q, status == :void)
          _ -> q
        end
      end)
      |> Ash.Query.load([:organization, :balance_amount])
      |> Ash.Query.sort(inserted_at: :desc)
      |> Ash.read!(domain: Finance, authorize?: false)

    assign(socket, :retainers, retainers)
  end

  defp status_class(:paid),
    do: "inline-flex rounded-full bg-emerald-50 px-2 py-0.5 text-xs font-medium text-emerald-700"

  defp status_class(:issued),
    do: "inline-flex rounded-full bg-blue-50 px-2 py-0.5 text-xs font-medium text-blue-700"

  defp status_class(:void),
    do: "inline-flex rounded-full bg-gray-100 px-2 py-0.5 text-xs font-medium text-gray-500"

  defp status_class(:exhausted),
    do: "inline-flex rounded-full bg-gray-100 px-2 py-0.5 text-xs font-medium text-gray-500"

  defp status_class(_),
    do: "inline-flex rounded-full bg-yellow-50 px-2 py-0.5 text-xs font-medium text-yellow-700"
end
