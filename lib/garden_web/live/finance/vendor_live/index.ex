defmodule GnomeGardenWeb.Finance.VendorLive.Index do
  use GnomeGardenWeb, :live_view

  require Ash.Query

  alias GnomeGarden.Finance
  alias GnomeGarden.Finance.Vendor

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Vendors")
     |> assign(:filter_active, "all")
     |> load_vendors()}
  end

  @impl true
  def handle_event("filter", %{"active" => active}, socket) do
    {:noreply, socket |> assign(:filter_active, active) |> load_vendors()}
  end

  @impl true
  def handle_event("deactivate", %{"id" => id}, socket) do
    vendor = Enum.find(socket.assigns.vendors, &(to_string(&1.id) == id))

    case Finance.deactivate_vendor(vendor, authorize?: false) do
      {:ok, _} ->
        {:noreply, socket |> load_vendors() |> put_flash(:info, "Vendor deactivated.")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not deactivate vendor.")}
    end
  end

  @impl true
  def handle_event("reactivate", %{"id" => id}, socket) do
    vendor = Enum.find(socket.assigns.vendors, &(to_string(&1.id) == id))

    case Finance.update_vendor(vendor, %{active: true}, authorize?: false) do
      {:ok, _} ->
        {:noreply, socket |> load_vendors() |> put_flash(:info, "Vendor reactivated.")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not reactivate vendor.")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.page class="pb-8">
      <.page_header eyebrow="Finance">
        Vendors
        <:subtitle>Suppliers and service providers that send you bills.</:subtitle>
        <:actions>
          <.button navigate={~p"/finance/vendors/new"}>
            New Vendor
          </.button>
        </:actions>
      </.page_header>

      <div class="mb-4 flex gap-2">
        <form phx-change="filter">
          <select name="active"
            class="block appearance-none rounded-md bg-base-100 px-3 py-1.5 text-sm text-base-content outline-1 -outline-offset-1 outline-base-content/20 hover:bg-base-200 focus:outline-2 focus:-outline-offset-2 focus:outline-primary transition-colors cursor-pointer pr-8">
            <option value="active" selected={@filter_active == "active"}>Active</option>
            <option value="inactive" selected={@filter_active == "inactive"}>Inactive</option>
            <option value="all" selected={@filter_active == "all"}>All</option>
          </select>
        </form>
      </div>

      <div class="overflow-hidden rounded-lg border border-gray-200 dark:border-white/10">
        <table class="min-w-full divide-y divide-gray-200 dark:divide-white/10 text-sm">
          <thead class="bg-gray-50 dark:bg-white/5">
            <tr>
              <th class="px-4 py-3 text-left text-xs font-semibold uppercase tracking-wide text-gray-500">Name</th>
              <th class="px-4 py-3 text-left text-xs font-semibold uppercase tracking-wide text-gray-500">Email</th>
              <th class="px-4 py-3 text-left text-xs font-semibold uppercase tracking-wide text-gray-500">Phone</th>
              <th class="px-4 py-3 text-left text-xs font-semibold uppercase tracking-wide text-gray-500">Terms</th>
              <th class="px-4 py-3 text-left text-xs font-semibold uppercase tracking-wide text-gray-500">Status</th>
              <th class="px-4 py-3"></th>
            </tr>
          </thead>
          <tbody class="divide-y divide-gray-100 bg-white dark:divide-white/5 dark:bg-transparent">
            <tr :if={Enum.empty?(@vendors)}>
              <td colspan="6" class="px-4 py-8 text-center text-sm text-gray-400">No vendors found.</td>
            </tr>
            <tr :for={vendor <- @vendors} class="hover:bg-gray-50 dark:hover:bg-white/5">
              <td class="px-4 py-3 font-medium text-gray-900 dark:text-white">
                <.link navigate={~p"/finance/vendors/#{vendor.id}"} class="hover:underline">
                  <%= vendor.name %>
                </.link>
              </td>
              <td class="px-4 py-3 text-gray-500"><%= vendor.email || "—" %></td>
              <td class="px-4 py-3 text-gray-500"><%= vendor.phone || "—" %></td>
              <td class="px-4 py-3 text-gray-500">Net <%= vendor.payment_terms_days %></td>
              <td class="px-4 py-3">
                <span class={status_class(vendor.active)}>
                  <%= if vendor.active, do: "Active", else: "Inactive" %>
                </span>
              </td>
              <td class="px-4 py-3 text-right">
                <.link navigate={~p"/finance/vendors/#{vendor.id}/edit"} class="text-xs text-emerald-600 hover:underline mr-3 dark:text-emerald-400">
                  Edit
                </.link>
                <%= if vendor.active do %>
                  <button phx-click="deactivate" phx-value-id={vendor.id}
                    data-confirm="Deactivate this vendor?"
                    class="text-xs text-gray-400 hover:text-red-600 transition-colors">
                    Deactivate
                  </button>
                <% else %>
                  <button phx-click="reactivate" phx-value-id={vendor.id}
                    class="text-xs text-gray-400 hover:text-emerald-600 transition-colors">
                    Reactivate
                  </button>
                <% end %>
              </td>
            </tr>
          </tbody>
        </table>
      </div>
    </.page>
    """
  end

  defp load_vendors(socket) do
    vendors =
      Vendor
      |> then(fn q ->
        case socket.assigns.filter_active do
          "active" -> Ash.Query.filter(q, active == true)
          "inactive" -> Ash.Query.filter(q, active == false)
          _ -> q
        end
      end)
      |> Ash.Query.sort(name: :asc)
      |> Ash.read!(domain: Finance, authorize?: false)

    assign(socket, :vendors, vendors)
  end

  defp status_class(true),
    do: "inline-flex rounded-full bg-emerald-50 px-2 py-0.5 text-xs font-medium text-emerald-700"

  defp status_class(false),
    do: "inline-flex rounded-full bg-gray-100 px-2 py-0.5 text-xs font-medium text-gray-500"
end
