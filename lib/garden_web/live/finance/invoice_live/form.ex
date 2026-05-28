defmodule GnomeGardenWeb.Finance.InvoiceLive.Form do
  use GnomeGardenWeb, :live_view

  alias GnomeGarden.Commercial
  alias GnomeGarden.Execution
  alias GnomeGarden.Finance
  alias GnomeGarden.Operations

  @impl true
  def mount(params, _session, socket) do
    invoice = if id = params["id"], do: load_invoice!(id, socket.assigns.current_user)

    agreement =
      if is_nil(invoice) and params["agreement_id"] do
        load_agreement!(params["agreement_id"], socket.assigns.current_user)
      end

    return_to = params["return_to"] || (if agreement, do: ~p"/commercial/agreements/#{agreement}", else: ~p"/finance/invoices")

    {:ok,
     socket
     |> assign(:invoice, invoice)
     |> assign(:agreement, agreement)
     |> assign(:agreement_selected, not is_nil(agreement))
     |> assign(:override_amounts, false)
     |> assign(:tax_total_preview, (invoice && invoice.tax_total) || Decimal.new("0"))
     |> assign(:total_amount_preview, (invoice && invoice.total_amount) || Decimal.new("0"))
     |> assign(:return_to, return_to)
     |> assign(:organizations, load_organizations(socket.assigns.current_user))
     |> assign(:agreements, load_agreements(socket.assigns.current_user))
     |> assign(:projects, load_projects(socket.assigns.current_user))
     |> assign(:page_title, page_title(invoice, agreement))
     |> assign_form()}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.page max_width="max-w-5xl" class="pb-8">
      <.page_header eyebrow="Finance">
        {@page_title}
        <:subtitle>
          Create operational invoices explicitly, or draft them from agreement-backed billable source records.
        </:subtitle>
        <:actions>
          <.button navigate={@return_to}>
            Back
          </.button>
        </:actions>
      </.page_header>

      <.section
        :if={@agreement}
        title="Source Agreement"
        description="This invoice is being drafted from billable agreement source records."
      >
        <div class="rounded-2xl border border-zinc-200 bg-zinc-50/70 px-4 py-4 dark:border-white/10 dark:bg-white/[0.03]">
          <p class="font-medium text-base-content">{@agreement.name}</p>
          <p class="text-sm text-base-content/50">
            {@agreement.reference_number || "No reference"} / {(@agreement.organization &&
                                                                  @agreement.organization.name) ||
              "No organization linked"}
          </p>
        </div>
      </.section>

      <.form for={@form} id="invoice-form" phx-change="validate" phx-submit="save" class="space-y-6">
        <.form_section
          title="Invoice Details"
          description="Define the operational billing header and the contract or execution context it belongs to."
        >
          <div class="grid grid-cols-1 gap-6 sm:grid-cols-6">
            <div class="sm:col-span-3">
              <.input field={@form[:invoice_number]} label="Invoice Number" placeholder="Auto-generated if left blank" />
            </div>
            <div class="sm:col-span-3">
              <.input field={@form[:due_on]} type="date" label="Due On" />
            </div>
            <div class="sm:col-span-3">
              <.input
                field={@form[:organization_id]}
                type="select"
                label="Organization"
                prompt="Select organization..."
                options={Enum.map(@organizations, &{&1.name, &1.id})}
              />
              <p class="mt-1.5 text-xs text-base-content/50">
                Organization not in the list?
                <.link navigate={~p"/operations/organizations/new?return_to=#{~p"/finance/invoices/new"}"} class="underline text-emerald-600 dark:text-emerald-400">Create one first</.link>.
              </p>
            </div>
            <div class="sm:col-span-3">
              <.input
                field={@form[:agreement_id]}
                type="select"
                label="Agreement"
                prompt="Select agreement..."
                options={Enum.map(@agreements, &{&1.name, &1.id})}
              />
              <p :if={Enum.empty?(@agreements)} class="mt-1.5 text-xs text-base-content/50">
                No agreements yet —
                <.link navigate={~p"/commercial/agreements/new?return_to=#{~p"/finance/invoices/new"}"} class="underline text-emerald-600 dark:text-emerald-400">create one first</.link>.
                (optional)
              </p>
              <p :if={not Enum.empty?(@agreements)} class="mt-1.5 text-xs text-base-content/50">
                Agreement not in the list?
                <.link navigate={~p"/commercial/agreements/new?return_to=#{~p"/finance/invoices/new"}"} class="underline text-emerald-600 dark:text-emerald-400">Create one first</.link>.
                When selected, amounts are auto-calculated from billable time entries and expenses.
              </p>
            </div>
            <div class="sm:col-span-3">
              <.input
                field={@form[:project_id]}
                type="select"
                label="Project"
                prompt="Select project..."
                options={Enum.map(@projects, &{&1.name, &1.id})}
              />
              <p :if={Enum.empty?(@projects)} class="mt-1.5 text-xs text-base-content/50">
                No projects yet —
                <.link navigate={~p"/execution/projects/new?return_to=#{~p"/finance/invoices/new"}"} class="underline text-emerald-600 dark:text-emerald-400">create one first</.link>.
                (optional)
              </p>
            </div>
            <div :if={not @agreement_selected} class="sm:col-span-3">
              <.input field={@form[:currency_code]} label="Currency Code" />
            </div>
            <div :if={@agreement_selected} class="col-span-full">
              <div class="flex items-center justify-between rounded-xl border border-zinc-200 bg-zinc-50/70 px-4 py-3 dark:border-white/10 dark:bg-white/[0.03]">
                <p class="text-sm text-base-content/60">Amounts will be calculated from the agreement on save.</p>
                <button
                  type="button"
                  phx-click="toggle_override_amounts"
                  class="text-sm font-medium text-emerald-600 dark:text-emerald-400 hover:underline"
                >
                  {if @override_amounts, do: "Use agreement amounts", else: "Override amounts manually"}
                </button>
              </div>
            </div>
            <div :if={not @agreement_selected or @override_amounts} class="sm:col-span-2">
              <.input field={@form[:subtotal]} label="Subtotal" type="number" step="0.01" />
            </div>
            <div class="sm:col-span-2">
              <.input field={@form[:tax_rate]} label="Tax Rate (%)" type="number" step="0.01" min="0" placeholder="0" />
            </div>
            <div :if={not @agreement_selected or @override_amounts} class="sm:col-span-4">
              <div class="rounded-lg border border-zinc-200 bg-zinc-50/70 px-4 py-3 text-sm dark:border-white/10 dark:bg-white/[0.03]">
                <div class="flex justify-between text-base-content/60 mb-1">
                  <span>Tax</span>
                  <span>${Decimal.to_string(Decimal.round(@tax_total_preview, 2))}</span>
                </div>
                <div class="flex justify-between font-semibold text-base-content">
                  <span>Total</span>
                  <span>${Decimal.to_string(Decimal.round(@total_amount_preview, 2))}</span>
                </div>
              </div>
            </div>
            <div class="col-span-full">
              <.input field={@form[:notes]} type="textarea" label="Notes" />
            </div>
          </div>
        </.form_section>

        <.section body_class="px-6 py-5 sm:px-7">
          <.form_actions
            cancel_path={@return_to}
            submit_label={submit_label(@invoice, @agreement)}
          />
        </.section>
      </.form>
    </.page>
    """
  end

  @impl true
  def handle_event("validate", %{"form" => params}, socket) do
    form = AshPhoenix.Form.validate(socket.assigns.form, params)

    {agreement_selected, override_amounts} =
      if socket.assigns.invoice do
        # Edit mode: always show amount fields directly
        {false, false}
      else
        selected = not_blank?(params["agreement_id"])
        {selected, if(selected, do: socket.assigns.override_amounts, else: false)}
      end

    {tax_total_preview, total_amount_preview} =
      case {Decimal.parse(params["subtotal"] || ""), Decimal.parse(params["tax_rate"] || "")} do
        {{subtotal, ""}, {rate, ""}} ->
          tax = Decimal.mult(subtotal, Decimal.div(rate, Decimal.new("100")))
          {tax, Decimal.add(subtotal, tax)}

        _ ->
          {Decimal.new("0"), Decimal.new("0")}
      end

    {:noreply,
     assign(socket,
       form: to_form(form),
       agreement_selected: agreement_selected,
       override_amounts: override_amounts,
       tax_total_preview: tax_total_preview,
       total_amount_preview: total_amount_preview
     )}
  end

  @impl true
  def handle_event("toggle_override_amounts", _params, socket) do
    {:noreply, assign(socket, :override_amounts, not socket.assigns.override_amounts)}
  end

  @impl true
  def handle_event("save", %{"form" => params}, socket) do
    # Only compute and inject derived tax fields when subtotal is explicitly
    # provided in the form (manual path or override-amounts path).
    # On the agreement path (no subtotal in params), CreateInvoiceFromAgreementSources
    # computes amounts itself — do not override with zeros.
    enriched_params =
      case Decimal.parse(params["subtotal"] || "") do
        {subtotal, ""} ->
          rate =
            case Decimal.parse(params["tax_rate"] || "") do
              {r, ""} -> r
              _ -> Decimal.new("0")
            end

          tax_total = Decimal.mult(subtotal, Decimal.div(rate, Decimal.new("100")))
          total_amount = Decimal.add(subtotal, tax_total)

          params
          |> Map.put("tax_total", Decimal.to_string(tax_total))
          |> Map.put("total_amount", Decimal.to_string(total_amount))
          |> Map.put("balance_amount", Decimal.to_string(total_amount))

        _ ->
          params
      end

    case AshPhoenix.Form.submit(socket.assigns.form, params: enriched_params) do
      {:ok, invoice} ->
        {:noreply,
         socket
         |> put_flash(:info, "Invoice #{success_label(socket.assigns.invoice, socket.assigns.agreement)}")
         |> push_navigate(to: ~p"/finance/invoices/#{invoice}")}

      {:error, form} ->
        {:noreply,
         socket
         |> put_flash(:error, "Please fix the errors below.")
         |> assign(form: to_form(form))}
    end
  end

  defp assign_form(
         %{assigns: %{invoice: invoice, agreement: agreement, current_user: actor}} = socket
       ) do
    form =
      cond do
        invoice ->
          AshPhoenix.Form.for_update(invoice, :update, actor: actor, domain: Finance)

        agreement ->
          AshPhoenix.Form.for_create(
            Finance.Invoice,
            :create_from_agreement_sources,
            actor: actor,
            domain: Finance,
            params: invoice_defaults_from_agreement(agreement),
            prepare_source: fn changeset ->
              Ash.Changeset.set_argument(changeset, :agreement_id, agreement.id)
            end
          )

        true ->
          default_rate = Application.get_env(:gnome_garden, :default_tax_rate, "0")

          AshPhoenix.Form.for_create(Finance.Invoice, :create,
            actor: actor,
            domain: Finance,
            params: %{"tax_rate" => to_string(default_rate)}
          )
      end

    assign(socket, :form, to_form(form))
  end

  defp load_invoice!(id, actor) do
    case Finance.get_invoice(id, actor: actor) do
      {:ok, invoice} -> invoice
      {:error, error} -> raise "failed to load invoice #{id}: #{inspect(error)}"
    end
  end

  defp load_agreement!(id, actor) do
    case Commercial.get_agreement(id, actor: actor, load: [:organization]) do
      {:ok, agreement} -> agreement
      {:error, error} -> raise "failed to load agreement #{id}: #{inspect(error)}"
    end
  end

  defp load_organizations(actor) do
    case Operations.list_organizations(actor: actor) do
      {:ok, organizations} -> Enum.sort_by(organizations, &String.downcase(&1.name || ""))
      {:error, error} -> raise "failed to load organizations: #{inspect(error)}"
    end
  end

  defp load_agreements(actor) do
    case Commercial.list_agreements(actor: actor) do
      {:ok, agreements} -> Enum.sort_by(agreements, &String.downcase(&1.name || ""))
      {:error, error} -> raise "failed to load agreements: #{inspect(error)}"
    end
  end

  defp load_projects(actor) do
    case Execution.list_projects(actor: actor) do
      {:ok, projects} -> Enum.sort_by(projects, &String.downcase(&1.name || ""))
      {:error, error} -> raise "failed to load projects: #{inspect(error)}"
    end
  end

  defp invoice_defaults_from_agreement(agreement) do
    %{
      "due_on" => agreement.end_on,
      "notes" => agreement.notes
    }
  end

  defp page_title(invoice, _agreement) when not is_nil(invoice), do: "Edit Invoice"
  defp page_title(nil, agreement) when not is_nil(agreement), do: "Draft Invoice From Agreement"
  defp page_title(nil, nil), do: "New Invoice"

  defp submit_label(invoice, _agreement) when not is_nil(invoice), do: "Update Invoice"
  defp submit_label(nil, agreement) when not is_nil(agreement), do: "Draft Invoice"
  defp submit_label(nil, nil), do: "Create Invoice"

  defp success_label(invoice, _agreement) when not is_nil(invoice), do: "updated"
  defp success_label(nil, agreement) when not is_nil(agreement), do: "drafted"
  defp success_label(nil, nil), do: "created"

  defp not_blank?(nil), do: false
  defp not_blank?(""), do: false
  defp not_blank?(_), do: true
end
