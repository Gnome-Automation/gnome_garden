defmodule GnomeGardenWeb.Finance.VendorBillLive.Form do
  use GnomeGardenWeb, :live_view

  require Ash.Query

  alias GnomeGarden.Finance
  alias GnomeGarden.Finance.Vendor

  @impl true
  def mount(params, _session, socket) do
    bill = if id = params["id"], do: load_bill!(id)
    vendors = load_vendors()

    {:ok,
     socket
     |> assign(:bill, bill)
     |> assign(:vendors, vendors)
     |> assign(:return_to, params["return_to"] || ~p"/finance/vendor-bills")
     |> assign(:page_title, if(bill, do: "Edit Bill", else: "New Bill"))
     |> assign_form(params)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.page max_width="max-w-3xl" class="pb-8">
      <.page_header eyebrow="Finance / Vendor Bills">
        {@page_title}
        <:actions>
          <.button navigate={@return_to}>
            Back to bills
          </.button>
        </:actions>
      </.page_header>

      <.form
        for={@form}
        id="vendor-bill-form"
        phx-change="validate"
        phx-submit="save"
        class="space-y-6"
      >
        <.form_section title="Bill Details" description="Enter the details from the vendor's bill.">
          <div class="grid grid-cols-1 gap-6 sm:grid-cols-6">
            <div class="sm:col-span-4">
              <.input
                field={@form[:vendor_id]}
                type="select"
                label="Vendor"
                prompt="Select vendor..."
                options={Enum.map(@vendors, &{&1.name, &1.id})}
                required
              />
              <p class="mt-1.5 text-xs text-base-content/50">
                Not in the list?
                <.link navigate={~p"/finance/vendors/new"} class="underline text-emerald-600 dark:text-emerald-400">Add a vendor first</.link>.
              </p>
            </div>
            <div class="sm:col-span-2">
              <.input
                field={@form[:total_amount]}
                type="number"
                step="0.01"
                label="Total Amount"
                required
              />
            </div>
            <div class="sm:col-span-3">
              <.input field={@form[:issued_on]} type="date" label="Issued On" required />
            </div>
            <div class="sm:col-span-3">
              <.input field={@form[:due_on]} type="date" label="Due On" />
            </div>
            <div class="col-span-full">
              <.input field={@form[:description]} label="Description" required />
            </div>
            <div class="col-span-full">
              <.input field={@form[:notes]} type="textarea" label="Notes" />
            </div>
          </div>
        </.form_section>

        <.section body_class="px-6 py-5 sm:px-7">
          <.form_actions
            cancel_path={~p"/finance/vendor-bills"}
            submit_label={if @bill, do: "Update Bill", else: "Create Bill"}
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
      {:ok, bill} ->
        {:noreply,
         socket
         |> put_flash(:info, if(socket.assigns.bill, do: "Bill updated.", else: "Bill created."))
         |> push_navigate(to: socket.assigns.return_to)}

      {:error, form} ->
        {:noreply,
         socket
         |> put_flash(:error, "Please fix the errors below.")
         |> assign(form: to_form(form))}
    end
  end

  defp assign_form(%{assigns: %{bill: bill}} = socket, params) do
    form =
      if bill do
        AshPhoenix.Form.for_update(bill, :update, domain: Finance, authorize?: false)
      else
        defaults = %{}
        |> maybe_put("vendor_id", params["vendor_id"])
        |> maybe_put("issued_on", Date.to_iso8601(Date.utc_today()))

        AshPhoenix.Form.for_create(
          Finance.VendorBill,
          :create,
          domain: Finance,
          authorize?: false,
          params: defaults
        )
      end

    assign(socket, :form, to_form(form))
  end

  defp load_bill!(id) do
    case Finance.get_vendor_bill(id, authorize?: false) do
      {:ok, bill} -> bill
      {:error, _} -> raise "bill #{id} not found"
    end
  end

  defp load_vendors do
    Vendor
    |> Ash.Query.filter(active == true)
    |> Ash.Query.sort(name: :asc)
    |> Ash.read!(domain: Finance, authorize?: false)
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, _key, ""), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
