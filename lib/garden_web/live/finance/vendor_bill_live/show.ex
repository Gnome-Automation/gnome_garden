defmodule GnomeGardenWeb.Finance.VendorBillLive.Show do
  use GnomeGardenWeb, :live_view

  alias GnomeGarden.Finance

  @impl true
  def mount(%{"id" => id} = params, _session, socket) do
    return_to = Map.get(params, "return_to", ~p"/finance/vendor-bills")

    case Finance.get_vendor_bill(id, authorize?: false, load: [:vendor]) do
      {:ok, bill} ->
        {:ok,
         socket
         |> assign(:page_title, bill.bill_number)
         |> assign(:bill, bill)
         |> assign(:return_to, return_to)}

      {:error, _} ->
        {:ok,
         socket
         |> put_flash(:error, "Bill not found.")
         |> push_navigate(to: ~p"/finance/vendor-bills")}
    end
  end

  @impl true
  def handle_event("approve", _params, socket) do
    case Finance.approve_vendor_bill(socket.assigns.bill, authorize?: false) do
      {:ok, bill} ->
        {:noreply,
         socket
         |> assign(:bill, %{bill | vendor: socket.assigns.bill.vendor})
         |> put_flash(:info, "Bill approved.")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not approve bill.")}
    end
  end

  @impl true
  def handle_event("mark_paid", _params, socket) do
    case Finance.pay_vendor_bill(socket.assigns.bill, authorize?: false) do
      {:ok, bill} ->
        {:noreply,
         socket
         |> assign(:bill, %{bill | vendor: socket.assigns.bill.vendor})
         |> put_flash(:info, "Bill marked as paid.")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not mark bill as paid.")}
    end
  end

  @impl true
  def handle_event("void", _params, socket) do
    case Finance.void_vendor_bill(socket.assigns.bill, authorize?: false) do
      {:ok, bill} ->
        {:noreply,
         socket
         |> assign(:bill, %{bill | vendor: socket.assigns.bill.vendor})
         |> put_flash(:info, "Bill voided.")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not void bill.")}
    end
  end

  @impl true
  def handle_event("reopen", _params, socket) do
    case Finance.reopen_vendor_bill(socket.assigns.bill, authorize?: false) do
      {:ok, bill} ->
        {:noreply,
         socket
         |> assign(:bill, %{bill | vendor: socket.assigns.bill.vendor})
         |> put_flash(:info, "Bill reopened.")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not reopen bill.")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.page class="pb-8">
      <.page_header eyebrow="Finance / Vendor Bills">
        <%= @bill.bill_number %>
        <:subtitle><%= @bill.vendor.name %></:subtitle>
        <:actions>
          <%= if @bill.status == :draft do %>
            <.button phx-click="approve" data-confirm="Approve this bill?">
              Approve
            </.button>
          <% end %>
          <%= if @bill.status == :approved do %>
            <.button phx-click="mark_paid" data-confirm="Mark this bill as paid?">
              Mark Paid
            </.button>
          <% end %>
          <%= if @bill.status in [:draft, :approved] do %>
            <.button phx-click="void" data-confirm="Void this bill? This cannot be undone easily.">
              Void
            </.button>
          <% end %>
          <%= if @bill.status == :voided do %>
            <.button phx-click="reopen">
              Reopen
            </.button>
          <% end %>
          <%= if @bill.status == :draft do %>
            <.button navigate={~p"/finance/vendor-bills/#{@bill.id}/edit"}>
              Edit
            </.button>
          <% end %>
          <.button navigate={@return_to}>
            Back
          </.button>
        </:actions>
      </.page_header>

      <div class="mb-6 grid grid-cols-2 gap-4 sm:grid-cols-4">
        <div>
          <p class="text-xs font-medium uppercase tracking-wide text-gray-500">Issued On</p>
          <p class="mt-1 text-sm text-gray-900 dark:text-white"><%= @bill.issued_on %></p>
        </div>
        <div>
          <p class="text-xs font-medium uppercase tracking-wide text-gray-500">Due On</p>
          <p class={["mt-1 text-sm", if(overdue?(@bill), do: "text-red-600 dark:text-red-400 font-medium", else: "text-gray-900 dark:text-white")]}>
            <%= @bill.due_on || "—" %>
            <%= if overdue?(@bill), do: " (overdue)" %>
          </p>
        </div>
        <div>
          <p class="text-xs font-medium uppercase tracking-wide text-gray-500">Status</p>
          <p class="mt-1">
            <span class={status_class(@bill.status)}>
              <%= String.capitalize(to_string(@bill.status)) %>
            </span>
          </p>
        </div>
        <div>
          <p class="text-xs font-medium uppercase tracking-wide text-gray-500">Amount</p>
          <p class="mt-1 text-sm font-mono font-semibold text-gray-900 dark:text-white">
            $<%= Decimal.round(@bill.total_amount, 2) %>
          </p>
        </div>
      </div>

      <div class="rounded-lg border border-gray-200 dark:border-white/10 p-4">
        <p class="text-xs font-medium uppercase tracking-wide text-gray-500 mb-1">Description</p>
        <p class="text-sm text-gray-900 dark:text-white"><%= @bill.description %></p>
        <%= if @bill.notes do %>
          <p class="mt-3 text-xs font-medium uppercase tracking-wide text-gray-500 mb-1">Notes</p>
          <p class="text-sm text-gray-500"><%= @bill.notes %></p>
        <% end %>
      </div>
    </.page>
    """
  end

  defp overdue?(bill) do
    bill.status in [:draft, :approved] &&
      bill.due_on != nil &&
      Date.compare(bill.due_on, Date.utc_today()) == :lt
  end

  defp status_class(:paid),
    do: "inline-flex rounded-full bg-emerald-50 px-2 py-0.5 text-xs font-medium text-emerald-700"

  defp status_class(:approved),
    do: "inline-flex rounded-full bg-blue-50 px-2 py-0.5 text-xs font-medium text-blue-700"

  defp status_class(:voided),
    do: "inline-flex rounded-full bg-gray-100 px-2 py-0.5 text-xs font-medium text-gray-500"

  defp status_class(_),
    do: "inline-flex rounded-full bg-yellow-50 px-2 py-0.5 text-xs font-medium text-yellow-700"
end
