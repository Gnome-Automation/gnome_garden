defmodule GnomeGardenWeb.Commercial.DiscoveryProgramLive.Form do
  use GnomeGardenWeb, :live_view

  alias GnomeGarden.Commercial

  @list_fields [:target_regions, :target_industries, :search_terms, :watch_channels]

  @impl true
  def mount(params, _session, socket) do
    discovery_program =
      if id = params["id"], do: load_discovery_program!(id, socket.assigns.current_user)

    {:ok,
     socket
     |> assign(:discovery_program, discovery_program)
     |> assign(
       :page_title,
       if(discovery_program, do: "Edit Discovery Program", else: "New Discovery Program")
     )
     |> assign(:list_inputs, list_inputs_from_program(discovery_program))
     |> assign_form()}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.page max_width="max-w-5xl" class="pb-8">
      <.page_header eyebrow="Commercial">
        {@page_title}
        <:subtitle>
          Define how broad lead-finder work should hunt, where it should look, and how often it should cycle.
        </:subtitle>
        <:actions>
          <.button navigate={~p"/commercial/discovery-programs"}>
            <.icon name="hero-arrow-left" class="size-4" /> Back to programs
          </.button>
        </:actions>
      </.page_header>

      <.form
        for={@form}
        id="discovery-program-form"
        phx-change="validate"
        phx-submit="save"
        class="space-y-6"
      >
        <.form_section
          title="Program Definition"
          description="Keep discovery scoped enough that agents know what to hunt and operators know why the program exists."
        >
          <div class="grid grid-cols-1 gap-6 sm:grid-cols-6">
            <div class="sm:col-span-4">
              <.input field={@form[:name]} label="Name" required />
            </div>
            <div class="sm:col-span-2">
              <.input
                field={@form[:program_type]}
                type="select"
                label="Program Type"
                options={[
                  {"Market Scan", :market_scan},
                  {"Territory Watch", :territory_watch},
                  {"Industry Watch", :industry_watch},
                  {"Account Hunt", :account_hunt},
                  {"Referral Network", :referral_network},
                  {"Custom", :custom}
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
            <div class="sm:col-span-3">
              <.input field={@form[:cadence_hours]} type="number" label="Cadence (hours)" />
            </div>
            <div class="col-span-full">
              <.input field={@form[:description]} type="textarea" label="Description" />
            </div>
            <div class="sm:col-span-3">
              <.input
                type="textarea"
                name="program[target_regions_text]"
                value={@list_inputs.target_regions}
                label="Target Regions"
              />
            </div>
            <div class="sm:col-span-3">
              <.input
                type="textarea"
                name="program[target_industries_text]"
                value={@list_inputs.target_industries}
                label="Target Industries"
              />
            </div>
            <div class="sm:col-span-3">
              <.input
                type="textarea"
                name="program[search_terms_text]"
                value={@list_inputs.search_terms}
                label="Search Terms"
              />
            </div>
            <div class="sm:col-span-3">
              <.input
                type="textarea"
                name="program[watch_channels_text]"
                value={@list_inputs.watch_channels}
                label="Watch Channels"
              />
            </div>
            <div class="col-span-full">
              <.input field={@form[:notes]} type="textarea" label="Notes" />
            </div>
          </div>
        </.form_section>

        <.section body_class="px-6 py-5 sm:px-7">
          <.form_actions
            cancel_path={~p"/commercial/discovery-programs"}
            submit_label={if @discovery_program, do: "Update Program", else: "Create Program"}
          />
        </.section>
      </.form>
    </.page>
    """
  end

  @impl true
  def handle_event("validate", %{"form" => params} = payload, socket) do
    list_inputs = list_inputs_from_payload(payload)

    form =
      AshPhoenix.Form.validate(socket.assigns.form.source, normalized_params(params, list_inputs))

    {:noreply,
     socket
     |> assign(:list_inputs, list_inputs)
     |> assign(:form, to_form(form))}
  end

  @impl true
  def handle_event("save", %{"form" => params} = payload, socket) do
    list_inputs = list_inputs_from_payload(payload)

    case AshPhoenix.Form.submit(socket.assigns.form.source,
           params: normalized_params(params, list_inputs)
         ) do
      {:ok, discovery_program} ->
        {:noreply,
         socket
         |> put_flash(
           :info,
           "Discovery program #{if socket.assigns.discovery_program, do: "updated", else: "created"}"
         )
         |> push_navigate(to: ~p"/commercial/discovery-programs/#{discovery_program}")}

      {:error, form} ->
        {:noreply,
         socket
         |> assign(:list_inputs, list_inputs)
         |> assign(:form, to_form(form))}
    end
  end

  defp assign_form(
         %{assigns: %{discovery_program: discovery_program, current_user: actor}} = socket
       ) do
    form =
      if discovery_program do
        AshPhoenix.Form.for_update(discovery_program, :update, actor: actor, domain: Commercial)
      else
        AshPhoenix.Form.for_create(
          Commercial.DiscoveryProgram,
          :create,
          actor: actor,
          domain: Commercial
        )
      end

    assign(socket, form: to_form(form))
  end

  defp load_discovery_program!(id, actor) do
    case Commercial.get_discovery_program(id, actor: actor) do
      {:ok, discovery_program} -> discovery_program
      {:error, error} -> raise "failed to load discovery program #{id}: #{inspect(error)}"
    end
  end

  defp list_inputs_from_program(nil) do
    Map.new(@list_fields, &{&1, ""})
  end

  defp list_inputs_from_program(program) do
    %{
      target_regions: Enum.join(program.target_regions || [], ", "),
      target_industries: Enum.join(program.target_industries || [], ", "),
      search_terms: Enum.join(program.search_terms || [], "\n"),
      watch_channels: Enum.join(program.watch_channels || [], ", ")
    }
  end

  defp list_inputs_from_payload(payload) do
    program_params = Map.get(payload, "program", %{})

    %{
      target_regions: Map.get(program_params, "target_regions_text", ""),
      target_industries: Map.get(program_params, "target_industries_text", ""),
      search_terms: Map.get(program_params, "search_terms_text", ""),
      watch_channels: Map.get(program_params, "watch_channels_text", "")
    }
  end

  defp normalized_params(params, list_inputs) do
    params
    |> Map.put("target_regions", split_csv(list_inputs.target_regions))
    |> Map.put("target_industries", split_csv(list_inputs.target_industries))
    |> Map.put("search_terms", split_lines(list_inputs.search_terms))
    |> Map.put("watch_channels", split_csv(list_inputs.watch_channels))
  end

  defp split_csv(value) do
    value
    |> String.split(",", trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  defp split_lines(value) do
    value
    |> String.split("\n", trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end
end
