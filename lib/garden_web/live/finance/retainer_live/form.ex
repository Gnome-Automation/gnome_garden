defmodule GnomeGardenWeb.Finance.RetainerLive.Form do
  use GnomeGardenWeb, :live_view

  alias GnomeGarden.Finance
  alias GnomeGarden.Operations

  @impl true
  def mount(params, _session, socket) do
    retainer = if id = params["id"], do: load_retainer!(id, socket.assigns.current_user)

    {:ok,
     socket
     |> assign(:retainer, retainer)
     |> assign(:organizations, load_organizations(socket.assigns.current_user))
     |> assign(:return_to, params["return_to"] || ~p"/finance/retainers")
     |> assign(:page_title, if(retainer, do: "Edit Retainer", else: "New Retainer"))
     |> assign_form(params)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.page max_width="max-w-3xl" class="pb-8">
      <.page_header eyebrow="Finance / Retainers">
        {@page_title}
        <:actions>
          <.button navigate={@return_to}>
            Back to retainers
          </.button>
        </:actions>
      </.page_header>

      <.form
        for={@form}
        id="retainer-form"
        phx-change="validate"
        phx-submit="save"
        class="space-y-6"
      >
        <.form_section title="Retainer Details" description="Record a client pre-payment held on account.">
          <div class="grid grid-cols-1 gap-6 sm:grid-cols-6">
            <div class="sm:col-span-4">
              <.input
                field={@form[:organization_id]}
                type="select"
                label="Client"
                prompt="Select client..."
                options={Enum.map(@organizations, &{&1.name, &1.id})}
                required
              />
              <p class="mt-1.5 text-xs text-base-content/50">
                Not in the list?
                <.link navigate={~p"/operations/organizations/new"} class="underline text-emerald-600 dark:text-emerald-400">Add a client first</.link>.
              </p>
            </div>
            <div class="sm:col-span-2">
              <.input
                field={@form[:amount]}
                type="number"
                step="0.01"
                label="Amount"
                required
              />
            </div>
            <div class="sm:col-span-3">
              <.input field={@form[:received_on]} type="date" label="Received On" />
            </div>
            <div class="sm:col-span-3 flex items-end pb-1">
              <label class="flex items-center gap-2 cursor-pointer">
                <input
                  type="checkbox"
                  name={@form[:auto_apply].name}
                  id={@form[:auto_apply].id}
                  checked={@form[:auto_apply].value in [true, "true"]}
                  value="true"
                  class="checkbox checkbox-sm checkbox-primary"
                />
                <span class="block text-sm/6 font-medium text-gray-900 dark:text-white">Auto-apply to new invoices</span>
              </label>
            </div>
            <div class="col-span-full">
              <.input field={@form[:notes]} type="textarea" label="Notes" />
            </div>
          </div>
        </.form_section>

        <.section body_class="px-6 py-5 sm:px-7">
          <.form_actions
            cancel_path={@return_to}
            submit_label={if @retainer, do: "Update Retainer", else: "Create Retainer"}
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
      {:ok, retainer} ->
        {:noreply,
         socket
         |> put_flash(:info, if(socket.assigns.retainer, do: "Retainer updated.", else: "Retainer created."))
         |> push_navigate(to: ~p"/finance/retainers/#{retainer.id}")}

      {:error, form} ->
        {:noreply,
         socket
         |> put_flash(:error, "Please fix the errors below.")
         |> assign(form: to_form(form))}
    end
  end

  defp assign_form(%{assigns: %{retainer: retainer, current_user: actor}} = socket, params) do
    form =
      if retainer do
        AshPhoenix.Form.for_update(retainer, :update, actor: actor, domain: Finance)
      else
        defaults =
          %{}
          |> maybe_put("organization_id", params["organization_id"])
          |> maybe_put("received_on", Date.to_iso8601(Date.utc_today()))

        AshPhoenix.Form.for_create(
          Finance.Retainer,
          :create,
          actor: actor,
          domain: Finance,
          params: defaults
        )
      end

    assign(socket, :form, to_form(form))
  end

  defp load_retainer!(id, actor) do
    case Finance.get_retainer(id, actor: actor) do
      {:ok, retainer} -> retainer
      {:error, error} -> raise "failed to load retainer #{id}: #{inspect(error)}"
    end
  end

  defp load_organizations(actor) do
    case Operations.list_organizations(actor: actor) do
      {:ok, organizations} -> Enum.sort_by(organizations, &String.downcase(&1.name || ""))
      {:error, error} -> raise "failed to load organizations: #{inspect(error)}"
    end
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, _key, ""), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
