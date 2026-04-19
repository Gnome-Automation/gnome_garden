defmodule GnomeGardenWeb.Commercial.PursuitLive.Form do
  use GnomeGardenWeb, :live_view

  import GnomeGardenWeb.Commercial.Helpers

  alias GnomeGarden.Commercial
  alias GnomeGarden.Operations

  @impl true
  def mount(params, _session, socket) do
    pursuit = if id = params["id"], do: load_pursuit!(id, socket.assigns.current_user)

    signal =
      if is_nil(pursuit) and params["signal_id"],
        do: load_signal!(params["signal_id"], socket.assigns.current_user)

    organizations = load_organizations(socket.assigns.current_user)

    {:ok,
     socket
     |> assign(:pursuit, pursuit)
     |> assign(:signal, signal)
     |> assign(:organizations, organizations)
     |> assign(:page_title, page_title(pursuit, signal))
     |> assign_form()}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.page max_width="max-w-5xl" class="pb-8">
      <.page_header eyebrow="Commercial">
        {@page_title}
        <:subtitle>
          Convert qualified signals into owned pipeline, or create a pursuit directly when the opportunity is already clear.
        </:subtitle>
        <:actions>
          <.button navigate={~p"/commercial/pursuits"}>
            <.icon name="hero-arrow-left" class="size-4" /> Back to pursuits
          </.button>
        </:actions>
      </.page_header>

      <.section
        :if={@signal}
        title="Source Signal"
        description="This pursuit is being created from an accepted signal. The form is prefilled so the reviewer can confirm and refine it."
      >
        <div class="flex items-center justify-between rounded-2xl border border-zinc-200 bg-zinc-50/70 px-4 py-4 dark:border-white/10 dark:bg-white/[0.03]">
          <div class="space-y-1">
            <p class="font-medium text-zinc-900 dark:text-white">{@signal.title}</p>
            <p class="text-sm text-zinc-500 dark:text-zinc-400">
              {format_atom(@signal.signal_type)}
              <span :if={@signal.organization} class="mx-1 text-zinc-400">/</span>
              <span :if={@signal.organization}>{@signal.organization.name}</span>
            </p>
          </div>
          <.status_badge status={@signal.status_variant}>
            {format_atom(@signal.status)}
          </.status_badge>
        </div>
      </.section>

      <.form for={@form} id="pursuit-form" phx-change="validate" phx-submit="save" class="space-y-6">
        <.form_section
          title="Pursuit Details"
          description="Set the commercial owner, account, and pursuit framing before the work reaches proposal stage."
        >
          <div class="grid grid-cols-1 gap-6 sm:grid-cols-6">
            <div class="sm:col-span-4">
              <.input field={@form[:name]} label="Name" required />
            </div>
            <div class="sm:col-span-4">
              <.input
                field={@form[:organization_id]}
                type="select"
                label="Organization"
                prompt="Select organization..."
                required
                options={Enum.map(@organizations, &{&1.name, &1.id})}
              />
            </div>
            <div class="sm:col-span-3">
              <.input
                field={@form[:pursuit_type]}
                type="select"
                label="Pursuit Type"
                options={[
                  {"New Logo", :new_logo},
                  {"Existing Account", :existing_account},
                  {"Bid Response", :bid_response},
                  {"Change Order", :change_order},
                  {"Renewal", :renewal},
                  {"Service Expansion", :service_expansion},
                  {"Other", :other}
                ]}
              />
            </div>
            <div class="sm:col-span-3">
              <.input
                field={@form[:priority]}
                type="select"
                label="Priority"
                options={[
                  {"Low", :low},
                  {"Normal", :normal},
                  {"High", :high},
                  {"Strategic", :strategic}
                ]}
              />
            </div>
            <div class="col-span-full">
              <.input field={@form[:description]} type="textarea" label="Description" />
            </div>
            <div class="col-span-full">
              <.input field={@form[:notes]} type="textarea" label="Notes" />
            </div>
          </div>
        </.form_section>

        <.form_section
          title="Forecast & Delivery"
          description="Capture value, likelihood, and the general delivery/billing shape early."
        >
          <div class="grid grid-cols-1 gap-6 sm:grid-cols-6">
            <div class="sm:col-span-2">
              <.input
                field={@form[:probability]}
                label="Probability (%)"
                type="number"
                min="0"
                max="100"
              />
            </div>
            <div class="sm:col-span-2">
              <.input field={@form[:target_value]} label="Target Value" type="number" step="0.01" />
            </div>
            <div class="sm:col-span-2">
              <.input field={@form[:expected_close_on]} label="Expected Close" type="date" />
            </div>
            <div class="sm:col-span-3">
              <.input
                field={@form[:delivery_model]}
                type="select"
                label="Delivery Model"
                options={[
                  {"Project", :project},
                  {"Service", :service},
                  {"Maintenance", :maintenance},
                  {"Retainer", :retainer},
                  {"Mixed", :mixed}
                ]}
              />
            </div>
            <div class="sm:col-span-3">
              <.input
                field={@form[:billing_model]}
                type="select"
                label="Billing Model"
                options={[
                  {"Fixed Fee", :fixed_fee},
                  {"Time & Materials", :time_and_materials},
                  {"Retainer", :retainer},
                  {"Milestone", :milestone},
                  {"Unit", :unit},
                  {"Mixed", :mixed}
                ]}
              />
            </div>
          </div>
        </.form_section>

        <.section body_class="px-6 py-5 sm:px-7">
          <.form_actions
            cancel_path={~p"/commercial/pursuits"}
            submit_label={submit_label(@pursuit, @signal)}
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
      {:ok, pursuit} ->
        {:noreply,
         socket
         |> put_flash(:info, "Pursuit #{success_label(socket.assigns.pursuit)}")
         |> push_navigate(to: ~p"/commercial/pursuits/#{pursuit}")}

      {:error, form} ->
        {:noreply, assign(socket, form: to_form(form))}
    end
  end

  defp assign_form(%{assigns: %{pursuit: pursuit, signal: signal, current_user: actor}} = socket) do
    form =
      cond do
        pursuit ->
          AshPhoenix.Form.for_update(pursuit, :update, actor: actor, domain: Commercial)

        signal ->
          AshPhoenix.Form.for_create(
            Commercial.Pursuit,
            :create_from_signal,
            actor: actor,
            domain: Commercial,
            params: pursuit_defaults_from_signal(signal),
            prepare_source: fn changeset ->
              Ash.Changeset.set_argument(changeset, :source_signal_id, signal.id)
            end
          )

        true ->
          AshPhoenix.Form.for_create(Commercial.Pursuit, :create,
            actor: actor,
            domain: Commercial
          )
      end

    assign(socket, form: to_form(form))
  end

  defp load_signal!(id, actor) do
    case Commercial.get_signal(id, actor: actor, load: [:organization, :status_variant]) do
      {:ok, signal} -> signal
      {:error, error} -> raise "failed to load signal #{id}: #{inspect(error)}"
    end
  end

  defp load_pursuit!(id, actor) do
    case Commercial.get_pursuit(id, actor: actor, load: [:organization, :signal]) do
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

  defp pursuit_defaults_from_signal(signal) do
    %{
      "organization_id" => signal.organization_id,
      "name" => signal.title,
      "description" => signal.description,
      "notes" => signal.notes
    }
  end

  defp page_title(nil, nil), do: "New Pursuit"
  defp page_title(nil, _signal), do: "Create Pursuit From Signal"
  defp page_title(_pursuit, _signal), do: "Edit Pursuit"

  defp submit_label(pursuit, nil), do: if(pursuit, do: "Update Pursuit", else: "Create Pursuit")
  defp submit_label(nil, _signal), do: "Create Pursuit From Signal"

  defp submit_label(pursuit, _signal),
    do: if(pursuit, do: "Update Pursuit", else: "Create Pursuit")

  defp success_label(nil), do: "created"
  defp success_label(_pursuit), do: "updated"
end
