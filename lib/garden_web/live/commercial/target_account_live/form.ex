defmodule GnomeGardenWeb.Commercial.TargetAccountLive.Form do
  use GnomeGardenWeb, :live_view

  alias GnomeGarden.Commercial
  alias GnomeGarden.Operations

  @impl true
  def mount(params, _session, socket) do
    target_account =
      if id = params["id"], do: load_target_account!(id, socket.assigns.current_user)

    organizations = load_organizations(socket.assigns.current_user)
    discovery_programs = load_discovery_programs(socket.assigns.current_user)

    {:ok,
     socket
     |> assign(:target_account, target_account)
     |> assign(:organizations, organizations)
     |> assign(:discovery_programs, discovery_programs)
     |> assign(:page_title, if(target_account, do: "Edit Target", else: "New Target"))
     |> assign_form()}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.page max_width="max-w-5xl" class="pb-8">
      <.page_header eyebrow="Commercial">
        {@page_title}
        <:subtitle>
          Capture discovered target accounts before they become formal commercial signals.
        </:subtitle>
        <:actions>
          <.button navigate={~p"/commercial/targets"}>
            <.icon name="hero-arrow-left" class="size-4" /> Back to targets
          </.button>
        </:actions>
      </.page_header>

      <.form
        for={@form}
        id="target-account-form"
        phx-change="validate"
        phx-submit="save"
        class="space-y-6"
      >
        <.form_section
          title="Target Context"
          description="Keep the broad discovery queue structured enough that human review stays fast."
        >
          <div class="grid grid-cols-1 gap-6 sm:grid-cols-6">
            <div class="sm:col-span-4">
              <.input field={@form[:name]} label="Name" required />
            </div>
            <div class="sm:col-span-2">
              <.input
                field={@form[:discovery_program_id]}
                type="select"
                label="Discovery Program"
                prompt="Select program..."
                options={Enum.map(@discovery_programs, &{&1.name, &1.id})}
              />
            </div>
            <div class="sm:col-span-2">
              <.input
                field={@form[:organization_id]}
                type="select"
                label="Linked Organization"
                prompt="Select organization..."
                options={Enum.map(@organizations, &{&1.name, &1.id})}
              />
            </div>
            <div class="sm:col-span-3">
              <.input field={@form[:website]} label="Website" />
            </div>
            <div class="sm:col-span-3">
              <.input field={@form[:location]} label="Location" />
            </div>
            <div class="sm:col-span-2">
              <.input field={@form[:region]} label="Region" />
            </div>
            <div class="sm:col-span-2">
              <.input field={@form[:industry]} label="Industry" />
            </div>
            <div class="sm:col-span-2">
              <.input
                field={@form[:size_bucket]}
                type="select"
                label="Size"
                prompt="Select size..."
                options={[
                  {"Small", :small},
                  {"Medium", :medium},
                  {"Large", :large},
                  {"Enterprise", :enterprise}
                ]}
              />
            </div>
            <div class="sm:col-span-3">
              <.input field={@form[:fit_score]} type="number" label="Fit Score" />
            </div>
            <div class="sm:col-span-3">
              <.input field={@form[:intent_score]} type="number" label="Intent Score" />
            </div>
            <div class="col-span-full">
              <.input field={@form[:notes]} type="textarea" label="Notes" />
            </div>
          </div>
        </.form_section>

        <.section body_class="px-6 py-5 sm:px-7">
          <.form_actions
            cancel_path={~p"/commercial/targets"}
            submit_label={if @target_account, do: "Update Target", else: "Create Target"}
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
      {:ok, target_account} ->
        {:noreply,
         socket
         |> put_flash(
           :info,
           "Target #{if socket.assigns.target_account, do: "updated", else: "created"}"
         )
         |> push_navigate(to: ~p"/commercial/targets/#{target_account}")}

      {:error, form} ->
        {:noreply, assign(socket, form: to_form(form))}
    end
  end

  defp assign_form(%{assigns: %{target_account: target_account, current_user: actor}} = socket) do
    form =
      if target_account do
        AshPhoenix.Form.for_update(target_account, :update, actor: actor, domain: Commercial)
      else
        AshPhoenix.Form.for_create(
          Commercial.TargetAccount,
          :create,
          actor: actor,
          domain: Commercial
        )
      end

    assign(socket, form: to_form(form))
  end

  defp load_target_account!(id, actor) do
    case Commercial.get_target_account(id, actor: actor) do
      {:ok, target_account} -> target_account
      {:error, error} -> raise "failed to load target account #{id}: #{inspect(error)}"
    end
  end

  defp load_organizations(actor) do
    case Operations.list_organizations(actor: actor) do
      {:ok, organizations} -> Enum.sort_by(organizations, &String.downcase(&1.name || ""))
      {:error, error} -> raise "failed to load organizations: #{inspect(error)}"
    end
  end

  defp load_discovery_programs(actor) do
    case Commercial.list_discovery_programs(actor: actor) do
      {:ok, programs} -> Enum.sort_by(programs, &String.downcase(&1.name || ""))
      {:error, error} -> raise "failed to load discovery programs: #{inspect(error)}"
    end
  end
end
