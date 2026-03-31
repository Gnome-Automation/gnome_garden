defmodule GnomeGardenWeb.CRM.OpportunityLive.Form do
  use GnomeGardenWeb, :live_view

  alias GnomeGarden.Sales

  @impl true
  def mount(params, _session, socket) do
    opportunity =
      if id = params["id"] do
        Sales.get_opportunity!(id, actor: socket.assigns.current_user)
      else
        nil
      end

    companies = Sales.list_companies!(actor: socket.assigns.current_user)

    {:ok,
     socket
     |> assign(:opportunity, opportunity)
     |> assign(:companies, companies)
     |> assign(:page_title, if(opportunity, do: "Edit #{opportunity.name}", else: "New Opportunity"))
     |> assign_form()}
  end

  defp assign_form(%{assigns: %{opportunity: opportunity, current_user: actor}} = socket) do
    form =
      if opportunity do
        Sales.form_to_update_opportunity(opportunity, actor: actor)
      else
        Sales.form_to_create_opportunity(actor: actor)
      end

    assign(socket, form: to_form(form))
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.header>
      {@page_title}
    </.header>

    <.form for={@form} id="opportunity-form" phx-change="validate" phx-submit="save" class="space-y-6 max-w-2xl">
      <.input field={@form[:name]} label="Opportunity Name" required />

      <.input
        field={@form[:company_id]}
        type="select"
        label="Company"
        required
        prompt="Select company..."
        options={Enum.map(@companies, &{&1.name, &1.id})}
      />

      <div class="grid grid-cols-1 gap-6 sm:grid-cols-2">
        <.input
          field={@form[:stage]}
          type="select"
          label="Stage"
          options={[
            {"Discovery", :discovery},
            {"Qualification", :qualification},
            {"Demo", :demo},
            {"Proposal", :proposal},
            {"Negotiation", :negotiation},
            {"Closed Won", :closed_won},
            {"Closed Lost", :closed_lost}
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
            {"Outbound", :outbound},
            {"Other", :other}
          ]}
        />
      </div>

      <div class="grid grid-cols-1 gap-6 sm:grid-cols-2">
        <.input field={@form[:amount]} label="Deal Amount ($)" type="number" step="0.01" />
        <.input field={@form[:probability]} label="Probability (%)" type="number" min="0" max="100" />
      </div>

      <div class="grid grid-cols-1 gap-6 sm:grid-cols-2">
        <.input field={@form[:expected_close_date]} label="Expected Close Date" type="date" />
        <.input
          :if={@opportunity}
          field={@form[:actual_close_date]}
          label="Actual Close Date"
          type="date"
        />
      </div>

      <.input field={@form[:description]} type="textarea" label="Description" />

      <.input
        :if={@opportunity && @form[:stage].value in [:closed_lost]}
        field={@form[:loss_reason]}
        type="textarea"
        label="Loss Reason"
      />

      <div class="flex gap-4 pt-4">
        <.button type="submit" variant="primary" phx-disable-with="Saving...">
          Save Opportunity
        </.button>
        <.button type="button" navigate={~p"/crm/opportunities"}>Cancel</.button>
      </div>
    </.form>
    """
  end

  @impl true
  def handle_event("validate", %{"form" => params}, socket) do
    form = AshPhoenix.Form.validate(socket.assigns.form.source, params)
    {:noreply, assign(socket, form: to_form(form))}
  end

  def handle_event("save", %{"form" => params}, socket) do
    case AshPhoenix.Form.submit(socket.assigns.form.source, params: params) do
      {:ok, opportunity} ->
        {:noreply,
         socket
         |> put_flash(:info, "Opportunity #{if socket.assigns.opportunity, do: "updated", else: "created"}")
         |> push_navigate(to: ~p"/crm/opportunities/#{opportunity}")}

      {:error, form} ->
        {:noreply, assign(socket, form: to_form(form))}
    end
  end
end
