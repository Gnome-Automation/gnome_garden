defmodule GnomeGardenWeb.Company.GrowthLive.Form do
  use GnomeGardenWeb, :live_view

  alias GnomeGarden.Company
  alias GnomeGarden.Operations

  @impl true
  def mount(params, _session, socket) do
    initiative = if id = params["id"], do: load_initiative!(id, socket.assigns.current_user)

    {:ok,
     socket
     |> assign(:initiative, initiative)
     |> assign(:page_title, if(initiative, do: "Edit Initiative", else: "New Initiative"))
     |> assign(:team_members, load_team_members(socket.assigns.current_user))
     |> assign_form()}
  end

  @impl true
  def handle_event("validate", %{"form" => params}, socket) do
    form = AshPhoenix.Form.validate(socket.assigns.form, params)
    {:noreply, assign(socket, form: to_form(form))}
  end

  @impl true
  def handle_event("save", %{"form" => params}, socket) do
    params =
      if socket.assigns.initiative,
        do: params,
        else: Map.put(params, "company_profile_id", primary_profile_id(socket))

    case AshPhoenix.Form.submit(socket.assigns.form, params: params) do
      {:ok, initiative} ->
        {:noreply,
         socket
         |> put_flash(:info, "Initiative saved")
         |> push_navigate(to: ~p"/company/growth/#{initiative}")}

      {:error, form} ->
        {:noreply, assign(socket, form: to_form(form))}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.page max_width="max-w-3xl" class="pb-8">
      <.page_header eyebrow="Company Growth">
        {@page_title}
        <:actions>
          <.button navigate={~p"/company/growth"}>
            Back
          </.button>
        </:actions>
      </.page_header>

      <.form for={@form} id="initiative-form" phx-change="validate" phx-submit="save" class="space-y-6">
        <.form_section title="Initiative">
          <div class="grid grid-cols-1 gap-6 sm:grid-cols-6">
            <div class="col-span-full">
              <.input field={@form[:title]} label="Title" required />
            </div>
            <div class="col-span-full">
              <.input field={@form[:description]} type="textarea" label="Description" />
            </div>
            <div class="sm:col-span-3">
              <.input
                field={@form[:category]}
                type="select"
                label="Category"
                options={category_options()}
              />
            </div>
            <div class="sm:col-span-3">
              <.input
                field={@form[:owner_team_member_id]}
                type="select"
                label="Owner"
                prompt="Unassigned"
                options={Enum.map(@team_members, &{&1.display_name, &1.id})}
              />
            </div>
            <div class="sm:col-span-3">
              <.input field={@form[:expected_benefit]} label="Expected benefit" />
            </div>
            <div class="sm:col-span-2">
              <.input field={@form[:effort_estimate]} label="Effort estimate" />
            </div>
            <div class="sm:col-span-1">
              <.input field={@form[:target_date]} type="date" label="Target" />
            </div>
          </div>
        </.form_section>

        <.section body_class="px-6 py-5 sm:px-7">
          <.form_actions
            cancel_path={~p"/company/growth"}
            submit_label={if @initiative, do: "Save Changes", else: "Create Initiative"}
          />
        </.section>
      </.form>
    </.page>
    """
  end

  defp assign_form(%{assigns: %{initiative: initiative, current_user: actor}} = socket) do
    form =
      if initiative do
        AshPhoenix.Form.for_update(initiative, :update, actor: actor, domain: Company)
      else
        AshPhoenix.Form.for_create(Company.GrowthInitiative, :create,
          actor: actor,
          domain: Company
        )
      end

    assign(socket, :form, to_form(form))
  end

  defp primary_profile_id(socket) do
    case Company.get_primary_company_profile(actor: socket.assigns.current_user) do
      {:ok, profile} -> profile.id
      {:error, error} -> raise "no primary company profile: #{inspect(error)}"
    end
  end

  defp category_options do
    [
      {"Certification", :certification},
      {"Registration", :registration},
      {"Licensing", :licensing},
      {"Bonding", :bonding},
      {"Insurance", :insurance},
      {"Partner program", :partner_program},
      {"Market access", :market_access},
      {"Marketing asset", :marketing_asset},
      {"Operational readiness", :operational_readiness}
    ]
  end

  defp load_team_members(actor) do
    case Operations.list_active_team_members(actor: actor) do
      {:ok, members} -> members
      {:error, _error} -> []
    end
  end

  defp load_initiative!(id, actor) do
    case Company.get_growth_initiative(id, actor: actor) do
      {:ok, initiative} -> initiative
      {:error, error} -> raise "failed to load growth initiative #{id}: #{inspect(error)}"
    end
  end
end
