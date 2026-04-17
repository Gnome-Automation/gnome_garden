defmodule GnomeGardenWeb.CRM.CompanyLive.Form do
  use GnomeGardenWeb, :live_view

  alias GnomeGarden.CRM.Forms, as: CRMForms

  @impl true
  def mount(params, _session, socket) do
    company =
      if id = params["id"] do
        CRMForms.get_company!(id, actor: socket.assigns.current_user)
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
        CRMForms.form_to_update_company(company, actor: actor)
      else
        CRMForms.form_to_create_company(actor: actor)
      end

    assign(socket, form: to_form(form))
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.header>
      {@page_title}
    </.header>

    <.form for={@form} id="company-form" phx-change="validate" phx-submit="save">
      <div class="space-y-12">
        <div class="border-b border-gray-900/10 pb-12 dark:border-white/10">
          <h2 class="text-base/7 font-semibold text-gray-900 dark:text-white">Company Details</h2>
          <p class="mt-1 text-sm/6 text-gray-600 dark:text-gray-400">
            Basic company information and contact details.
          </p>
          <div class="mt-10 grid grid-cols-1 gap-x-6 gap-y-8 sm:grid-cols-6">
            <div class="sm:col-span-3">
              <.input field={@form[:name]} label="Company Name" required />
            </div>
            <div class="sm:col-span-3">
              <.input field={@form[:legal_name]} label="Legal Name" />
            </div>
            <div class="sm:col-span-3">
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
            </div>
            <div class="sm:col-span-3">
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
            <div class="sm:col-span-3">
              <.input field={@form[:website]} label="Website" type="url" />
            </div>
            <div class="sm:col-span-3">
              <.input field={@form[:phone]} label="Phone" type="tel" />
            </div>
          </div>
        </div>

        <div class="border-b border-gray-900/10 pb-12 dark:border-white/10">
          <h2 class="text-base/7 font-semibold text-gray-900 dark:text-white">Address</h2>
          <p class="mt-1 text-sm/6 text-gray-600 dark:text-gray-400">
            Company physical address.
          </p>
          <div class="mt-10 grid grid-cols-1 gap-x-6 gap-y-8 sm:grid-cols-6">
            <div class="col-span-full">
              <.input field={@form[:address]} label="Street Address" />
            </div>
            <div class="sm:col-span-2">
              <.input field={@form[:city]} label="City" />
            </div>
            <div class="sm:col-span-2">
              <.input field={@form[:state]} label="State" />
            </div>
            <div class="sm:col-span-2">
              <.input field={@form[:postal_code]} label="Postal Code" />
            </div>
          </div>
        </div>

        <div class="border-b border-gray-900/10 pb-12 dark:border-white/10">
          <h2 class="text-base/7 font-semibold text-gray-900 dark:text-white">Additional</h2>
          <p class="mt-1 text-sm/6 text-gray-600 dark:text-gray-400">
            Region, source, and other company metadata.
          </p>
          <div class="mt-10 grid grid-cols-1 gap-x-6 gap-y-8 sm:grid-cols-6">
            <div class="sm:col-span-3">
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
            </div>
            <div class="sm:col-span-3">
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
            <div class="sm:col-span-3">
              <.input field={@form[:employee_count]} label="Employee Count" type="number" />
            </div>
            <div class="sm:col-span-3">
              <.input
                field={@form[:annual_revenue]}
                label="Annual Revenue"
                type="number"
                step="0.01"
              />
            </div>
            <div class="col-span-full">
              <.input field={@form[:description]} type="textarea" label="Description" />
            </div>
          </div>
        </div>
      </div>

      <div class="mt-6 flex items-center justify-end gap-x-6">
        <.button type="button" navigate={~p"/crm/companies"}>Cancel</.button>
        <.button type="submit" variant="primary" phx-disable-with="Saving...">Save</.button>
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
