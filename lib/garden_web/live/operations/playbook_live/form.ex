defmodule GnomeGardenWeb.Operations.PlaybookLive.Form do
  use GnomeGardenWeb, :live_view

  alias GnomeGarden.Operations

  @impl true
  def mount(params, _session, socket) do
    playbook = if id = params["id"], do: load_playbook!(id, socket.assigns.current_user)

    {:ok,
     socket
     |> assign(:playbook, playbook)
     |> assign(:page_title, if(playbook, do: "Edit Playbook", else: "New Playbook"))
     |> assign_form()}
  end

  @impl true
  def handle_event("validate", %{"form" => params}, socket) do
    form = AshPhoenix.Form.validate(socket.assigns.form, params)
    {:noreply, assign(socket, form: to_form(form))}
  end

  @impl true
  def handle_event("save", %{"form" => params}, socket) do
    case AshPhoenix.Form.submit(socket.assigns.form, params: params) do
      {:ok, playbook} ->
        {:noreply,
         socket
         |> put_flash(
           :info,
           "Playbook #{if socket.assigns.playbook, do: "updated", else: "created"}"
         )
         |> push_navigate(to: ~p"/operations/playbooks/#{playbook}")}

      {:error, form} ->
        {:noreply, assign(socket, form: to_form(form))}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.page max_width="max-w-3xl" class="pb-8">
      <.page_header eyebrow="Operations">
        {@page_title}
        <:subtitle>
          A playbook is a reusable set of ordered task steps applied to a record.
        </:subtitle>
        <:actions>
          <.button navigate={~p"/operations/playbooks"}>
            Back to playbooks
          </.button>
        </:actions>
      </.page_header>

      <.form for={@form} id="playbook-form" phx-change="validate" phx-submit="save" class="space-y-6">
        <.form_section title="Playbook">
          <div class="grid grid-cols-1 gap-6">
            <.input field={@form[:name]} label="Name" required />
            <.input field={@form[:description]} type="textarea" label="Description" />
          </div>
        </.form_section>

        <.section body_class="px-6 py-5 sm:px-7">
          <.form_actions
            cancel_path={~p"/operations/playbooks"}
            submit_label={if @playbook, do: "Save Changes", else: "Create Playbook"}
          />
        </.section>
      </.form>
    </.page>
    """
  end

  defp assign_form(%{assigns: %{playbook: playbook, current_user: actor}} = socket) do
    form =
      if playbook do
        AshPhoenix.Form.for_update(playbook, :update, actor: actor, domain: Operations)
      else
        AshPhoenix.Form.for_create(Operations.Playbook, :create, actor: actor, domain: Operations)
      end

    assign(socket, :form, to_form(form))
  end

  defp load_playbook!(id, actor) do
    case Operations.get_playbook(id, actor: actor) do
      {:ok, playbook} -> playbook
      {:error, error} -> raise "failed to load playbook #{id}: #{inspect(error)}"
    end
  end
end
