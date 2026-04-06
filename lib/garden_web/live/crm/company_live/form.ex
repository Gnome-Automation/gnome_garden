defmodule GnomeGardenWeb.CRM.CompanyLive.Form do
  use GnomeGardenWeb, :live_view

  alias GnomeGarden.Sales

  @impl true
  def mount(params, _session, socket) do
    company =
      if id = params["id"] do
        Sales.get_company!(id, actor: socket.assigns.current_user)
      else
        nil
      end

    {:ok,
     socket
     |> assign(:company, company)
     |> assign(:page_title, if(company, do: "Edit #{company.name}", else: "New Company"))
     |> assign_form()}
  end

  defp assign_form(%{assigns: %{company: company, current_user: actor}} = socket) do
    form =
      if company do
        Sales.form_to_update_company(company, actor: actor)
      else
        Sales.form_to_create_company(actor: actor)
      end

    assign(socket, form: to_form(form))
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.header>
      {@page_title}
    </.header>

    <.form
      for={@form}
      id="company-form"
      phx-change="validate"
      phx-submit="save"
      class="space-y-6 max-w-2xl"
    >
      <div class="grid grid-cols-1 gap-6 sm:grid-cols-2">
        <.input field={@form[:name]} label="Company Name" required />
        <.input field={@form[:legal_name]} label="Legal Name" />
      </div>

      <div class="grid grid-cols-1 gap-6 sm:grid-cols-2">
        <.input
          field={@form[:company_type]}
          type="select"
          label="Type"
          options={[
            {"Prospect", :prospect},
            {"Customer", :customer},
            {"Partner", :partner},
            {"Vendor", :vendor}
          ]}
        />
        <.input
          field={@form[:status]}
          type="select"
          label="Status"
          options={[
            {"Active", :active},
            {"Inactive", :inactive},
            {"Churned", :churned}
          ]}
        />
      </div>

      <div class="grid grid-cols-1 gap-6 sm:grid-cols-2">
        <.input field={@form[:website]} label="Website" type="url" />
        <.input field={@form[:phone]} label="Phone" type="tel" />
      </div>

      <.input field={@form[:address]} label="Street Address" />

      <div class="grid grid-cols-1 gap-6 sm:grid-cols-3">
        <.input field={@form[:city]} label="City" />
        <.input field={@form[:state]} label="State" />
        <.input field={@form[:postal_code]} label="Postal Code" />
      </div>

      <div class="grid grid-cols-1 gap-6 sm:grid-cols-2">
        <.input
          field={@form[:region]}
          type="select"
          label="Region"
          prompt="Select region..."
          options={[
            {"Orange County", :oc},
            {"Los Angeles", :la},
            {"Inland Empire", :ie},
            {"San Diego", :sd},
            {"SoCal", :socal},
            {"NorCal", :norcal},
            {"California", :ca},
            {"National", :national},
            {"Other", :other}
          ]}
        />
        <.input
          field={@form[:source]}
          type="select"
          label="Source"
          prompt="Select source..."
          options={[
            {"Bid", :bid},
            {"Prospect", :prospect},
            {"Referral", :referral},
            {"Inbound", :inbound},
            {"Other", :other}
          ]}
        />
      </div>

      <div class="grid grid-cols-1 gap-6 sm:grid-cols-2">
        <.input field={@form[:employee_count]} label="Employee Count" type="number" />
        <.input field={@form[:annual_revenue]} label="Annual Revenue" type="number" step="0.01" />
      </div>

      <.input field={@form[:description]} type="textarea" label="Description" />

      <div class="flex gap-4 pt-4">
        <.button type="submit" variant="primary" phx-disable-with="Saving...">
          Save Company
        </.button>
        <.button type="button" navigate={~p"/crm/companies"}>Cancel</.button>
      </div>
    </.form>
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
      {:ok, company} ->
        {:noreply,
         socket
         |> put_flash(
           :info,
           "Company #{if socket.assigns.company, do: "updated", else: "created"}"
         )
         |> push_navigate(to: ~p"/crm/companies/#{company}")}

      {:error, form} ->
        {:noreply, assign(socket, form: to_form(form))}
    end
  end
end
