defmodule GnomeGardenWeb.Execution.ServiceTicketLive.Form do
  use GnomeGardenWeb, :live_view

  alias GnomeGarden.Commercial
  alias GnomeGarden.Execution
  alias GnomeGarden.Operations

  @impl true
  def mount(params, _session, socket) do
    service_ticket =
      if id = params["id"] do
        load_service_ticket!(id, socket.assigns.current_user)
      end

    {:ok,
     socket
     |> assign(:service_ticket, service_ticket)
     |> assign(:organizations, load_organizations(socket.assigns.current_user))
     |> assign(:sites, load_sites(socket.assigns.current_user))
     |> assign(:managed_systems, load_managed_systems(socket.assigns.current_user))
     |> assign(:assets, load_assets(socket.assigns.current_user))
     |> assign(:agreements, load_agreements(socket.assigns.current_user))
     |> assign(:people, load_people(socket.assigns.current_user))
     |> assign(:service_level_policies, load_service_level_policies(socket.assigns.current_user))
     |> assign(
       :page_title,
       if(service_ticket, do: "Edit Service Ticket", else: "New Service Ticket")
     )
     |> assign_form(params)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.page max_width="max-w-5xl" class="pb-8">
      <.page_header eyebrow="Execution">
        {@page_title}
        <:subtitle>
          Capture service intake with enough context to drive triage, dispatch, and later billing decisions.
        </:subtitle>
        <:actions>
          <.button navigate={~p"/execution/service-tickets"}>
            Back to tickets
          </.button>
        </:actions>
      </.page_header>

      <.form
        for={@form}
        id="service-ticket-form"
        phx-change="validate"
        phx-submit="save"
        class="space-y-6"
      >
        <.form_section
          title="Ticket Details"
          description="Tie the ticket to the right customer context, service severity, and intake channel before work begins."
        >
          <div class="grid grid-cols-1 gap-6 sm:grid-cols-6">
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
              <.input field={@form[:ticket_number]} label="Ticket Number" />
            </div>
            <div class="col-span-full">
              <.input field={@form[:title]} label="Title" required />
            </div>
            <div class="sm:col-span-3">
              <.input
                field={@form[:site_id]}
                type="select"
                label="Site"
                prompt="Select site..."
                options={Enum.map(@sites, &{site_label(&1), &1.id})}
              />
            </div>
            <div class="sm:col-span-3">
              <.input
                field={@form[:managed_system_id]}
                type="select"
                label="Managed System"
                prompt="Select system..."
                options={Enum.map(@managed_systems, &{system_label(&1), &1.id})}
              />
            </div>
            <div class="sm:col-span-3">
              <.input
                field={@form[:asset_id]}
                type="select"
                label="Asset"
                prompt="Select asset..."
                options={Enum.map(@assets, &{asset_label(&1), &1.id})}
              />
            </div>
            <div class="sm:col-span-3">
              <.input
                field={@form[:agreement_id]}
                type="select"
                label="Agreement"
                prompt="Select agreement..."
                options={Enum.map(@agreements, &{agreement_label(&1), &1.id})}
              />
            </div>
            <div class="sm:col-span-3">
              <.input
                field={@form[:requester_person_id]}
                type="select"
                label="Requester"
                prompt="Select requester..."
                options={Enum.map(@people, &{person_label(&1), &1.id})}
              />
            </div>
            <div class="sm:col-span-3">
              <.input
                field={@form[:service_level_policy_id]}
                type="select"
                label="SLA Policy"
                prompt="Select policy..."
                options={Enum.map(@service_level_policies, &{policy_label(&1), &1.id})}
              />
            </div>
            <div class="sm:col-span-2">
              <.input
                field={@form[:ticket_type]}
                type="select"
                label="Ticket Type"
                options={ticket_type_options()}
              />
            </div>
            <div class="sm:col-span-2">
              <.input
                field={@form[:source_channel]}
                type="select"
                label="Source Channel"
                options={source_channel_options()}
              />
            </div>
            <div class="sm:col-span-2">
              <.input
                field={@form[:severity]}
                type="select"
                label="Severity"
                options={severity_options()}
              />
            </div>
            <div class="sm:col-span-3">
              <.input field={@form[:impact]} type="select" label="Impact" options={impact_options()} />
            </div>
            <div class="sm:col-span-3">
              <.input field={@form[:due_on]} type="date" label="Due On" />
            </div>
            <div class="sm:col-span-3">
              <.input
                field={@form[:reported_at]}
                type="datetime-local"
                label="Reported At"
              />
            </div>
            <div class="col-span-full">
              <.input field={@form[:description]} type="textarea" label="Description" />
            </div>
            <div class="col-span-full">
              <.input
                field={@form[:resolution_summary]}
                type="textarea"
                label="Resolution Summary"
              />
            </div>
            <div class="col-span-full">
              <.input field={@form[:notes]} type="textarea" label="Notes" />
            </div>
          </div>
        </.form_section>

        <.section body_class="px-6 py-5 sm:px-7">
          <.form_actions
            cancel_path={~p"/execution/service-tickets"}
            submit_label={
              if @service_ticket, do: "Update Service Ticket", else: "Create Service Ticket"
            }
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
      {:ok, service_ticket} ->
        {:noreply,
         socket
         |> put_flash(
           :info,
           "Service ticket #{if socket.assigns.service_ticket, do: "updated", else: "created"}"
         )
         |> push_navigate(to: ~p"/execution/service-tickets/#{service_ticket}")}

      {:error, form} ->
        {:noreply, assign(socket, form: to_form(form))}
    end
  end

  defp assign_form(
         %{assigns: %{service_ticket: service_ticket, current_user: actor}} = socket,
         params
       ) do
    form =
      if service_ticket do
        AshPhoenix.Form.for_update(service_ticket, :update, actor: actor, domain: Execution)
      else
        AshPhoenix.Form.for_create(
          Execution.ServiceTicket,
          :create,
          actor: actor,
          domain: Execution,
          params: service_ticket_defaults(params)
        )
      end

    assign(socket, :form, to_form(form))
  end

  defp load_service_ticket!(id, actor) do
    case Execution.get_service_ticket(id, actor: actor) do
      {:ok, service_ticket} -> service_ticket
      {:error, error} -> raise "failed to load service ticket #{id}: #{inspect(error)}"
    end
  end

  defp load_organizations(actor) do
    case Operations.list_organizations(actor: actor) do
      {:ok, organizations} -> Enum.sort_by(organizations, &String.downcase(&1.name || ""))
      {:error, error} -> raise "failed to load organizations: #{inspect(error)}"
    end
  end

  defp load_sites(actor) do
    case Operations.list_sites(actor: actor, load: [:organization]) do
      {:ok, sites} -> Enum.sort_by(sites, &String.downcase(&1.name || ""))
      {:error, error} -> raise "failed to load sites: #{inspect(error)}"
    end
  end

  defp load_managed_systems(actor) do
    case Operations.list_managed_systems(actor: actor, load: [:organization]) do
      {:ok, systems} -> Enum.sort_by(systems, &String.downcase(&1.name || ""))
      {:error, error} -> raise "failed to load managed systems: #{inspect(error)}"
    end
  end

  defp load_assets(actor) do
    case Operations.list_assets(actor: actor, load: [:organization]) do
      {:ok, assets} -> Enum.sort_by(assets, &String.downcase(&1.name || ""))
      {:error, error} -> raise "failed to load assets: #{inspect(error)}"
    end
  end

  defp load_agreements(actor) do
    case Commercial.list_agreements(actor: actor, load: [:organization]) do
      {:ok, agreements} -> Enum.sort_by(agreements, &String.downcase(&1.name || ""))
      {:error, error} -> raise "failed to load agreements: #{inspect(error)}"
    end
  end

  defp load_people(actor) do
    case Operations.list_people(actor: actor) do
      {:ok, people} -> Enum.sort_by(people, &String.downcase(person_label(&1)))
      {:error, error} -> raise "failed to load people: #{inspect(error)}"
    end
  end

  defp load_service_level_policies(actor) do
    case Commercial.list_service_level_policies(actor: actor) do
      {:ok, policies} -> Enum.sort_by(policies, &String.downcase(&1.name || ""))
      {:error, error} -> raise "failed to load service level policies: #{inspect(error)}"
    end
  end

  defp service_ticket_defaults(params) do
    %{}
    |> maybe_put("organization_id", params["organization_id"])
    |> maybe_put("site_id", params["site_id"])
    |> maybe_put("managed_system_id", params["managed_system_id"])
    |> maybe_put("asset_id", params["asset_id"])
    |> maybe_put("agreement_id", params["agreement_id"])
    |> maybe_put("requester_person_id", params["requester_person_id"])
    |> maybe_put("service_level_policy_id", params["service_level_policy_id"])
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, _key, ""), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp site_label(site) do
    [site.name, site.organization && site.organization.name]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(" · ")
  end

  defp system_label(system) do
    [system.name, system.organization && system.organization.name]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(" · ")
  end

  defp asset_label(asset) do
    [asset.name, asset.organization && asset.organization.name]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(" · ")
  end

  defp agreement_label(agreement) do
    [agreement.name, agreement.organization && agreement.organization.name]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(" · ")
  end

  defp person_label(person) do
    [person.first_name, person.last_name]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(" ")
  end

  defp policy_label(policy), do: policy.name || "Untitled Policy"

  defp ticket_type_options do
    [
      {"Incident", :incident},
      {"Service Request", :service_request},
      {"Warranty", :warranty},
      {"Maintenance", :maintenance},
      {"Monitoring Alert", :monitoring_alert},
      {"Other", :other}
    ]
  end

  defp source_channel_options do
    [
      {"Email", :email},
      {"Phone", :phone},
      {"Portal", :portal},
      {"Monitoring", :monitoring},
      {"Manual", :manual},
      {"Other", :other}
    ]
  end

  defp severity_options do
    [{"Low", :low}, {"Normal", :normal}, {"High", :high}, {"Critical", :critical}]
  end

  defp impact_options do
    [
      {"Single Area", :single_area},
      {"Multi Area", :multi_area},
      {"Site Wide", :site_wide},
      {"Enterprise", :enterprise}
    ]
  end
end
