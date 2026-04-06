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

    <.form
      for={@form}
      id="lead-form"
      phx-change="validate"
      phx-submit="save"
      class="space-y-6 max-w-2xl"
    >
      <div class="grid grid-cols-1 gap-6 sm:grid-cols-2">
        <.input field={@form[:first_name]} label="First Name" required />
        <.input field={@form[:last_name]} label="Last Name" required />
      </div>

      <div class="grid grid-cols-1 gap-6 sm:grid-cols-2">
        <.input field={@form[:email]} label="Email" type="email" />
        <.input field={@form[:phone]} label="Phone" type="tel" />
      </div>

      <div class="grid grid-cols-1 gap-6 sm:grid-cols-2">
        <.input field={@form[:title]} label="Job Title" />
        <.input field={@form[:company_name]} label="Company Name" />
      </div>

      <div class="grid grid-cols-1 gap-6 sm:grid-cols-2">
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

      <.input field={@form[:source_details]} type="textarea" label="Source Details" />

      <div class="flex gap-4 pt-4">
        <.button type="submit" variant="primary" phx-disable-with="Saving...">
          Save Lead
        </.button>
        <.button type="button" navigate={~p"/crm/leads"}>Cancel</.button>
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
