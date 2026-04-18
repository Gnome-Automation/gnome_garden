defmodule GnomeGardenWeb.CRM.LeadLive.Form do
  use GnomeGardenWeb, :live_view

  alias GnomeGarden.CRM.Forms, as: CRMForms

  @impl true
  def mount(params, _session, socket) do
    lead =
      if id = params["id"] do
        CRMForms.get_lead!(id, actor: socket.assigns.current_user)
      else
        nil
      end

    {:ok,
     socket
     |> assign(:lead, lead)
     |> assign(
       :page_title,
       if(lead, do: "Edit #{lead.first_name} #{lead.last_name}", else: "New Lead")
     )
     |> assign_form()}
  end

  defp assign_form(%{assigns: %{lead: lead, current_user: actor}} = socket) do
    form =
      if lead do
        CRMForms.form_to_update_lead(lead, actor: actor)
      else
        CRMForms.form_to_create_lead(actor: actor)
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
          {if @lead,
            do: "Refine qualification details and keep the source signal current.",
            else: "Capture a raw market signal and the person or company attached to it."}
        </:subtitle>
        <:actions>
          <.button navigate={~p"/crm/leads"}>
            <.icon name="hero-arrow-left" class="size-4" /> Back to leads
          </.button>
        </:actions>
      </.page_header>

      <.form for={@form} id="lead-form" phx-change="validate" phx-submit="save" class="space-y-6">
        <.form_section
          title="Lead Information"
          description="The person, role, and company details attached to this incoming opportunity."
        >
          <div class="grid grid-cols-1 gap-6 sm:grid-cols-6">
            <div class="sm:col-span-3">
              <.input field={@form[:first_name]} label="First Name" required />
            </div>
            <div class="sm:col-span-3">
              <.input field={@form[:last_name]} label="Last Name" required />
            </div>
            <div class="sm:col-span-3">
              <.input field={@form[:email]} label="Email" type="email" />
            </div>
            <div class="sm:col-span-3">
              <.input field={@form[:phone]} label="Phone" type="tel" />
            </div>
            <div class="sm:col-span-3">
              <.input field={@form[:title]} label="Job Title" />
            </div>
            <div class="sm:col-span-3">
              <.input field={@form[:company_name]} label="Company Name" />
            </div>
          </div>
        </.form_section>

        <.form_section
          title="Source & Details"
          description="Track where the lead came from and the context needed for qualification."
        >
          <div class="grid grid-cols-1 gap-6 sm:grid-cols-6">
            <div :if={@lead} class="sm:col-span-3">
              <.input
                field={@form[:status]}
                type="select"
                label="Status"
                options={[
                  {"New", :new},
                  {"Contacted", :contacted},
                  {"Qualified", :qualified},
                  {"Unqualified", :unqualified},
                  {"Converted", :converted}
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
                  {"Website", :website},
                  {"Referral", :referral},
                  {"Trade Show", :trade_show},
                  {"Cold Call", :cold_call},
                  {"Bid", :bid},
                  {"Other", :other}
                ]}
              />
            </div>
            <div class="col-span-full">
              <.input field={@form[:source_url]} label="Source URL" type="url" />
            </div>
            <div class="col-span-full">
              <.input field={@form[:source_details]} type="textarea" label="Source Details" />
            </div>
            <div class="col-span-full">
              <.input field={@form[:description]} type="textarea" label="Description" />
            </div>
          </div>
        </.form_section>

        <.section body_class="px-6 py-5 sm:px-7">
          <.form_actions
            cancel_path={~p"/crm/leads"}
            submit_label={if @lead, do: "Update Lead", else: "Create Lead"}
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
      {:ok, lead} ->
        {:noreply,
         socket
         |> put_flash(:info, "Lead #{if socket.assigns.lead, do: "updated", else: "created"}")
         |> push_navigate(to: ~p"/crm/leads/#{lead}")}

      {:error, form} ->
        {:noreply, assign(socket, form: to_form(form))}
    end
  end
end
