defmodule GnomeGardenWeb.Finance.RecurringInvoiceLive.Form do
  use GnomeGardenWeb, :live_view

  import GnomeGardenWeb.Finance.Helpers

  alias GnomeGarden.Finance
  alias GnomeGarden.Finance.RecurringInvoice
  alias GnomeGarden.Finance.RecurringInvoiceLine
  alias GnomeGarden.Operations
  alias GnomeGarden.Commercial

  require Ash.Query

  @empty_line %{
    "description" => "",
    "quantity" => "1",
    "unit_price" => "",
    "line_kind" => "service"
  }

  @impl true
  def mount(params, _session, socket) do
    organizations = Ash.read!(Operations.Organization, domain: Operations, authorize?: false)
    agreements = Ash.read!(Commercial.Agreement, domain: Commercial, authorize?: false)

    {template, lines, title} =
      case params["id"] do
        nil ->
          {nil, [@empty_line], "New Recurring Invoice"}

        id ->
          t =
            RecurringInvoice
            |> Ash.Query.load([:recurring_invoice_lines])
            |> Ash.get!(id, domain: Finance, authorize?: false)

          existing_lines =
            Enum.map(t.recurring_invoice_lines, fn l ->
              %{
                "description" => l.description,
                "quantity" => Decimal.to_string(l.quantity),
                "unit_price" => Decimal.to_string(l.unit_price),
                "line_kind" => to_string(l.line_kind)
              }
            end)

          {t, existing_lines, "Edit Recurring Invoice"}
      end

    return_to = params["return_to"] || ~p"/finance/recurring-invoices"

    {:ok,
     socket
     |> assign(:page_title, title)
     |> assign(:template, template)
     |> assign(:lines, lines)
     |> assign(:organizations, organizations)
     |> assign(:agreements, agreements)
     |> assign(:return_to, return_to)
     |> assign(:errors, [])
     |> assign(:preselected_org_id, params["organization_id"])}
  end

  @impl true
  def handle_event("add_line", _params, socket) do
    {:noreply, assign(socket, :lines, socket.assigns.lines ++ [@empty_line])}
  end

  @impl true
  def handle_event("remove_line", %{"index" => idx_str}, socket) do
    idx = String.to_integer(idx_str)
    new_lines = List.delete_at(socket.assigns.lines, idx)
    {:noreply, assign(socket, :lines, new_lines)}
  end

  @impl true
  def handle_event("save", %{"template" => params} = form_params, socket) do
    lines = normalize_lines(form_params["lines"])

    with {:ok, template} <- save_template(socket.assigns.template, params),
         :ok <- save_lines(template, lines) do
      {:noreply,
       socket
       |> put_flash(:info, "Recurring invoice saved.")
       |> push_navigate(to: socket.assigns.return_to)}
    else
      {:error, errors} ->
        {:noreply, assign(socket, :errors, errors)}
    end
  end

  defp normalize_lines(nil), do: []
  defp normalize_lines(lines) when is_list(lines), do: lines
  defp normalize_lines(lines) when is_map(lines) do
    lines
    |> Enum.sort_by(fn {k, _} -> String.to_integer(k) end)
    |> Enum.map(fn {_, v} -> v end)
  end

  defp save_template(nil, params) do
    start_date = parse_date(params["start_date"])
    attrs = build_attrs(params) |> Map.put(:next_generation_date, start_date)

    case Finance.create_recurring_invoice(attrs, authorize?: false) do
      {:ok, t} -> {:ok, t}
      {:error, err} -> {:error, [inspect(err)]}
    end
  end

  defp save_template(template, params) do
    attrs = build_attrs(params)

    case Finance.update_recurring_invoice(template, attrs, authorize?: false) do
      {:ok, t} -> {:ok, t}
      {:error, err} -> {:error, [inspect(err)]}
    end
  end

  defp build_attrs(params) do
    %{
      organization_id: params["organization_id"],
      agreement_id: blank_to_nil(params["agreement_id"]),
      interval: String.to_existing_atom(params["interval"]),
      net_terms_days: String.to_integer(params["net_terms_days"] || "30"),
      start_date: parse_date(params["start_date"]),
      end_date: parse_date(params["end_date"]),
      delivery_mode: String.to_existing_atom(params["delivery_mode"]),
      status: String.to_existing_atom(params["status"]),
      tax_rate: parse_decimal(params["tax_rate"]),
      notes: blank_to_nil(params["notes"])
    }
  end

  defp save_lines(template, lines) do
    existing =
      RecurringInvoiceLine
      |> Ash.Query.filter(recurring_invoice_id == ^template.id)
      |> Ash.read!(domain: Finance, authorize?: false)

    Enum.each(existing, &Ash.destroy!(&1, domain: Finance, authorize?: false))

    lines
    |> Enum.with_index(1)
    |> Enum.each(fn {line, idx} ->
      qty = parse_decimal(line["quantity"])
      price = parse_decimal(line["unit_price"])
      total = Decimal.mult(qty, price)

      Finance.create_recurring_invoice_line(
        %{
          recurring_invoice_id: template.id,
          line_number: idx,
          description: line["description"],
          quantity: qty,
          unit_price: price,
          line_total: total,
          line_kind: String.to_existing_atom(line["line_kind"] || "service")
        },
        authorize?: false
      )
    end)

    :ok
  end

  defp parse_date(nil), do: nil
  defp parse_date(""), do: nil
  defp parse_date(str), do: Date.from_iso8601!(str)

  defp parse_decimal(nil), do: Decimal.new(0)
  defp parse_decimal(""), do: Decimal.new(0)
  defp parse_decimal(str), do: Decimal.new(str)

  defp blank_to_nil(nil), do: nil
  defp blank_to_nil(""), do: nil
  defp blank_to_nil(v), do: v

  defp compute_subtotal(lines) do
    Enum.reduce(lines, Decimal.new(0), fn line, acc ->
      qty = parse_decimal_safe(line["quantity"])
      price = parse_decimal_safe(line["unit_price"])
      Decimal.add(acc, Decimal.mult(qty, price))
    end)
  end

  defp parse_decimal_safe(nil), do: Decimal.new(0)
  defp parse_decimal_safe(""), do: Decimal.new(0)
  defp parse_decimal_safe(s) do
    case Decimal.parse(s) do
      {d, ""} -> d
      _ -> Decimal.new(0)
    end
  end

  defp schedule_preview(nil, _interval), do: ""
  defp schedule_preview(_date, nil), do: ""
  defp schedule_preview(date, interval) do
    next1 = GnomeGarden.Finance.RecurringInvoiceWorker.advance_date(date, interval)
    next2 = GnomeGarden.Finance.RecurringInvoiceWorker.advance_date(next1, interval)
    " → #{format_date(next1)} → #{format_date(next2)} → …"
  end

  defp selected_org?(nil, org_id, preselected), do: preselected != nil and preselected == to_string(org_id)
  defp selected_org?(template, org_id, _pre), do: to_string(template.organization_id) == to_string(org_id)

  defp selected_interval?(nil, :monthly), do: true
  defp selected_interval?(nil, _), do: false
  defp selected_interval?(t, interval), do: t.interval == interval

  defp selected_net_terms?(nil, 30), do: true
  defp selected_net_terms?(nil, _), do: false
  defp selected_net_terms?(t, days), do: t.net_terms_days == days

  defp selected_delivery?(nil, :auto_issue), do: true
  defp selected_delivery?(nil, _), do: false
  defp selected_delivery?(t, mode), do: t.delivery_mode == mode

  defp selected_status?(nil, :active), do: true
  defp selected_status?(nil, _), do: false
  defp selected_status?(t, status), do: t.status == status

  defp date_value(nil), do: ""
  defp date_value(%Date{} = d), do: Date.to_iso8601(d)

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

      <form phx-submit="save" class="space-y-8">
        <%!-- Section 1: Schedule --%>
        <div class="border-b border-gray-900/10 pb-12 dark:border-white/10">
          <h2 class="text-base/7 font-semibold text-gray-900 dark:text-white">Schedule</h2>
          <p class="mt-1 text-sm/6 text-gray-600 dark:text-gray-400">Who to bill, how often, and when.</p>

          <div class="mt-6 grid grid-cols-1 gap-x-6 gap-y-8 sm:grid-cols-6">
            <%!-- Client --%>
            <div class="sm:col-span-3">
              <label class="block text-sm/6 font-medium text-gray-900 dark:text-white">
                Client <span class="text-red-500">*</span>
              </label>
              <div class="mt-2">
                <select name="template[organization_id]" class="block w-full appearance-none rounded-md bg-white px-3 py-1.5 text-base text-gray-900 outline-1 -outline-offset-1 outline-gray-300 focus:outline-2 focus:-outline-offset-2 focus:outline-emerald-600 sm:text-sm/6 dark:bg-white/5 dark:text-white dark:outline-white/10 dark:focus:outline-emerald-500">
                  <option value="">Select client…</option>
                  <%= for org <- @organizations do %>
                    <option value={org.id} selected={selected_org?(@template, org.id, @preselected_org_id)}>{org.name}</option>
                  <% end %>
                </select>
              </div>
              <p class="mt-1.5 text-xs text-base-content/50">
                Organization not in the list?
                <.link navigate={~p"/operations/organizations/new?return_to=#{~p"/finance/recurring-invoices/new"}"} class="underline text-emerald-600 dark:text-emerald-400">Create one first</.link>.
              </p>
            </div>

            <%!-- Agreement --%>
            <div class="sm:col-span-3">
              <label class="block text-sm/6 font-medium text-gray-900 dark:text-white">
                Agreement <span class="text-gray-400 font-normal">(optional)</span>
              </label>
              <div class="mt-2">
                <select name="template[agreement_id]" class="block w-full appearance-none rounded-md bg-white px-3 py-1.5 text-base text-gray-900 outline-1 -outline-offset-1 outline-gray-300 focus:outline-2 focus:-outline-offset-2 focus:outline-emerald-600 sm:text-sm/6 dark:bg-white/5 dark:text-white dark:outline-white/10 dark:focus:outline-emerald-500">
                  <option value="">None</option>
                  <%= for agr <- @agreements do %>
                    <option value={agr.id} selected={@template && to_string(@template.agreement_id) == to_string(agr.id)}>{agr.name}</option>
                  <% end %>
                </select>
              </div>
              <p class="mt-1.5 text-xs text-base-content/50">
                No agreement yet?
                <.link navigate={~p"/commercial/agreements/new?return_to=#{~p"/finance/recurring-invoices/new"}"} class="underline text-emerald-600 dark:text-emerald-400">Create one first</.link>.
              </p>
            </div>

            <%!-- Interval --%>
            <div class="sm:col-span-2">
              <label class="block text-sm/6 font-medium text-gray-900 dark:text-white">
                Repeats <span class="text-red-500">*</span>
              </label>
              <div class="mt-2">
                <select name="template[interval]" class="block w-full appearance-none rounded-md bg-white px-3 py-1.5 text-base text-gray-900 outline-1 -outline-offset-1 outline-gray-300 focus:outline-2 focus:-outline-offset-2 focus:outline-emerald-600 sm:text-sm/6 dark:bg-white/5 dark:text-white dark:outline-white/10 dark:focus:outline-emerald-500">
                  <option value="daily" selected={selected_interval?(@template, :daily)}>Daily</option>
                  <option value="weekly" selected={selected_interval?(@template, :weekly)}>Weekly</option>
                  <option value="monthly" selected={selected_interval?(@template, :monthly)}>Monthly</option>
                  <option value="quarterly" selected={selected_interval?(@template, :quarterly)}>Quarterly</option>
                  <option value="semi_annually" selected={selected_interval?(@template, :semi_annually)}>Semi-annually</option>
                  <option value="annually" selected={selected_interval?(@template, :annually)}>Annually</option>
                </select>
              </div>
            </div>

            <%!-- Net Terms --%>
            <div class="sm:col-span-2">
              <label class="block text-sm/6 font-medium text-gray-900 dark:text-white">Net Terms</label>
              <div class="mt-2">
                <select name="template[net_terms_days]" class="block w-full appearance-none rounded-md bg-white px-3 py-1.5 text-base text-gray-900 outline-1 -outline-offset-1 outline-gray-300 focus:outline-2 focus:-outline-offset-2 focus:outline-emerald-600 sm:text-sm/6 dark:bg-white/5 dark:text-white dark:outline-white/10 dark:focus:outline-emerald-500">
                  <option value="15" selected={selected_net_terms?(@template, 15)}>Net 15</option>
                  <option value="30" selected={selected_net_terms?(@template, 30)}>Net 30</option>
                  <option value="45" selected={selected_net_terms?(@template, 45)}>Net 45</option>
                  <option value="60" selected={selected_net_terms?(@template, 60)}>Net 60</option>
                  <option value="90" selected={selected_net_terms?(@template, 90)}>Net 90</option>
                </select>
              </div>
            </div>

            <%!-- Delivery mode --%>
            <div class="sm:col-span-2">
              <label class="block text-sm/6 font-medium text-gray-900 dark:text-white">When generated</label>
              <div class="mt-2">
                <select name="template[delivery_mode]" class="block w-full appearance-none rounded-md bg-white px-3 py-1.5 text-base text-gray-900 outline-1 -outline-offset-1 outline-gray-300 focus:outline-2 focus:-outline-offset-2 focus:outline-emerald-600 sm:text-sm/6 dark:bg-white/5 dark:text-white dark:outline-white/10 dark:focus:outline-emerald-500">
                  <option value="auto_issue" selected={selected_delivery?(@template, :auto_issue)}>Auto-issue & send</option>
                  <option value="draft" selected={selected_delivery?(@template, :draft)}>Save as draft</option>
                </select>
              </div>
            </div>

            <%!-- First Invoice Date --%>
            <div class="sm:col-span-3">
              <label class="block text-sm/6 font-medium text-gray-900 dark:text-white">
                First Invoice Date <span class="text-red-500">*</span>
              </label>
              <div class="mt-2">
                <input
                  type="date"
                  name="template[start_date]"
                  value={date_value(@template && @template.start_date)}
                  class="block w-full rounded-md bg-white px-3 py-1.5 text-base text-gray-900 outline-1 -outline-offset-1 outline-gray-300 focus:outline-2 focus:-outline-offset-2 focus:outline-emerald-600 sm:text-sm/6 dark:bg-white/5 dark:text-white dark:outline-white/10 dark:focus:outline-emerald-500"
                />
              </div>
            </div>

            <%!-- End Date --%>
            <div class="sm:col-span-3">
              <label class="block text-sm/6 font-medium text-gray-900 dark:text-white">
                End Date <span class="text-gray-400 font-normal">(optional)</span>
              </label>
              <div class="mt-2">
                <input
                  type="date"
                  name="template[end_date]"
                  value={date_value(@template && @template.end_date)}
                  class="block w-full rounded-md bg-white px-3 py-1.5 text-base text-gray-900 outline-1 -outline-offset-1 outline-gray-300 focus:outline-2 focus:-outline-offset-2 focus:outline-emerald-600 sm:text-sm/6 dark:bg-white/5 dark:text-white dark:outline-white/10 dark:focus:outline-emerald-500"
                />
              </div>
            </div>

            <%!-- Status --%>
            <div class="sm:col-span-2">
              <label class="block text-sm/6 font-medium text-gray-900 dark:text-white">Status</label>
              <div class="mt-2">
                <select name="template[status]" class="block w-full appearance-none rounded-md bg-white px-3 py-1.5 text-base text-gray-900 outline-1 -outline-offset-1 outline-gray-300 focus:outline-2 focus:-outline-offset-2 focus:outline-emerald-600 sm:text-sm/6 dark:bg-white/5 dark:text-white dark:outline-white/10 dark:focus:outline-emerald-500">
                  <option value="active" selected={selected_status?(@template, :active)}>Active</option>
                  <option value="paused" selected={selected_status?(@template, :paused)}>Paused</option>
                </select>
              </div>
            </div>
          </div>
        </div>

        <%!-- Section 2: Line Items --%>
        <div>
          <h2 class="text-base/7 font-semibold text-gray-900 dark:text-white">Line Items</h2>
          <p class="mt-1 text-sm/6 text-gray-600 dark:text-gray-400">Same items will appear on every generated invoice.</p>

          <div class="mt-6 overflow-hidden rounded-lg border border-gray-200 dark:border-white/10">
            <table class="min-w-full divide-y divide-gray-200 dark:divide-white/10">
              <thead>
                <tr class="bg-gray-50 dark:bg-white/5">
                  <th class="px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider dark:text-gray-400">Description</th>
                  <th class="px-4 py-3 text-right text-xs font-medium text-gray-500 uppercase tracking-wider dark:text-gray-400 w-24">Qty</th>
                  <th class="px-4 py-3 text-right text-xs font-medium text-gray-500 uppercase tracking-wider dark:text-gray-400 w-32">Unit Price</th>
                  <th class="px-4 py-3 text-right text-xs font-medium text-gray-500 uppercase tracking-wider dark:text-gray-400 w-32">Total</th>
                  <th class="w-10"></th>
                </tr>
              </thead>
              <tbody class="divide-y divide-gray-100 dark:divide-white/5">
                <%= for {line, idx} <- Enum.with_index(@lines) do %>
                  <tr>
                    <td class="px-4 py-2">
                      <input type="text" name={"lines[#{idx}][description]"} value={line["description"]} placeholder="Description" class="block w-full rounded-md bg-white px-3 py-1.5 text-sm text-gray-900 outline-1 -outline-offset-1 outline-gray-300 focus:outline-2 focus:-outline-offset-2 focus:outline-emerald-600 dark:bg-white/5 dark:text-white dark:outline-white/10 dark:focus:outline-emerald-500" />
                      <input type="hidden" name={"lines[#{idx}][line_kind]"} value={line["line_kind"] || "service"} />
                    </td>
                    <td class="px-4 py-2">
                      <input type="number" name={"lines[#{idx}][quantity]"} value={line["quantity"]} step="0.01" class="block w-full rounded-md bg-white px-3 py-1.5 text-sm text-right text-gray-900 outline-1 -outline-offset-1 outline-gray-300 focus:outline-2 focus:-outline-offset-2 focus:outline-emerald-600 dark:bg-white/5 dark:text-white dark:outline-white/10 dark:focus:outline-emerald-500" />
                    </td>
                    <td class="px-4 py-2">
                      <input type="number" name={"lines[#{idx}][unit_price]"} value={line["unit_price"]} step="0.01" placeholder="0.00" class="block w-full rounded-md bg-white px-3 py-1.5 text-sm text-right text-gray-900 outline-1 -outline-offset-1 outline-gray-300 focus:outline-2 focus:-outline-offset-2 focus:outline-emerald-600 dark:bg-white/5 dark:text-white dark:outline-white/10 dark:focus:outline-emerald-500" />
                    </td>
                    <td class="px-4 py-2 text-right text-sm text-gray-900 dark:text-white">
                      {format_currency(Decimal.mult(parse_decimal_safe(line["quantity"]), parse_decimal_safe(line["unit_price"])))}
                    </td>
                    <td class="px-4 py-2 text-center">
                      <button type="button" phx-click="remove_line" phx-value-index={idx} class="text-red-500 hover:text-red-700 text-sm font-medium px-2 py-1 rounded hover:bg-red-50 dark:hover:bg-red-900/20">✕</button>
                    </td>
                  </tr>
                <% end %>
              </tbody>
            </table>
            <div class="px-4 py-3 border-t border-gray-100 dark:border-white/5">
              <button type="button" phx-click="add_line" class="inline-flex items-center gap-1.5 rounded-md bg-emerald-600 px-3 py-2 text-sm font-semibold text-white shadow-xs hover:bg-emerald-500 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-emerald-600">
                + Add line
              </button>
            </div>
          </div>

          <%!-- Tax + Total --%>
          <div class="mt-4 flex items-end justify-between gap-6">
            <div class="w-48">
              <label class="block text-sm/6 font-medium text-gray-900 dark:text-white">
                Tax Rate <span class="text-gray-400 font-normal">(optional %)</span>
              </label>
              <div class="mt-2">
                <input
                  type="number"
                  name="template[tax_rate]"
                  value={(@template && Decimal.to_string(@template.tax_rate)) || "0"}
                  step="0.01"
                  min="0"
                  max="100"
                  class="block w-full rounded-md bg-white px-3 py-1.5 text-base text-gray-900 outline-1 -outline-offset-1 outline-gray-300 focus:outline-2 focus:-outline-offset-2 focus:outline-emerald-600 sm:text-sm/6 dark:bg-white/5 dark:text-white dark:outline-white/10 dark:focus:outline-emerald-500"
                />
              </div>
            </div>
            <div class="text-right">
              <div class="text-sm text-gray-500 dark:text-gray-400">Total per invoice</div>
              <div class="text-2xl font-bold text-gray-900 dark:text-white">
                {format_currency(compute_subtotal(@lines))}
              </div>
            </div>
          </div>

          <%!-- Schedule Preview --%>
          <p class="mt-3 text-sm text-gray-500 dark:text-gray-400">
            Next invoice: <strong class="text-gray-700 dark:text-gray-300">{format_date(@template && @template.next_generation_date)}</strong>
            {schedule_preview(@template && @template.next_generation_date, @template && @template.interval)}
          </p>
        </div>

        <%!-- Actions --%>
        <div class="flex justify-end gap-4 pt-4 border-t border-gray-200 dark:border-white/10">
          <.button navigate={@return_to}>Cancel</.button>
          <.button type="submit" variant="primary">Save Recurring Invoice</.button>
        </div>
      </form>
    </.page>
    """
  end
end
