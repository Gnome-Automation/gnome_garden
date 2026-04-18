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
    <.page max_width="max-w-5xl" class="pb-8">
      <.page_header eyebrow="CRM">
        {@page_title}
        <:subtitle>
          {if @opportunity,
            do: "Adjust deal shape, timeline, and commercial expectations before advancing stages.",
            else: "Create a pursuit record that can mature into proposals, agreements, and projects."}
        </:subtitle>
        <:actions>
          <.button navigate={~p"/crm/opportunities"}>
            <.icon name="hero-arrow-left" class="size-4" /> Back to opportunities
          </.button>
        </:actions>
      </.page_header>

      <.form
        for={@form}
        id="opportunity-form"
        phx-change="validate"
        phx-submit="save"
        class="space-y-6"
      >
        <.form_section
          title="Opportunity Details"
          description="Define the company, workflow, and commercial source driving this pursuit."
        >
          <div class="grid grid-cols-1 gap-6 sm:grid-cols-6">
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
            <div
              :if={@opportunity}
              class="col-span-full rounded-2xl bg-zinc-50 px-4 py-3 text-sm text-zinc-600 dark:bg-white/[0.04] dark:text-zinc-300"
            >
              Current stage: <span class="font-medium">{format_stage(@opportunity.stage)}</span>
              <span class="text-zinc-400 dark:text-zinc-500">
                (advance it from the opportunity detail page)
              </span>
            </div>
          </div>
        </.form_section>

        <.form_section
          title="Financials & Timeline"
          description="Capture value, close probability, and the dates that matter to forecasting."
        >
          <div class="grid grid-cols-1 gap-6 sm:grid-cols-6">
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
        </.form_section>

        <.section body_class="px-6 py-5 sm:px-7">
          <.form_actions
            cancel_path={~p"/crm/opportunities"}
            submit_label={if @opportunity, do: "Update Opportunity", else: "Create Opportunity"}
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
