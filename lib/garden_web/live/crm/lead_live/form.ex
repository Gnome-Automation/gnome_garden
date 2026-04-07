defmodule GnomeGardenWeb.CRM.LeadLive.Form do
  use GnomeGardenWeb, :live_view

  alias GnomeGarden.Sales

  @impl true
  def mount(params, _session, socket) do
    lead =
      if id = params["id"] do
        Sales.get_lead!(id, actor: socket.assigns.current_user)
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
        Sales.form_to_update_lead(lead, actor: actor)
      else
        Sales.form_to_create_lead(actor: actor)
      end

    assign(socket, form: to_form(form))
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.header>
      {@page_title}
    </.header>

    <.form for={@form} id="lead-form" phx-change="validate" phx-submit="save">
      <div class="space-y-12">
        <div class="border-b border-gray-900/10 pb-12 dark:border-white/10">
          <h2 class="text-base/7 font-semibold text-gray-900 dark:text-white">Lead Information</h2>
          <p class="mt-1 text-sm/6 text-gray-600 dark:text-gray-400">
            Contact details and company information.
          </p>
          <div class="mt-10 grid grid-cols-1 gap-x-6 gap-y-8 sm:grid-cols-6">
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
        </div>

        <div class="border-b border-gray-900/10 pb-12 dark:border-white/10">
          <h2 class="text-base/7 font-semibold text-gray-900 dark:text-white">
            Source & Details
          </h2>
          <p class="mt-1 text-sm/6 text-gray-600 dark:text-gray-400">
            How we found this lead and additional context.
          </p>
          <div class="mt-10 grid grid-cols-1 gap-x-6 gap-y-8 sm:grid-cols-6">
            <div class="sm:col-span-3">
              <.input
                :if={@lead}
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
        </div>
      </div>

      <div class="mt-6 flex items-center justify-end gap-x-6">
        <.button type="button" navigate={~p"/crm/leads"}>Cancel</.button>
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
