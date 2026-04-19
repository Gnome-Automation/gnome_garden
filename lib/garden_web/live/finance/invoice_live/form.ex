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

    {:ok,
     socket
     |> assign(:invoice, invoice)
     |> assign(:agreement, agreement)
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
          <.button navigate={~p"/finance/invoices"}>
            <.icon name="hero-arrow-left" class="size-4" /> Back to invoices
          </.button>
        </:actions>
      </.page_header>

      <.section
        :if={@agreement}
        title="Source Agreement"
        description="This invoice is being drafted from billable agreement source records."
      >
        <div class="rounded-2xl border border-zinc-200 bg-zinc-50/70 px-4 py-4 dark:border-white/10 dark:bg-white/[0.03]">
          <p class="font-medium text-zinc-900 dark:text-white">{@agreement.name}</p>
          <p class="text-sm text-zinc-500 dark:text-zinc-400">
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
              <.input field={@form[:invoice_number]} label="Invoice Number" />
            </div>
            <div class="sm:col-span-3">
              <.input field={@form[:due_on]} type="date" label="Due On" />
            </div>
            <div :if={is_nil(@agreement)} class="sm:col-span-3">
              <.input
                field={@form[:organization_id]}
                type="select"
                label="Organization"
                prompt="Select organization..."
                options={Enum.map(@organizations, &{&1.name, &1.id})}
              />
            </div>
            <div :if={is_nil(@agreement)} class="sm:col-span-3">
              <.input
                field={@form[:agreement_id]}
                type="select"
                label="Agreement"
                prompt="Select agreement..."
                options={Enum.map(@agreements, &{&1.name, &1.id})}
              />
            </div>
            <div :if={is_nil(@agreement)} class="sm:col-span-3">
              <.input
                field={@form[:project_id]}
                type="select"
                label="Project"
                prompt="Select project..."
                options={Enum.map(@projects, &{&1.name, &1.id})}
              />
            </div>
            <div :if={is_nil(@agreement)} class="sm:col-span-3">
              <.input field={@form[:currency_code]} label="Currency Code" />
            </div>
            <div :if={is_nil(@agreement)} class="sm:col-span-2">
              <.input field={@form[:subtotal]} label="Subtotal" type="number" step="0.01" />
            </div>
            <div :if={is_nil(@agreement)} class="sm:col-span-2">
              <.input field={@form[:tax_total]} label="Tax Total" type="number" step="0.01" />
            </div>
            <div :if={is_nil(@agreement)} class="sm:col-span-2">
              <.input field={@form[:total_amount]} label="Total Amount" type="number" step="0.01" />
            </div>
            <div :if={is_nil(@agreement)} class="sm:col-span-3">
              <.input field={@form[:balance_amount]} label="Balance Amount" type="number" step="0.01" />
            </div>
            <div class="col-span-full">
              <.input field={@form[:notes]} type="textarea" label="Notes" />
            </div>
          </div>
        </.form_section>

        <.section body_class="px-6 py-5 sm:px-7">
          <.form_actions
            cancel_path={~p"/finance/invoices"}
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
    {:noreply, assign(socket, form: to_form(form))}
  end

  @impl true
  def handle_event("save", %{"form" => params}, socket) do
    case AshPhoenix.Form.submit(socket.assigns.form, params: params) do
      {:ok, invoice} ->
        {:noreply,
         socket
         |> put_flash(
           :info,
           "Invoice #{success_label(socket.assigns.invoice, socket.assigns.agreement)}"
         )
         |> push_navigate(to: ~p"/finance/invoices/#{invoice}")}

      {:error, form} ->
        {:noreply, assign(socket, form: to_form(form))}
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
          AshPhoenix.Form.for_create(Finance.Invoice, :create, actor: actor, domain: Finance)
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
      "invoice_number" => agreement.reference_number,
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
end
