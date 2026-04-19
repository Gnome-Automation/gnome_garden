defmodule GnomeGardenWeb.Finance.PaymentApplicationLive.Form do
  use GnomeGardenWeb, :live_view

  alias GnomeGarden.Finance

  @impl true
  def mount(params, _session, socket) do
    payment_application =
      if id = params["id"] do
        load_payment_application!(id, socket.assigns.current_user)
      end

    {:ok,
     socket
     |> assign(:payment_application, payment_application)
     |> assign(:payments, load_payments(socket.assigns.current_user))
     |> assign(:invoices, load_invoices(socket.assigns.current_user))
     |> assign(
       :page_title,
       if(payment_application, do: "Edit Payment Application", else: "New Payment Application")
     )
     |> assign_form(params)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.page max_width="max-w-5xl" class="pb-8">
      <.page_header eyebrow="Finance">
        {@page_title}
        <:subtitle>
          Allocate receipts to invoices explicitly so cash application stays auditable.
        </:subtitle>
        <:actions>
          <.button navigate={~p"/finance/payment-applications"}>
            <.icon name="hero-arrow-left" class="size-4" /> Back to applications
          </.button>
        </:actions>
      </.page_header>

      <.form
        for={@form}
        id="payment-application-form"
        phx-change="validate"
        phx-submit="save"
        class="space-y-6"
      >
        <.form_section
          title="Allocation Details"
          description="Tie one payment to one invoice with an explicit applied amount and date."
        >
          <div class="grid grid-cols-1 gap-6 sm:grid-cols-6">
            <div class="sm:col-span-3">
              <.input
                field={@form[:payment_id]}
                type="select"
                label="Payment"
                prompt="Select payment..."
                options={Enum.map(@payments, &{payment_label(&1), &1.id})}
              />
            </div>
            <div class="sm:col-span-3">
              <.input
                field={@form[:invoice_id]}
                type="select"
                label="Invoice"
                prompt="Select invoice..."
                options={Enum.map(@invoices, &{invoice_label(&1), &1.id})}
              />
            </div>
            <div class="sm:col-span-3">
              <.input field={@form[:amount]} label="Amount" type="number" step="0.01" />
            </div>
            <div class="sm:col-span-3">
              <.input field={@form[:applied_on]} type="date" label="Applied On" />
            </div>
            <div class="col-span-full">
              <.input field={@form[:notes]} type="textarea" label="Notes" />
            </div>
          </div>
        </.form_section>

        <.section body_class="px-6 py-5 sm:px-7">
          <.form_actions
            cancel_path={~p"/finance/payment-applications"}
            submit_label={
              if @payment_application, do: "Update Application", else: "Create Application"
            }
          />
        </.section>
      </.form>
    </.page>
    """
  end

  @impl true
  def handle_event("validate", %{"form" => params}, socket) do
    form = AshPhoenix.Form.validate(socket.assigns.form, params)
    {:noreply, assign(socket, form: to_form(form))}
  end

  @impl true
  def handle_event("save", %{"form" => params}, socket) do
    case AshPhoenix.Form.submit(socket.assigns.form, params: params) do
      {:ok, payment_application} ->
        {:noreply,
         socket
         |> put_flash(
           :info,
           "Payment application #{if socket.assigns.payment_application, do: "updated", else: "created"}"
         )
         |> push_navigate(to: ~p"/finance/payment-applications/#{payment_application}")}

      {:error, form} ->
        {:noreply, assign(socket, form: to_form(form))}
    end
  end

  defp assign_form(
         %{assigns: %{payment_application: payment_application, current_user: actor}} = socket,
         params
       ) do
    form =
      if payment_application do
        AshPhoenix.Form.for_update(
          payment_application,
          :update,
          actor: actor,
          domain: Finance
        )
      else
        AshPhoenix.Form.for_create(
          Finance.PaymentApplication,
          :create,
          actor: actor,
          domain: Finance,
          params: payment_application_defaults(params)
        )
      end

    assign(socket, :form, to_form(form))
  end

  defp load_payment_application!(id, actor) do
    case Finance.get_payment_application(id, actor: actor) do
      {:ok, payment_application} -> payment_application
      {:error, error} -> raise "failed to load payment application #{id}: #{inspect(error)}"
    end
  end

  defp load_payments(actor) do
    case Finance.list_payments(actor: actor, load: [:organization]) do
      {:ok, payments} -> Enum.sort_by(payments, &String.downcase(payment_label(&1)))
      {:error, error} -> raise "failed to load payments: #{inspect(error)}"
    end
  end

  defp load_invoices(actor) do
    case Finance.list_invoices(actor: actor, load: [:organization]) do
      {:ok, invoices} -> Enum.sort_by(invoices, &String.downcase(invoice_label(&1)))
      {:error, error} -> raise "failed to load invoices: #{inspect(error)}"
    end
  end

  defp payment_application_defaults(params) do
    %{}
    |> maybe_put("payment_id", params["payment_id"])
    |> maybe_put("invoice_id", params["invoice_id"])
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, _key, ""), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp payment_label(payment) do
    [
      payment.payment_number || "Payment",
      payment.organization && payment.organization.name
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(" · ")
  end

  defp invoice_label(invoice) do
    [
      invoice.invoice_number || "Invoice",
      invoice.organization && invoice.organization.name
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(" · ")
  end
end
