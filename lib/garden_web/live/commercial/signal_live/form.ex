defmodule GnomeGardenWeb.Commercial.SignalLive.Form do
  use GnomeGardenWeb, :live_view

  alias GnomeGarden.Commercial
  alias GnomeGarden.Operations

  @impl true
  def mount(params, _session, socket) do
    signal = if id = params["id"], do: load_signal!(id, socket.assigns.current_user)
    organizations = load_organizations(socket.assigns.current_user)

    {:ok,
     socket
     |> assign(:signal, signal)
     |> assign(:organizations, organizations)
     |> assign(:page_title, if(signal, do: "Edit Signal", else: "New Signal"))
     |> assign_form()}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.page max_width="max-w-5xl" class="pb-8">
      <.page_header eyebrow="Commercial">
        {@page_title}
        <:subtitle>
          Capture raw market intelligence before it becomes real commercial pipeline.
        </:subtitle>
        <:actions>
          <.button navigate={~p"/commercial/signals"}>
            <.icon name="hero-arrow-left" class="size-4" /> Back to inbox
          </.button>
        </:actions>
      </.page_header>

      <.form for={@form} id="signal-form" phx-change="validate" phx-submit="save" class="space-y-6">
        <.form_section
          title="Signal Details"
          description="Describe the raw lead, bid, or market trigger that just entered the system."
        >
          <div class="grid grid-cols-1 gap-6 sm:grid-cols-6">
            <div class="sm:col-span-4">
              <.input field={@form[:title]} label="Title" required />
            </div>
            <div class="sm:col-span-3">
              <.input
                field={@form[:signal_type]}
                type="select"
                label="Signal Type"
                options={[
                  {"Bid Notice", :bid_notice},
                  {"Inbound Request", :inbound_request},
                  {"Outbound Target", :outbound_target},
                  {"Referral", :referral},
                  {"Renewal", :renewal},
                  {"Service Need", :service_need},
                  {"Market Signal", :market_signal},
                  {"Other", :other}
                ]}
              />
            </div>
            <div class="sm:col-span-3">
              <.input
                field={@form[:source_channel]}
                type="select"
                label="Source Channel"
                options={[
                  {"Procurement Portal", :procurement_portal},
                  {"Website", :website},
                  {"Email", :email},
                  {"Phone", :phone},
                  {"Referral", :referral},
                  {"Agent Discovery", :agent_discovery},
                  {"Service Event", :service_event},
                  {"Manual", :manual},
                  {"Other", :other}
                ]}
              />
            </div>
            <div class="sm:col-span-4">
              <.input
                field={@form[:organization_id]}
                type="select"
                label="Organization"
                prompt="Select organization..."
                options={Enum.map(@organizations, &{&1.name, &1.id})}
              />
            </div>
            <div class="sm:col-span-3">
              <.input field={@form[:external_ref]} label="External Ref" />
            </div>
            <div class="sm:col-span-3">
              <.input field={@form[:observed_at]} label="Observed At" type="datetime-local" />
            </div>
            <div class="col-span-full">
              <.input field={@form[:source_url]} label="Source URL" />
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
            cancel_path={~p"/commercial/signals"}
            submit_label={if @signal, do: "Update Signal", else: "Create Signal"}
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
      {:ok, signal} ->
        {:noreply,
         socket
         |> put_flash(:info, "Signal #{if socket.assigns.signal, do: "updated", else: "created"}")
         |> push_navigate(to: ~p"/commercial/signals/#{signal}")}

      {:error, form} ->
        {:noreply, assign(socket, form: to_form(form))}
    end
  end

  defp assign_form(%{assigns: %{signal: signal, current_user: actor}} = socket) do
    form =
      if signal do
        AshPhoenix.Form.for_update(signal, :update, actor: actor, domain: Commercial)
      else
        AshPhoenix.Form.for_create(Commercial.Signal, :create, actor: actor, domain: Commercial)
      end

    assign(socket, form: to_form(form))
  end

  defp load_signal!(id, actor) do
    case Commercial.get_signal(id, actor: actor) do
      {:ok, signal} -> signal
      {:error, error} -> raise "failed to load signal #{id}: #{inspect(error)}"
    end
  end

  defp load_organizations(actor) do
    case Operations.list_organizations(actor: actor) do
      {:ok, organizations} -> Enum.sort_by(organizations, &String.downcase(&1.name || ""))
      {:error, error} -> raise "failed to load organizations: #{inspect(error)}"
    end
  end
end
