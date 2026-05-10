defmodule GnomeGardenWeb.Finance.PaymentApplicationLive.Show do
  use GnomeGardenWeb, :live_view

  import GnomeGardenWeb.Finance.Helpers

  alias GnomeGarden.Finance

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    payment_application = load_payment_application!(id, socket.assigns.current_user)

    {:ok,
     socket
     |> assign(:page_title, "Payment Application")
     |> assign(:payment_application, payment_application)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.page class="pb-8">
      <.page_header eyebrow="Finance">
        Payment Application
        <:subtitle>
          <span class="inline-flex items-center gap-2">
            <span>
              {(@payment_application.payment && @payment_application.payment.payment_number) ||
                "Payment"}
            </span>
            <span class="text-base-content/40">→</span>
            <span>
              {(@payment_application.invoice && @payment_application.invoice.invoice_number) ||
                "Invoice"}
            </span>
          </span>
        </:subtitle>
        <:actions>
          <.button navigate={~p"/finance/payment-applications"}>
            Back
          </.button>
          <.button navigate={~p"/finance/payment-applications/#{@payment_application}/edit"}>
            Edit
          </.button>
        </:actions>
      </.page_header>

      <.section title="Application Snapshot">
        <div class="grid gap-5 sm:grid-cols-2">
          <.property_item
            label="Payment"
            value={
              (@payment_application.payment && @payment_application.payment.payment_number) || "-"
            }
          />
          <.property_item
            label="Invoice"
            value={
              (@payment_application.invoice && @payment_application.invoice.invoice_number) || "-"
            }
          />
          <.property_item label="Applied On" value={format_date(@payment_application.applied_on)} />
          <.property_item label="Amount" value={format_amount(@payment_application.amount)} />
        </div>
      </.section>

      <.section :if={@payment_application.notes} title="Notes">
        <p class="whitespace-pre-wrap text-sm leading-6 text-base-content/70">
          {@payment_application.notes}
        </p>
      </.section>
    </.page>
    """
  end

  attr :label, :string, required: true
  attr :value, :string, required: true

  defp property_item(assigns) do
    ~H"""
    <div class="space-y-1">
      <p class="text-xs font-semibold uppercase tracking-[0.2em] text-base-content/40">
        {@label}
      </p>
      <p class="text-sm font-medium text-base-content">{@value}</p>
    </div>
    """
  end

  defp load_payment_application!(id, actor) do
    case Finance.get_payment_application(id, actor: actor, load: [payment: [], invoice: []]) do
      {:ok, payment_application} -> payment_application
      {:error, error} -> raise "failed to load payment application #{id}: #{inspect(error)}"
    end
  end
end
