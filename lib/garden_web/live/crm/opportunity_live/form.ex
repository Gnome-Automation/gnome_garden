defmodule GnomeGardenWeb.CRM.OpportunityLive.Form do
  use GnomeGardenWeb, :live_view

  alias GnomeGarden.CRM.Forms, as: CRMForms

  @impl true
  def mount(params, _session, socket) do
    opportunity =
      if id = params["id"] do
        CRMForms.get_opportunity!(id, actor: socket.assigns.current_user)
      else
        nil
      end

    companies = CRMForms.list_companies!(actor: socket.assigns.current_user)

    {:ok,
     socket
     |> assign(:opportunity, opportunity)
     |> assign(:companies, companies)
     |> assign(
       :page_title,
       if(opportunity, do: "Edit #{opportunity.name}", else: "New Opportunity")
     )
     |> assign_form()}
  end

  defp assign_form(%{assigns: %{opportunity: opportunity, current_user: actor}} = socket) do
    form =
      if opportunity do
        CRMForms.form_to_update_opportunity(opportunity, actor: actor)
      else
        CRMForms.form_to_create_opportunity(actor: actor)
      end

    assign(socket, form: to_form(form))
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.header>
      {@page_title}
    </.header>

    <.form for={@form} id="opportunity-form" phx-change="validate" phx-submit="save">
      <div class="space-y-12">
        <div class="border-b border-gray-900/10 pb-12 dark:border-white/10">
          <h2 class="text-base/7 font-semibold text-gray-900 dark:text-white">
            Opportunity Details
          </h2>
          <p class="mt-1 text-sm/6 text-gray-600 dark:text-gray-400">
            Name, company, workflow, and source information.
          </p>
          <div class="mt-10 grid grid-cols-1 gap-x-6 gap-y-8 sm:grid-cols-6">
            <div class="sm:col-span-4">
              <.input field={@form[:name]} label="Opportunity Name" required />
            </div>
            <div class="sm:col-span-4">
              <.input
                field={@form[:company_id]}
                type="select"
                label="Company"
                required
                prompt="Select company..."
                options={Enum.map(@companies, &{&1.name, &1.id})}
              />
            </div>
            <div class="sm:col-span-3">
              <.input
                field={@form[:workflow]}
                type="select"
                label="Workflow"
                prompt="Select workflow..."
                options={[
                  {"Bid Response (RFP/RFI)", :bid_response},
                  {"Outreach (cold call)", :outreach},
                  {"Inbound (referral)", :inbound}
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
                  {"Outbound", :outbound},
                  {"Other", :other}
                ]}
              />
            </div>
            <div :if={@opportunity} class="col-span-full text-sm text-zinc-500">
              Current stage: <span class="font-medium">{format_stage(@opportunity.stage)}</span>
              <span class="text-zinc-400">
                (use stage buttons on the opportunity page to advance)
              </span>
            </div>
          </div>
        </div>

        <div class="border-b border-gray-900/10 pb-12 dark:border-white/10">
          <h2 class="text-base/7 font-semibold text-gray-900 dark:text-white">
            Financials & Timeline
          </h2>
          <p class="mt-1 text-sm/6 text-gray-600 dark:text-gray-400">
            Deal value, probability, and key dates.
          </p>
          <div class="mt-10 grid grid-cols-1 gap-x-6 gap-y-8 sm:grid-cols-6">
            <div class="sm:col-span-3">
              <.input field={@form[:amount]} label="Deal Amount ($)" type="number" step="0.01" />
            </div>
            <div class="sm:col-span-3">
              <.input
                field={@form[:probability]}
                label="Probability (%)"
                type="number"
                min="0"
                max="100"
              />
            </div>
            <div class="sm:col-span-3">
              <.input
                field={@form[:expected_close_date]}
                label="Expected Close Date"
                type="date"
              />
            </div>
            <div :if={@opportunity} class="sm:col-span-3">
              <.input
                field={@form[:actual_close_date]}
                label="Actual Close Date"
                type="date"
              />
            </div>
            <div class="col-span-full">
              <.input field={@form[:description]} type="textarea" label="Description" />
            </div>
            <div
              :if={@opportunity && to_string(@opportunity.stage) == "closed_lost"}
              class="col-span-full"
            >
              <.input field={@form[:loss_reason]} type="textarea" label="Loss Reason" />
            </div>
          </div>
        </div>
      </div>

      <div class="mt-6 flex items-center justify-end gap-x-6">
        <.button type="button" navigate={~p"/crm/opportunities"}>Cancel</.button>
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
      {:ok, opportunity} ->
        {:noreply,
         socket
         |> put_flash(
           :info,
           "Opportunity #{if socket.assigns.opportunity, do: "updated", else: "created"}"
         )
         |> push_navigate(to: ~p"/crm/opportunities/#{opportunity}")}

      {:error, form} ->
        {:noreply, assign(socket, form: to_form(form))}
    end
  end

  defp format_stage(stage) do
    stage |> to_string() |> String.replace("_", " ") |> String.capitalize()
  end
end
