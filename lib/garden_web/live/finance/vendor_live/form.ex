defmodule GnomeGardenWeb.Finance.VendorLive.Form do
  use GnomeGardenWeb, :live_view

  alias GnomeGarden.Finance

  @impl true
  def mount(params, _session, socket) do
    vendor = if id = params["id"], do: load_vendor!(id)
    return_to = params["return_to"] || ~p"/finance/vendors"

    {:ok,
     socket
     |> assign(:vendor, vendor)
     |> assign(:return_to, return_to)
     |> assign(:page_title, if(vendor, do: "Edit Vendor", else: "New Vendor"))
     |> assign_form()}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.page max_width="max-w-3xl" class="pb-8">
      <.page_header eyebrow="Finance / Vendors">
        {@page_title}
        <:actions>
          <.button navigate={@return_to}>
            Cancel
          </.button>
        </:actions>
      </.page_header>

      <.form
        for={@form}
        id="vendor-form"
        phx-change="validate"
        phx-submit="save"
        class="space-y-6"
      >
        <.form_section title="Vendor Details" description="Basic contact information for this vendor.">
          <div class="grid grid-cols-1 gap-6 sm:grid-cols-6">
            <div class="sm:col-span-4">
              <.input field={@form[:name]} label="Vendor Name" required />
            </div>
            <div class="sm:col-span-2">
              <.input
                field={@form[:payment_terms_days]}
                type="number"
                label="Payment Terms (days)"
              />
            </div>
            <div class="sm:col-span-3">
              <.input field={@form[:email]} type="email" label="Email" />
            </div>
            <div class="sm:col-span-3">
              <.input field={@form[:phone]} label="Phone" />
            </div>
            <div class="col-span-full">
              <.input field={@form[:address]} type="textarea" label="Address" />
            </div>
            <div class="col-span-full">
              <.input field={@form[:notes]} type="textarea" label="Notes" />
            </div>
          </div>
        </.form_section>

        <.section body_class="px-6 py-5 sm:px-7">
          <.form_actions
            cancel_path={~p"/finance/vendors"}
            submit_label={if @vendor, do: "Update Vendor", else: "Create Vendor"}
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
      {:ok, vendor} ->
        {:noreply,
         socket
         |> put_flash(:info, if(socket.assigns.vendor, do: "Vendor updated.", else: "Vendor created."))
         |> push_navigate(to: socket.assigns.return_to)}

      {:error, form} ->
        {:noreply,
         socket
         |> put_flash(:error, "Please fix the errors below.")
         |> assign(form: to_form(form))}
    end
  end

  defp assign_form(%{assigns: %{vendor: vendor}} = socket) do
    form =
      if vendor do
        AshPhoenix.Form.for_update(vendor, :update, domain: Finance, authorize?: false)
      else
        AshPhoenix.Form.for_create(Finance.Vendor, :create, domain: Finance, authorize?: false)
      end

    assign(socket, :form, to_form(form))
  end

  defp load_vendor!(id) do
    case Finance.get_vendor(id, authorize?: false) do
      {:ok, vendor} -> vendor
      {:error, _} -> raise "vendor #{id} not found"
    end
  end
end
