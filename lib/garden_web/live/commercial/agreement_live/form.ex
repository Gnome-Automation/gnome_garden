defmodule GnomeGardenWeb.Commercial.AgreementLive.Form do
  use GnomeGardenWeb, :live_view

  import GnomeGardenWeb.Commercial.Helpers

  alias GnomeGarden.Commercial
  alias GnomeGarden.Operations

  @impl true
  def mount(params, _session, socket) do
    agreement = if id = params["id"], do: load_agreement!(id, socket.assigns.current_user)

    proposal =
      if is_nil(agreement) and params["proposal_id"] do
        load_proposal!(params["proposal_id"], socket.assigns.current_user)
      end

    {:ok,
     socket
     |> assign(:agreement, agreement)
     |> assign(:proposal, proposal)
     |> assign(:organizations, load_organizations(socket.assigns.current_user))
     |> assign(:proposals, load_proposals(socket.assigns.current_user))
     |> assign(:page_title, page_title(agreement, proposal))
     |> assign_form()}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.page max_width="max-w-5xl" class="pb-8">
      <.page_header eyebrow="Commercial">
        {@page_title}
        <:subtitle>
          Capture the durable contract record that downstream projects, service work, and billing will hang off.
        </:subtitle>
        <:actions>
          <.button navigate={~p"/commercial/agreements"}>
            <.icon name="hero-arrow-left" class="size-4" /> Back to agreements
          </.button>
        </:actions>
      </.page_header>

      <.section
        :if={@proposal}
        title="Source Proposal"
        description="This agreement is being created from an accepted proposal. Confirm the commercial commitment before activating it."
      >
        <div class="flex items-center justify-between rounded-2xl border border-zinc-200 bg-zinc-50/70 px-4 py-4 dark:border-white/10 dark:bg-white/[0.03]">
          <div class="space-y-1">
            <p class="font-medium text-zinc-900 dark:text-white">{@proposal.name}</p>
            <p class="text-sm text-zinc-500 dark:text-zinc-400">
              {@proposal.proposal_number}
              <span class="mx-1 text-zinc-400">/</span>
              {(@proposal.organization && @proposal.organization.name) || "No organization linked"}
            </p>
          </div>
          <.status_badge status={@proposal.status_variant}>
            {format_atom(@proposal.status)}
          </.status_badge>
        </div>
      </.section>

      <.form for={@form} id="agreement-form" phx-change="validate" phx-submit="save" class="space-y-6">
        <.form_section
          title="Agreement Details"
          description="Define the contract identity, billing model, term, and account scope."
        >
          <div class="grid grid-cols-1 gap-6 sm:grid-cols-6">
            <div class="sm:col-span-3">
              <.input field={@form[:reference_number]} label="Reference Number" />
            </div>
            <div class="sm:col-span-3">
              <.input field={@form[:name]} label="Name" required />
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
                :if={is_nil(@proposal)}
                field={@form[:proposal_id]}
                type="select"
                label="Proposal"
                prompt="Select proposal..."
                options={Enum.map(@proposals, &{&1.name, &1.id})}
              />
            </div>
            <div :if={!is_nil(@proposal)} class="sm:col-span-3">
              <div class="space-y-2">
                <label class="block text-sm/6 font-medium text-gray-900 dark:text-white">
                  Proposal
                </label>
                <div class="rounded-2xl border border-zinc-200 bg-zinc-50/70 px-4 py-3 text-sm text-zinc-600 dark:border-white/10 dark:bg-white/[0.03] dark:text-zinc-300">
                  {@proposal.name}
                </div>
              </div>
            </div>
            <div class="sm:col-span-3">
              <.input
                field={@form[:agreement_type]}
                type="select"
                label="Agreement Type"
                options={agreement_type_options()}
              />
            </div>
            <div class="sm:col-span-3">
              <.input
                field={@form[:billing_model]}
                type="select"
                label="Billing Model"
                options={billing_model_options()}
              />
            </div>
            <div class="sm:col-span-2">
              <.input field={@form[:currency_code]} label="Currency Code" />
            </div>
            <div class="sm:col-span-2">
              <.input field={@form[:contract_value]} label="Contract Value" type="number" step="0.01" />
            </div>
            <div class="sm:col-span-2">
              <.input field={@form[:renewal_notice_days]} label="Renewal Notice Days" type="number" />
            </div>
            <div class="sm:col-span-3">
              <.input field={@form[:start_on]} type="date" label="Start On" />
            </div>
            <div class="sm:col-span-3">
              <.input field={@form[:end_on]} type="date" label="End On" />
            </div>
            <div class="sm:col-span-3">
              <.input field={@form[:auto_renew]} type="checkbox" label="Auto Renew" />
            </div>
            <div class="col-span-full">
              <.input field={@form[:notes]} type="textarea" label="Notes" />
            </div>
          </div>
        </.form_section>

        <.section body_class="px-6 py-5 sm:px-7">
          <.form_actions
            cancel_path={~p"/commercial/agreements"}
            submit_label={if @agreement, do: "Update Agreement", else: "Create Agreement"}
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
      {:ok, agreement} ->
        {:noreply,
         socket
         |> put_flash(
           :info,
           "Agreement #{if socket.assigns.agreement, do: "updated", else: "created"}"
         )
         |> push_navigate(to: ~p"/commercial/agreements/#{agreement}")}

      {:error, form} ->
        {:noreply, assign(socket, form: to_form(form))}
    end
  end

  defp assign_form(
         %{assigns: %{agreement: agreement, proposal: proposal, current_user: actor}} = socket
       ) do
    form =
      cond do
        agreement ->
          AshPhoenix.Form.for_update(agreement, :update, actor: actor, domain: Commercial)

        proposal ->
          AshPhoenix.Form.for_create(
            Commercial.Agreement,
            :create_from_proposal,
            actor: actor,
            domain: Commercial,
            params: agreement_defaults_from_proposal(proposal),
            prepare_source: fn changeset ->
              Ash.Changeset.set_argument(changeset, :proposal_id, proposal.id)
            end
          )

        true ->
          AshPhoenix.Form.for_create(Commercial.Agreement, :create,
            actor: actor,
            domain: Commercial
          )
      end

    assign(socket, :form, to_form(form))
  end

  defp load_agreement!(id, actor) do
    case Commercial.get_agreement(id, actor: actor) do
      {:ok, agreement} -> agreement
      {:error, error} -> raise "failed to load agreement #{id}: #{inspect(error)}"
    end
  end

  defp load_proposal!(id, actor) do
    case Commercial.get_proposal(id, actor: actor, load: [:organization, :status_variant]) do
      {:ok, proposal} -> proposal
      {:error, error} -> raise "failed to load proposal #{id}: #{inspect(error)}"
    end
  end

  defp load_organizations(actor) do
    case Operations.list_organizations(actor: actor) do
      {:ok, organizations} -> Enum.sort_by(organizations, &String.downcase(&1.name || ""))
      {:error, error} -> raise "failed to load organizations: #{inspect(error)}"
    end
  end

  defp load_proposals(actor) do
    case Commercial.list_proposals(actor: actor) do
      {:ok, proposals} -> Enum.sort_by(proposals, &String.downcase(&1.name || ""))
      {:error, error} -> raise "failed to load proposals: #{inspect(error)}"
    end
  end

  defp agreement_defaults_from_proposal(proposal) do
    %{
      "organization_id" => proposal.organization_id,
      "reference_number" => proposal.proposal_number,
      "name" => proposal.name,
      "billing_model" => proposal.pricing_model,
      "currency_code" => proposal.currency_code,
      "notes" => proposal.notes
    }
  end

  defp page_title(agreement, _proposal) when not is_nil(agreement), do: "Edit Agreement"
  defp page_title(nil, proposal) when not is_nil(proposal), do: "New Agreement From Proposal"
  defp page_title(nil, nil), do: "New Agreement"

  defp agreement_type_options do
    [
      {"MSA", :msa},
      {"SOW", :sow},
      {"Project", :project},
      {"Service", :service},
      {"Maintenance", :maintenance},
      {"Retainer", :retainer},
      {"Support", :support},
      {"Warranty", :warranty},
      {"Other", :other}
    ]
  end

  defp billing_model_options do
    [
      {"Fixed Fee", :fixed_fee},
      {"Time & Materials", :time_and_materials},
      {"Retainer", :retainer},
      {"Milestone", :milestone},
      {"Unit", :unit},
      {"Mixed", :mixed}
    ]
  end
end
