defmodule GnomeGardenWeb.Finance.RecurringVendorBillLive.Show do
  use GnomeGardenWeb, :live_view

  import GnomeGardenWeb.Finance.Helpers

  alias GnomeGarden.Finance

  @impl true
  def mount(%{"id" => id} = params, _session, socket) do
    template = Finance.get_recurring_vendor_bill!(id, authorize?: false, load: [:vendor])

    {:ok,
     socket
     |> assign(:page_title, "Recurring Bill")
     |> assign(:template, template)
     |> assign(:return_to, params["return_to"] || ~p"/finance/recurring-vendor-bills")}
  end

  @impl true
  def handle_event("pause", _params, socket) do
    case Finance.pause_recurring_vendor_bill(socket.assigns.template, authorize?: false) do
      {:ok, updated} ->
        {:noreply, socket |> assign(:template, reload(updated.id)) |> put_flash(:info, "Template paused")}
      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Could not pause: #{inspect(reason)}")}
    end
  end

  @impl true
  def handle_event("resume", _params, socket) do
    case Finance.resume_recurring_vendor_bill(socket.assigns.template, authorize?: false) do
      {:ok, updated} ->
        {:noreply, socket |> assign(:template, reload(updated.id)) |> put_flash(:info, "Template resumed")}
      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Could not resume: #{inspect(reason)}")}
    end
  end

  @impl true
  def handle_event("stop", _params, socket) do
    case Finance.stop_recurring_vendor_bill(socket.assigns.template, authorize?: false) do
      {:ok, updated} ->
        {:noreply, socket |> assign(:template, reload(updated.id)) |> put_flash(:info, "Template stopped")}
      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Could not stop: #{inspect(reason)}")}
    end
  end

  @impl true
  def handle_event("delete", _params, socket) do
    case Finance.destroy_recurring_vendor_bill(socket.assigns.template, authorize?: false) do
      :ok ->
        {:noreply, push_navigate(socket, to: ~p"/finance/recurring-vendor-bills")}
      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Could not delete: #{inspect(reason)}")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.page class="pb-8">
      <.page_header eyebrow="Finance">
        Recurring Bill Template
        <:subtitle>
          <.status_badge status={status_variant(@template.status)}>
            {format_atom(@template.status)}
          </.status_badge>
        </:subtitle>
        <:actions>
          <.button navigate={@return_to}>Back</.button>
          <.button navigate={~p"/finance/recurring-vendor-bills/#{@template.id}/edit"}>Edit</.button>
        </:actions>
      </.page_header>

      <.section title="Template Status">
        <div class="flex flex-wrap gap-3">
          <.button :if={@template.status == :active} phx-click="pause">
            <.icon name="hero-pause" class="size-4" /> Pause
          </.button>
          <.button :if={@template.status == :paused} phx-click="resume" variant="primary">
            <.icon name="hero-play" class="size-4" /> Resume
          </.button>
          <.button :if={@template.status in [:active, :paused]} phx-click="stop" data-confirm="Stop this recurring bill? It will no longer generate new bills.">
            <.icon name="hero-stop" class="size-4" /> Stop
          </.button>
          <.button :if={@template.status == :stopped} phx-click="delete" data-confirm="Permanently delete this template?">
            <.icon name="hero-trash" class="size-4" /> Delete
          </.button>
        </div>
      </.section>

      <div class="grid gap-6 lg:grid-cols-2">
        <.section title="Bill Details">
          <div class="grid gap-5 sm:grid-cols-2">
            <.property_item label="Vendor" value={((@template.vendor && @template.vendor.name) || "-")} />
            <.property_item label="Amount" value={format_amount(@template.amount)} />
            <.property_item label="Description" value={@template.description || "-"} />
            <.property_item label="Interval" value={format_atom(@template.interval)} />
          </div>
        </.section>

        <.section title="Schedule">
          <div class="grid gap-5 sm:grid-cols-2">
            <.property_item label="Next Due On" value={format_date(@template.next_due_on)} />
            <.property_item label="End Date" value={format_date(@template.end_date)} />
            <.property_item label="Status" value={format_atom(@template.status)} />
          </div>
        </.section>
      </div>

      <.section :if={@template.notes} title="Notes">
        <p class="whitespace-pre-wrap text-sm leading-6 text-base-content/70">{@template.notes}</p>
      </.section>
    </.page>
    """
  end

  attr :label, :string, required: true
  attr :value, :string, required: true

  defp property_item(assigns) do
    ~H"""
    <div class="space-y-1">
      <p class="text-xs font-semibold uppercase tracking-[0.2em] text-base-content/40">{@label}</p>
      <p class="text-sm font-medium text-base-content">{@value}</p>
    </div>
    """
  end

  defp reload(id) do
    Finance.get_recurring_vendor_bill!(id, authorize?: false, load: [:vendor])
  end

  defp status_variant(:active), do: "success"
  defp status_variant(:paused), do: "warning"
  defp status_variant(:stopped), do: "neutral"
  defp status_variant(_), do: "neutral"


end
