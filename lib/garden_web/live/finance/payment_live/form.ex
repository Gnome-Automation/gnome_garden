defmodule GnomeGardenWeb.Finance.PaymentLive.Form do
  use GnomeGardenWeb, :live_view

  alias GnomeGarden.Commercial
  alias GnomeGarden.Finance
  alias GnomeGarden.Operations

  @impl true
  def mount(params, _session, socket) do
    payment = if id = params["id"], do: load_payment!(id, socket.assigns.current_user)

    {:ok,
     socket
     |> assign(:payment, payment)
     |> assign(:organizations, load_organizations(socket.assigns.current_user))
     |> assign(:agreements, load_agreements(socket.assigns.current_user))
     |> assign(:page_title, if(payment, do: "Edit Payment", else: "New Payment"))
     |> assign_form(params)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.page max_width="max-w-5xl" class="pb-8">
      <.page_header eyebrow="Finance">
        {@page_title}
        <:subtitle>
          Record operational receipt events before allocating them to invoices.
        </:subtitle>
        <:actions>
          <.button navigate={~p"/finance/payments"}>
            Back to payments
          </.button>
        </:actions>
      </.page_header>

      <.form for={@form} id="payment-form" phx-change="validate" phx-submit="save" class="space-y-6">
        <.form_section
          title="Payment Details"
          description="Capture the receipt itself first; allocations to invoices happen separately through payment applications."
        >
          <div class="grid grid-cols-1 gap-6 sm:grid-cols-6">
            <div class="sm:col-span-3">
              <.input
                field={@form[:organization_id]}
                type="select"
                label="Organization"
                prompt="Select organization..."
                options={Enum.map(@organizations, &{&1.name, &1.id})}
              />
            </div>
            <div class="sm:col-span-3">
              <.input
                field={@form[:agreement_id]}
                type="select"
                label="Agreement"
                prompt="Select agreement..."
                options={Enum.map(@agreements, &{agreement_label(&1), &1.id})}
              />
            </div>
            <div class="sm:col-span-3">
              <.input field={@form[:payment_number]} label="Payment Number" />
            </div>
            <div class="sm:col-span-3">
              <.input field={@form[:received_on]} type="date" label="Received On" />
            </div>
            <div class="sm:col-span-2">
              <.input
                field={@form[:payment_method]}
                type="select"
                label="Payment Method"
                options={payment_method_options()}
              />
            </div>
            <div class="sm:col-span-2">
              <.input field={@form[:currency_code]} label="Currency Code" />
            </div>
            <div class="sm:col-span-2">
              <.input field={@form[:amount]} label="Amount" type="number" step="0.01" />
            </div>
            <div class="col-span-full">
              <.input field={@form[:reference]} label="Reference" />
            </div>
            <div class="col-span-full">
              <.input field={@form[:notes]} type="textarea" label="Notes" />
            </div>
          </div>
        </.form_section>

        <.section body_class="px-6 py-5 sm:px-7">
          <.form_actions
            cancel_path={~p"/finance/payments"}
            submit_label={if @payment, do: "Update Payment", else: "Create Payment"}
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
      {:ok, payment} ->
        {:noreply,
         socket
         |> put_flash(
           :info,
           "Payment #{if socket.assigns.payment, do: "updated", else: "created"}"
         )
         |> push_navigate(to: ~p"/finance/payments/#{payment}")}

      {:error, form} ->
        {:noreply, assign(socket, form: to_form(form))}
    end
  end

  defp assign_form(%{assigns: %{payment: payment, current_user: actor}} = socket, params) do
    form =
      if payment do
        AshPhoenix.Form.for_update(payment, :update, actor: actor, domain: Finance)
      else
        AshPhoenix.Form.for_create(
          Finance.Payment,
          :create,
          actor: actor,
          domain: Finance,
          params: payment_defaults(params)
        )
      end

    assign(socket, :form, to_form(form))
  end

  defp load_payment!(id, actor) do
    case Finance.get_payment(id, actor: actor) do
      {:ok, payment} -> payment
      {:error, error} -> raise "failed to load payment #{id}: #{inspect(error)}"
    end
  end

  defp load_organizations(actor) do
    case Operations.list_organizations(actor: actor) do
      {:ok, organizations} -> Enum.sort_by(organizations, &String.downcase(&1.name || ""))
      {:error, error} -> raise "failed to load organizations: #{inspect(error)}"
    end
  end

  defp load_agreements(actor) do
    case Commercial.list_agreements(actor: actor, load: [:organization]) do
      {:ok, agreements} -> Enum.sort_by(agreements, &String.downcase(&1.name || ""))
      {:error, error} -> raise "failed to load agreements: #{inspect(error)}"
    end
  end

  defp payment_defaults(params) do
    %{}
    |> maybe_put("organization_id", params["organization_id"])
    |> maybe_put("agreement_id", params["agreement_id"])
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, _key, ""), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp agreement_label(agreement) do
    [agreement.name, agreement.organization && agreement.organization.name]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(" · ")
  end

  defp payment_method_options do
    [
      {"ACH", :ach},
      {"Wire", :wire},
      {"Check", :check},
      {"Card", :card},
      {"Cash", :cash},
      {"Other", :other}
    ]
  end
end
