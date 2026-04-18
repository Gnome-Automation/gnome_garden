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
    <.page max_width="max-w-5xl" class="pb-8">
      <.page_header eyebrow="CRM">
        {@page_title}
        <:subtitle>
          {if @company,
            do: "Update company details, market metadata, and location data.",
            else: "Capture a company record that can anchor contacts, pursuits, and delivery work."}
        </:subtitle>
        <:actions>
          <.button navigate={~p"/crm/companies"}>
            <.icon name="hero-arrow-left" class="size-4" /> Back to companies
          </.button>
        </:actions>
      </.page_header>

      <.form for={@form} id="company-form" phx-change="validate" phx-submit="save" class="space-y-6">
        <.form_section
          title="Company Details"
          description="Basic identity, commercial classification, and primary contact info."
        >
          <div class="grid grid-cols-1 gap-6 sm:grid-cols-6">
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
        </.form_section>

        <.form_section
          title="Address"
          description="Capture the company location so the record can support local targeting and field work."
        >
          <div class="grid grid-cols-1 gap-6 sm:grid-cols-6">
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
        </.form_section>

        <.form_section
          title="Additional Context"
          description="Operational metadata that helps with sourcing, prioritization, and segmentation."
        >
          <div class="grid grid-cols-1 gap-6 sm:grid-cols-6">
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
        </.form_section>

        <.section body_class="px-6 py-5 sm:px-7">
          <.form_actions
            cancel_path={~p"/crm/companies"}
            submit_label={if @company, do: "Update Company", else: "Create Company"}
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
