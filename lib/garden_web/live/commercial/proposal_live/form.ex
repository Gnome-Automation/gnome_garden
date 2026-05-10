defmodule GnomeGardenWeb.Commercial.ProposalLive.Form do
  use GnomeGardenWeb, :live_view

  import GnomeGardenWeb.Commercial.Helpers

  alias GnomeGarden.Commercial
  alias GnomeGarden.Operations

  @impl true
  def mount(params, _session, socket) do
    proposal = if id = params["id"], do: load_proposal!(id, socket.assigns.current_user)

    pursuit =
      if is_nil(proposal) and params["pursuit_id"] do
        load_pursuit!(params["pursuit_id"], socket.assigns.current_user)
      end

    {:ok,
     socket
     |> assign(:proposal, proposal)
     |> assign(:pursuit, pursuit)
     |> assign(:organizations, load_organizations(socket.assigns.current_user))
     |> assign(:pursuits, load_pursuits(socket.assigns.current_user))
     |> assign(:page_title, page_title(proposal, pursuit))
     |> assign_form()}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.page max_width="max-w-5xl" class="pb-8">
      <.page_header eyebrow="Commercial">
        {@page_title}
        <:subtitle>
          Price the commercial scope explicitly so proposals stay anchored to the right pursuit and account.
        </:subtitle>
        <:actions>
          <.button navigate={~p"/commercial/proposals"}>
            Back to proposals
          </.button>
        </:actions>
      </.page_header>

      <.section
        :if={@pursuit}
        title="Source Pursuit"
        description="This proposal is being created from an existing pursuit. Confirm the scope and pricing before issuing it."
      >
        <div class="flex items-center justify-between rounded-2xl border border-zinc-200 bg-zinc-50/70 px-4 py-4 dark:border-white/10 dark:bg-white/[0.03]">
          <div class="space-y-1">
            <p class="font-medium text-base-content">{@pursuit.name}</p>
            <p class="text-sm text-base-content/50">
              {(@pursuit.organization && @pursuit.organization.name) || "No organization linked"}
            </p>
          </div>
          <.status_badge status={@pursuit.stage_variant}>
            {format_atom(@pursuit.stage)}
          </.status_badge>
        </div>
      </.section>

      <.form for={@form} id="proposal-form" phx-change="validate" phx-submit="save" class="space-y-6">
        <.form_section
          title="Proposal Details"
          description="Set the customer-facing identity and commercial context for this offer."
        >
          <div class="grid grid-cols-1 gap-6 sm:grid-cols-6">
            <div class="sm:col-span-3">
              <.input field={@form[:proposal_number]} label="Proposal Number" required />
            </div>
            <div class="sm:col-span-3">
              <.input field={@form[:name]} label="Name" required />
            </div>
            <div class="sm:col-span-3">
              <.input
                field={@form[:pursuit_id]}
                type="select"
                label="Pursuit"
                prompt="Select pursuit..."
                options={Enum.map(@pursuits, &{&1.name, &1.id})}
              />
            </div>
            <div class="sm:col-span-3">
              <.input
                field={@form[:organization_id]}
                type="select"
                label="Organization"
                prompt="Select organization..."
                options={Enum.map(@organizations, &{&1.name, &1.id})}
              />
            </div>
            <div class="sm:col-span-3">
              <.input
                field={@form[:pricing_model]}
                type="select"
                label="Pricing Model"
                options={pricing_model_options()}
              />
            </div>
            <div class="sm:col-span-3">
              <.input
                field={@form[:delivery_model]}
                type="select"
                label="Delivery Model"
                options={delivery_model_options()}
              />
            </div>
            <div class="sm:col-span-3">
              <.input field={@form[:currency_code]} label="Currency Code" />
            </div>
            <div class="sm:col-span-3">
              <.input field={@form[:valid_until_on]} type="date" label="Valid Until" />
            </div>
            <div class="col-span-full">
              <.input field={@form[:description]} type="textarea" label="Description" />
            </div>
            <div class="col-span-full">
              <.input field={@form[:notes]} type="textarea" label="Notes" />
            </div>
          </div>
        </.form_section>

        <.section body_class="px-6 py-5 sm:px-7">
          <.form_actions
            cancel_path={~p"/commercial/proposals"}
            submit_label={if @proposal, do: "Update Proposal", else: "Create Proposal"}
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
      {:ok, proposal} ->
        {:noreply,
         socket
         |> put_flash(
           :info,
           "Proposal #{if socket.assigns.proposal, do: "updated", else: "created"}"
         )
         |> push_navigate(to: ~p"/commercial/proposals/#{proposal}")}

      {:error, form} ->
        {:noreply, assign(socket, form: to_form(form))}
    end
  end

  defp assign_form(
         %{assigns: %{proposal: proposal, pursuit: pursuit, current_user: actor}} = socket
       ) do
    form =
      cond do
        proposal ->
          AshPhoenix.Form.for_update(proposal, :update, actor: actor, domain: Commercial)

        pursuit ->
          AshPhoenix.Form.for_create(
            Commercial.Proposal,
            :create,
            actor: actor,
            domain: Commercial,
            params: proposal_defaults_from_pursuit(pursuit)
          )

        true ->
          AshPhoenix.Form.for_create(Commercial.Proposal, :create,
            actor: actor,
            domain: Commercial
          )
      end

    assign(socket, :form, to_form(form))
  end

  defp load_proposal!(id, actor) do
    case Commercial.get_proposal(id, actor: actor) do
      {:ok, proposal} -> proposal
      {:error, error} -> raise "failed to load proposal #{id}: #{inspect(error)}"
    end
  end

  defp load_pursuit!(id, actor) do
    case Commercial.get_pursuit(id, actor: actor, load: [:organization, :stage_variant]) do
      {:ok, pursuit} -> pursuit
      {:error, error} -> raise "failed to load pursuit #{id}: #{inspect(error)}"
    end
  end

  defp load_organizations(actor) do
    case Operations.list_organizations(actor: actor) do
      {:ok, organizations} -> Enum.sort_by(organizations, &String.downcase(&1.name || ""))
      {:error, error} -> raise "failed to load organizations: #{inspect(error)}"
    end
  end

  defp load_pursuits(actor) do
    case Commercial.list_pursuits(actor: actor) do
      {:ok, pursuits} -> Enum.sort_by(pursuits, &String.downcase(&1.name || ""))
      {:error, error} -> raise "failed to load pursuits: #{inspect(error)}"
    end
  end

  defp proposal_defaults_from_pursuit(pursuit) do
    %{
      "pursuit_id" => pursuit.id,
      "organization_id" => pursuit.organization_id,
      "name" => pursuit.name,
      "description" => pursuit.description,
      "notes" => pursuit.notes,
      "delivery_model" => pursuit.delivery_model,
      "pricing_model" => pursuit.billing_model
    }
  end

  defp page_title(proposal, _pursuit) when not is_nil(proposal), do: "Edit Proposal"
  defp page_title(nil, pursuit) when not is_nil(pursuit), do: "New Proposal From Pursuit"
  defp page_title(nil, nil), do: "New Proposal"

  defp pricing_model_options do
    [
      {"Fixed Fee", :fixed_fee},
      {"Time & Materials", :time_and_materials},
      {"Retainer", :retainer},
      {"Milestone", :milestone},
      {"Unit", :unit},
      {"Mixed", :mixed}
    ]
  end

  defp delivery_model_options do
    [
      {"Project", :project},
      {"Service", :service},
      {"Maintenance", :maintenance},
      {"Retainer", :retainer},
      {"Mixed", :mixed}
    ]
  end
end
