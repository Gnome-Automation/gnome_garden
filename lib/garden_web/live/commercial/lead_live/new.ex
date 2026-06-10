defmodule GnomeGardenWeb.Commercial.LeadLive.New do
  use GnomeGardenWeb, :live_view

  alias GnomeGarden.Commercial
  alias GnomeGarden.Commercial.LeadIntake.Submission

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "New Lead")
     |> assign_form()}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.page max_width="max-w-6xl" class="pb-8">
      <.page_header eyebrow="Commercial">
        New Lead
        <:subtitle>
          Capture a referral, inbound request, or manually discovered opportunity and create the company, contacts, signal, and follow-up task in one governed Ash workflow.
        </:subtitle>
        <:actions>
          <.button navigate={~p"/commercial/signals"}>Back to signals</.button>
        </:actions>
      </.page_header>

      <.form
        for={@form}
        id="lead-intake-form"
        phx-change="validate"
        phx-submit="save"
        class="space-y-6"
      >
        <.inputs_for :let={organization_form} field={@form[:organization]}>
          <.form_section
            title="Company"
            description="Who is this lead for? The organization is upserted by name and normalized by website."
          >
            <div class="grid grid-cols-1 gap-6 sm:grid-cols-6">
              <div class="sm:col-span-3">
                <.input field={organization_form[:name]} label="Company Name" required />
              </div>
              <div class="sm:col-span-3">
                <.input field={organization_form[:legal_name]} label="Legal Name" />
              </div>
              <div class="sm:col-span-3">
                <.input
                  field={organization_form[:website]}
                  label="Website"
                  placeholder="https://example.com"
                />
              </div>
              <div class="sm:col-span-3">
                <.input field={organization_form[:phone]} label="Main Phone" />
              </div>
              <div class="sm:col-span-2">
                <.input
                  field={organization_form[:primary_region]}
                  label="Primary Region"
                  placeholder="CA"
                />
              </div>
              <div class="sm:col-span-4">
                <.input field={organization_form[:notes]} label="Company Notes" />
              </div>
            </div>
          </.form_section>
        </.inputs_for>

        <.form_section
          title="Sites"
          description="Add known facilities or offices. Start with the site most likely tied to the opportunity."
        >
          <div class="space-y-4">
            <.inputs_for :let={site_form} field={@form[:sites]}>
              <div class="rounded-2xl border border-base-300/70 bg-base-100/70 p-4 dark:border-white/10 dark:bg-white/[0.03]">
                <div class="mb-4 flex items-center justify-between gap-3">
                  <p class="text-sm font-semibold text-base-content">Site</p>
                  <button
                    type="button"
                    phx-click="remove-form"
                    phx-value-path={site_form.name}
                    class="text-sm font-medium text-error hover:text-error/80"
                  >
                    Remove
                  </button>
                </div>
                <div class="grid grid-cols-1 gap-4 sm:grid-cols-6">
                  <div class="sm:col-span-3">
                    <.input field={site_form[:name]} label="Site Name" required />
                  </div>
                  <div class="sm:col-span-3">
                    <.input field={site_form[:address1]} label="Address" />
                  </div>
                  <div class="sm:col-span-2">
                    <.input field={site_form[:city]} label="City" />
                  </div>
                  <div class="sm:col-span-1">
                    <.input field={site_form[:state]} label="State" />
                  </div>
                  <div class="sm:col-span-1">
                    <.input field={site_form[:postal_code]} label="Postal" />
                  </div>
                  <div class="sm:col-span-2">
                    <.input field={site_form[:country_code]} label="Country" placeholder="US" />
                  </div>
                  <div class="sm:col-span-3">
                    <.input
                      field={site_form[:timezone]}
                      label="Timezone"
                      placeholder="America/Los_Angeles"
                    />
                  </div>
                  <div class="sm:col-span-3">
                    <.input field={site_form[:notes]} label="Site Notes" />
                  </div>
                </div>
              </div>
            </.inputs_for>
          </div>
          <div class="mt-4">
            <.button type="button" phx-click="add-site">Add Site</.button>
          </div>
        </.form_section>

        <.form_section
          title="Contacts"
          description="Add referral, procurement, technical, facilities, validation, or commercial contacts."
        >
          <div class="space-y-4">
            <.inputs_for :let={contact_form} field={@form[:contacts]}>
              <div class="rounded-2xl border border-base-300/70 bg-base-100/70 p-4 dark:border-white/10 dark:bg-white/[0.03]">
                <div class="mb-4 flex items-center justify-between gap-3">
                  <p class="text-sm font-semibold text-base-content">Contact</p>
                  <button
                    type="button"
                    phx-click="remove-form"
                    phx-value-path={contact_form.name}
                    class="text-sm font-medium text-error hover:text-error/80"
                  >
                    Remove
                  </button>
                </div>
                <div class="grid grid-cols-1 gap-4 sm:grid-cols-6">
                  <div class="sm:col-span-2">
                    <.input field={contact_form[:first_name]} label="First Name" required />
                  </div>
                  <div class="sm:col-span-2">
                    <.input field={contact_form[:last_name]} label="Last Name" required />
                  </div>
                  <div class="sm:col-span-2">
                    <.input field={contact_form[:email]} label="Email" />
                  </div>
                  <div class="sm:col-span-2">
                    <.input field={contact_form[:phone]} label="Phone" />
                  </div>
                  <div class="sm:col-span-2">
                    <.input field={contact_form[:mobile]} label="Mobile" />
                  </div>
                  <div class="sm:col-span-2 flex items-end">
                    <.input field={contact_form[:is_primary]} type="checkbox" label="Primary contact" />
                  </div>
                  <div class="sm:col-span-3">
                    <.input field={contact_form[:title]} label="Title" />
                  </div>
                  <div class="sm:col-span-3">
                    <.input field={contact_form[:department]} label="Department" />
                  </div>
                  <div class="sm:col-span-3">
                    <.input
                      field={contact_form[:contact_roles]}
                      label="Roles"
                      placeholder="referrer, procurement, technical_stakeholder"
                    />
                  </div>
                  <div class="sm:col-span-3">
                    <.input field={contact_form[:notes]} label="Contact Notes" />
                  </div>
                </div>
              </div>
            </.inputs_for>
          </div>
          <div class="mt-4">
            <.button type="button" phx-click="add-contact">Add Contact</.button>
          </div>
        </.form_section>

        <.inputs_for :let={signal_form} field={@form[:signal]}>
          <.form_section
            title="Lead Signal"
            description="Describe why this lead matters and what work might exist."
          >
            <div class="grid grid-cols-1 gap-6 sm:grid-cols-6">
              <div class="sm:col-span-4">
                <.input field={signal_form[:title]} label="Lead Title" required />
              </div>
              <div class="sm:col-span-2">
                <.input field={signal_form[:referral_source]} label="Referral Source" />
              </div>
              <div class="sm:col-span-3">
                <.input field={signal_form[:source_url]} label="Source URL" />
              </div>
              <div class="sm:col-span-3">
                <.input field={signal_form[:external_ref]} label="External Ref" />
              </div>
              <div class="col-span-full">
                <.input field={signal_form[:description]} type="textarea" label="Description" />
              </div>
              <div class="col-span-full">
                <.input
                  field={signal_form[:suspected_needs]}
                  type="textarea"
                  label="Suspected Needs"
                  placeholder="PLC, SCADA, controls, validation, facilities, historian, reporting"
                />
              </div>
              <div class="col-span-full">
                <.input field={signal_form[:notes]} type="textarea" label="Notes" />
              </div>
            </div>
          </.form_section>
        </.inputs_for>

        <.inputs_for :let={task_form} field={@form[:task]}>
          <.form_section
            title="Next Action"
            description="Optionally create an operator follow-up task linked to the new signal."
          >
            <div class="grid grid-cols-1 gap-6 sm:grid-cols-6">
              <div class="sm:col-span-4">
                <.input field={task_form[:title]} label="Task Title" />
              </div>
              <div class="sm:col-span-1">
                <.input
                  field={task_form[:task_type]}
                  type="select"
                  label="Type"
                  options={[
                    {"Call", :call},
                    {"Email", :email},
                    {"Research", :research},
                    {"Review", :review},
                    {"Other", :other}
                  ]}
                />
              </div>
              <div class="sm:col-span-1">
                <.input
                  field={task_form[:priority]}
                  type="select"
                  label="Priority"
                  options={[{"Low", :low}, {"Normal", :normal}, {"High", :high}, {"Urgent", :urgent}]}
                />
              </div>
              <div class="col-span-full">
                <.input field={task_form[:description]} type="textarea" label="Task Description" />
              </div>
            </div>
          </.form_section>
        </.inputs_for>

        <.section body_class="px-6 py-5 sm:px-7">
          <.form_actions cancel_path={~p"/commercial/signals"} submit_label="Create Lead" />
        </.section>
      </.form>
    </.page>
    """
  end

  @impl true
  def handle_event("validate", %{"form" => params}, socket) do
    form = AshPhoenix.Form.validate(socket.assigns.form.source, params)
    {:noreply, assign(socket, form: to_form(form))}
  end

  def handle_event("add-site", _params, socket) do
    form = AshPhoenix.Form.add_form(socket.assigns.form.source, :sites)
    {:noreply, assign(socket, form: to_form(form))}
  end

  def handle_event("add-contact", _params, socket) do
    form = AshPhoenix.Form.add_form(socket.assigns.form.source, :contacts)
    {:noreply, assign(socket, form: to_form(form))}
  end

  def handle_event("remove-form", %{"path" => path}, socket) do
    form = AshPhoenix.Form.remove_form(socket.assigns.form.source, path)
    {:noreply, assign(socket, form: to_form(form))}
  end

  def handle_event("save", %{"form" => params}, socket) do
    case AshPhoenix.Form.submit(socket.assigns.form.source, params: params) do
      {:ok, submission} ->
        attrs = Submission.to_lead_attrs(submission)

        case Commercial.create_referral_lead(attrs, actor: socket.assigns.current_user) do
          {:ok, result} ->
            {:noreply,
             socket
             |> put_flash(:info, "Lead created")
             |> push_navigate(to: ~p"/commercial/signals/#{result.signal.id}")}

          {:error, error} ->
            {:noreply, put_flash(socket, :error, "Could not create lead: #{inspect(error)}")}
        end

      {:error, form} ->
        {:noreply, assign(socket, form: to_form(form))}
    end
  end

  defp assign_form(socket) do
    form =
      Submission
      |> AshPhoenix.Form.for_create(:create,
        actor: socket.assigns.current_user,
        forms: nested_forms(),
        params: default_params(),
        prepare_params: &prepare_form_params/2
      )
      |> to_form()

    assign(socket, :form, form)
  end

  defp nested_forms do
    [
      auto?: false,
      organization: [
        type: :single,
        resource: GnomeGarden.Commercial.LeadIntake.OrganizationInput,
        create_action: :create
      ],
      sites: [
        type: :list,
        resource: GnomeGarden.Commercial.LeadIntake.SiteInput,
        create_action: :create
      ],
      contacts: [
        type: :list,
        resource: GnomeGarden.Commercial.LeadIntake.ContactInput,
        create_action: :create
      ],
      signal: [
        type: :single,
        resource: GnomeGarden.Commercial.LeadIntake.SignalInput,
        create_action: :create
      ],
      task: [
        type: :single,
        resource: GnomeGarden.Commercial.LeadIntake.TaskInput,
        create_action: :create
      ]
    ]
  end

  defp prepare_form_params(params, _type) when is_map(params) do
    params
    |> update_nested_collection("contacts", fn contact ->
      Map.update(contact, "contact_roles", [], &split_lines/1)
    end)
    |> update_nested_map("signal", fn signal ->
      Map.update(signal, "suspected_needs", [], &split_lines/1)
    end)
  end

  defp prepare_form_params(params, _type), do: params

  defp update_nested_map(params, key, fun) do
    case Map.get(params, key) do
      %{} = nested -> Map.put(params, key, fun.(nested))
      _other -> params
    end
  end

  defp update_nested_collection(params, key, fun) do
    case Map.get(params, key) do
      %{} = nested ->
        Map.put(params, key, Map.new(nested, fn {index, value} -> {index, fun.(value)} end))

      list when is_list(list) ->
        Map.put(params, key, Enum.map(list, fun))

      _other ->
        params
    end
  end

  defp split_lines(values) when is_list(values),
    do: values |> Enum.flat_map(&split_lines/1) |> Enum.uniq()

  defp split_lines(value) when is_binary(value) do
    value
    |> String.split([",", "\n"], trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  defp split_lines(_value), do: []

  defp default_params do
    %{
      "organization" => %{"name" => ""},
      "sites" => [%{"name" => ""}],
      "contacts" => [%{"first_name" => "", "last_name" => "", "is_primary" => "true"}],
      "signal" => %{"title" => ""},
      "task" => %{"task_type" => "call", "priority" => "high"}
    }
  end
end
