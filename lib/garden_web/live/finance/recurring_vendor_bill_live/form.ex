defmodule GnomeGardenWeb.Finance.RecurringVendorBillLive.Form do
  use GnomeGardenWeb, :live_view

  import GnomeGardenWeb.Finance.Helpers

  alias GnomeGarden.Finance

  @impl true
  def mount(%{"id" => id} = params, _session, socket) do
    template = Finance.get_recurring_vendor_bill!(id, authorize?: false, load: [:vendor])
    vendors = load_vendors()

    {:ok,
     socket
     |> assign(:page_title, "Edit Recurring Bill")
     |> assign(:template, template)
     |> assign(:vendors, vendors)
     |> assign(:return_to, params["return_to"] || ~p"/finance/recurring-vendor-bills/#{id}")
     |> assign_form(template)}
  end

  def mount(params, _session, socket) do
    vendors = load_vendors()

    {:ok,
     socket
     |> assign(:page_title, "New Recurring Bill Template")
     |> assign(:template, nil)
     |> assign(:vendors, vendors)
     |> assign(:return_to, params["return_to"] || ~p"/finance/recurring-vendor-bills")
     |> assign_form(nil)}
  end

  @impl true
  def handle_event("validate", %{"form" => params}, socket) do
    {:noreply, assign(socket, :form, Map.merge(socket.assigns.form, params))}
  end

  @impl true
  def handle_event("save", %{"form" => params}, socket) do
    actor = socket.assigns.current_user

    attrs = %{
      vendor_id: params["vendor_id"],
      description: params["description"],
      amount: parse_decimal(params["amount"]),
      interval: String.to_existing_atom(params["interval"]),
      next_due_on: parse_date(params["next_due_on"]),
      end_date: parse_date(params["end_date"]),
      notes: blank_to_nil(params["notes"])
    }

    result =
      if socket.assigns.template do
        Finance.update_recurring_vendor_bill(socket.assigns.template, attrs, actor: actor)
      else
        Finance.create_recurring_vendor_bill(attrs, actor: actor)
      end

    case result do
      {:ok, saved} ->
        {:noreply, push_navigate(socket, to: ~p"/finance/recurring-vendor-bills/#{saved.id}")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Could not save: #{inspect(reason)}")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.page class="pb-8">
      <.page_header eyebrow="Finance">
        {@page_title}
        <:actions>
          <.button navigate={@return_to}>Cancel</.button>
        </:actions>
      </.page_header>

      <div class="max-w-2xl">
        <form phx-submit="save" phx-change="validate" class="space-y-6">
          <div class="border-b border-gray-900/10 pb-8 dark:border-white/10">
            <div class="grid grid-cols-1 gap-x-6 gap-y-6 sm:grid-cols-6">

              <div class="sm:col-span-6">
                <label class="block text-sm/6 font-medium text-gray-900 dark:text-white">Vendor</label>
                <div class="mt-2">
                  <select name="form[vendor_id]"
                    class="w-full appearance-none rounded-md bg-white px-3 py-1.5 text-base text-gray-900 outline-1 -outline-offset-1 outline-gray-300 focus:outline-2 focus:-outline-offset-2 focus:outline-emerald-600 sm:text-sm/6 dark:bg-white/5 dark:text-white dark:outline-white/10 dark:focus:outline-emerald-500">
                    <option value="">Select a vendor...</option>
                    <option :for={v <- @vendors} value={v.id} selected={@form["vendor_id"] == v.id}>{v.name}</option>
                  </select>
                </div>
              </div>

              <div class="sm:col-span-6">
                <label class="block text-sm/6 font-medium text-gray-900 dark:text-white">Description</label>
                <div class="mt-2">
                  <input type="text" name="form[description]" value={@form["description"]} required placeholder="e.g. Monthly software subscription"
                    class="w-full rounded-md bg-white px-3 py-1.5 text-base text-gray-900 outline-1 -outline-offset-1 outline-gray-300 placeholder:text-gray-400 focus:outline-2 focus:-outline-offset-2 focus:outline-emerald-600 sm:text-sm/6 dark:bg-white/5 dark:text-white dark:outline-white/10 dark:placeholder:text-gray-500 dark:focus:outline-emerald-500" />
                </div>
              </div>

              <div class="sm:col-span-3">
                <label class="block text-sm/6 font-medium text-gray-900 dark:text-white">Amount</label>
                <div class="mt-2">
                  <input type="number" name="form[amount]" value={@form["amount"]} step="0.01" min="0.01" required placeholder="0.00"
                    class="w-full rounded-md bg-white px-3 py-1.5 text-base text-gray-900 outline-1 -outline-offset-1 outline-gray-300 placeholder:text-gray-400 focus:outline-2 focus:-outline-offset-2 focus:outline-emerald-600 sm:text-sm/6 dark:bg-white/5 dark:text-white dark:outline-white/10 dark:placeholder:text-gray-500 dark:focus:outline-emerald-500" />
                </div>
              </div>

              <div class="sm:col-span-3">
                <label class="block text-sm/6 font-medium text-gray-900 dark:text-white">Interval</label>
                <div class="mt-2">
                  <select name="form[interval]"
                    class="w-full appearance-none rounded-md bg-white px-3 py-1.5 text-base text-gray-900 outline-1 -outline-offset-1 outline-gray-300 focus:outline-2 focus:-outline-offset-2 focus:outline-emerald-600 sm:text-sm/6 dark:bg-white/5 dark:text-white dark:outline-white/10 dark:focus:outline-emerald-500">
                    <option value="weekly" selected={@form["interval"] == "weekly"}>Weekly</option>
                    <option value="monthly" selected={@form["interval"] == "monthly"}>Monthly</option>
                    <option value="quarterly" selected={@form["interval"] == "quarterly"}>Quarterly</option>
                    <option value="semi_annually" selected={@form["interval"] == "semi_annually"}>Semi-annually</option>
                    <option value="annually" selected={@form["interval"] == "annually"}>Annually</option>
                  </select>
                </div>
              </div>

              <div class="sm:col-span-3">
                <label class="block text-sm/6 font-medium text-gray-900 dark:text-white">First Due On</label>
                <div class="mt-2">
                  <input type="date" name="form[next_due_on]" value={@form["next_due_on"]} required
                    class="w-full rounded-md bg-white px-3 py-1.5 text-base text-gray-900 outline-1 -outline-offset-1 outline-gray-300 focus:outline-2 focus:-outline-offset-2 focus:outline-emerald-600 sm:text-sm/6 dark:bg-white/5 dark:text-white dark:outline-white/10 dark:focus:outline-emerald-500" />
                </div>
              </div>

              <div class="sm:col-span-3">
                <label class="block text-sm/6 font-medium text-gray-900 dark:text-white">End Date <span class="text-base-content/40">(optional)</span></label>
                <div class="mt-2">
                  <input type="date" name="form[end_date]" value={@form["end_date"]}
                    class="w-full rounded-md bg-white px-3 py-1.5 text-base text-gray-900 outline-1 -outline-offset-1 outline-gray-300 focus:outline-2 focus:-outline-offset-2 focus:outline-emerald-600 sm:text-sm/6 dark:bg-white/5 dark:text-white dark:outline-white/10 dark:focus:outline-emerald-500" />
                </div>
              </div>

              <div class="sm:col-span-6">
                <label class="block text-sm/6 font-medium text-gray-900 dark:text-white">Notes <span class="text-base-content/40">(optional)</span></label>
                <div class="mt-2">
                  <textarea name="form[notes]" rows="3" placeholder="Internal notes about this recurring bill..."
                    class="w-full rounded-md bg-white px-3 py-1.5 text-base text-gray-900 outline-1 -outline-offset-1 outline-gray-300 placeholder:text-gray-400 focus:outline-2 focus:-outline-offset-2 focus:outline-emerald-600 sm:text-sm/6 dark:bg-white/5 dark:text-white dark:outline-white/10 dark:placeholder:text-gray-500 dark:focus:outline-emerald-500">{@form["notes"]}</textarea>
                </div>
              </div>

            </div>
          </div>

          <div class="flex justify-end gap-3">
            <.button type="button" navigate={@return_to}>Cancel</.button>
            <.button type="submit" variant="primary">
              {if @template, do: "Save Changes", else: "Create Template"}
            </.button>
          </div>
        </form>
      </div>
    </.page>
    """
  end

  defp assign_form(socket, nil) do
    today = Date.utc_today() |> Date.to_iso8601()
    assign(socket, :form, %{
      "vendor_id" => "",
      "description" => "",
      "amount" => "",
      "interval" => "monthly",
      "next_due_on" => today,
      "end_date" => "",
      "notes" => ""
    })
  end

  defp assign_form(socket, template) do
    assign(socket, :form, %{
      "vendor_id" => template.vendor_id,
      "description" => template.description || "",
      "amount" => if(template.amount, do: Decimal.to_string(template.amount), else: ""),
      "interval" => to_string(template.interval),
      "next_due_on" => if(template.next_due_on, do: Date.to_iso8601(template.next_due_on), else: ""),
      "end_date" => if(template.end_date, do: Date.to_iso8601(template.end_date), else: ""),
      "notes" => template.notes || ""
    })
  end

  defp load_vendors do
    {:ok, vendors} = Finance.list_vendors(authorize?: false)
    vendors |> Enum.filter(& &1.active) |> Enum.sort_by(& &1.name)
  end

  defp parse_decimal(""), do: nil
  defp parse_decimal(nil), do: nil
  defp parse_decimal(v), do: Decimal.new(v)

  defp parse_date(""), do: nil
  defp parse_date(nil), do: nil
  defp parse_date(v) do
    case Date.from_iso8601(v) do
      {:ok, d} -> d
      _ -> nil
    end
  end

  defp blank_to_nil(""), do: nil
  defp blank_to_nil(v), do: v
end
