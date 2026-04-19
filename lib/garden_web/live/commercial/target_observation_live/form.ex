defmodule GnomeGardenWeb.Commercial.TargetObservationLive.Form do
  use GnomeGardenWeb, :live_view

  alias GnomeGarden.Commercial

  @impl true
  def mount(params, _session, socket) do
    observation =
      if id = params["id"], do: load_observation!(id, socket.assigns.current_user)

    target_accounts = load_target_accounts(socket.assigns.current_user)
    discovery_programs = load_discovery_programs(socket.assigns.current_user)

    {:ok,
     socket
     |> assign(:observation, observation)
     |> assign(:target_accounts, target_accounts)
     |> assign(:discovery_programs, discovery_programs)
     |> assign(:page_title, if(observation, do: "Edit Observation", else: "New Observation"))
     |> assign(:evidence_points_text, evidence_points_text(observation))
     |> assign_form(params)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.page max_width="max-w-5xl" class="pb-8">
      <.page_header eyebrow="Commercial">
        {@page_title}
        <:subtitle>
          Capture raw evidence separately from target promotion so discovery can scale without polluting the signal inbox.
        </:subtitle>
        <:actions>
          <.button navigate={~p"/commercial/observations"}>
            <.icon name="hero-arrow-left" class="size-4" /> Back to observations
          </.button>
        </:actions>
      </.page_header>

      <.form
        for={@form}
        id="target-observation-form"
        phx-change="validate"
        phx-submit="save"
        class="space-y-6"
      >
        <.form_section
          title="Observation Context"
          description="Treat observations as durable discovery evidence that can later support a target review decision."
        >
          <div class="grid grid-cols-1 gap-6 sm:grid-cols-6">
            <div class="sm:col-span-3">
              <.input
                field={@form[:target_account_id]}
                type="select"
                label="Target Account"
                prompt="Select target..."
                options={Enum.map(@target_accounts, &{&1.name, &1.id})}
              />
            </div>
            <div class="sm:col-span-3">
              <.input
                field={@form[:discovery_program_id]}
                type="select"
                label="Discovery Program"
                prompt="Select program..."
                options={Enum.map(@discovery_programs, &{&1.name, &1.id})}
              />
            </div>
            <div class="sm:col-span-3">
              <.input
                field={@form[:observation_type]}
                type="select"
                label="Observation Type"
                options={[
                  {"Hiring", :hiring},
                  {"Expansion", :expansion},
                  {"Legacy Stack", :legacy_stack},
                  {"Directory", :directory},
                  {"News", :news},
                  {"Referral", :referral},
                  {"Website Contact", :website_contact},
                  {"Bid Notice", :bid_notice},
                  {"Manual", :manual},
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
                  {"Company Website", :company_website},
                  {"Job Board", :job_board},
                  {"Directory", :directory},
                  {"News Site", :news_site},
                  {"Referral", :referral},
                  {"Agent Discovery", :agent_discovery},
                  {"Manual", :manual},
                  {"Other", :other}
                ]}
              />
            </div>
            <div class="sm:col-span-4">
              <.input field={@form[:summary]} label="Summary" required />
            </div>
            <div class="sm:col-span-2">
              <.input field={@form[:confidence_score]} type="number" label="Confidence Score" />
            </div>
            <div class="sm:col-span-3">
              <.input field={@form[:source_url]} label="Source URL" />
            </div>
            <div class="sm:col-span-3">
              <.input field={@form[:external_ref]} label="External Ref" />
            </div>
            <div class="sm:col-span-3">
              <.input field={@form[:observed_at]} type="datetime-local" label="Observed At" />
            </div>
            <div class="col-span-full">
              <.input field={@form[:raw_excerpt]} type="textarea" label="Raw Excerpt" />
            </div>
            <div class="col-span-full">
              <.input
                type="textarea"
                name="observation[evidence_points_text]"
                value={@evidence_points_text}
                label="Evidence Points"
              />
            </div>
          </div>
        </.form_section>

        <.section body_class="px-6 py-5 sm:px-7">
          <.form_actions
            cancel_path={~p"/commercial/observations"}
            submit_label={if @observation, do: "Update Observation", else: "Create Observation"}
          />
        </.section>
      </.form>
    </.page>
    """
  end

  @impl true
  def handle_event("validate", %{"form" => params, "observation" => payload}, socket) do
    evidence_points_text = Map.get(payload, "evidence_points_text", "")

    form =
      AshPhoenix.Form.validate(
        socket.assigns.form.source,
        normalized_params(params, evidence_points_text)
      )

    {:noreply,
     socket
     |> assign(:evidence_points_text, evidence_points_text)
     |> assign(:form, to_form(form))}
  end

  @impl true
  def handle_event("save", %{"form" => params, "observation" => payload}, socket) do
    evidence_points_text = Map.get(payload, "evidence_points_text", "")

    case AshPhoenix.Form.submit(socket.assigns.form.source,
           params: normalized_params(params, evidence_points_text)
         ) do
      {:ok, observation} ->
        {:noreply,
         socket
         |> put_flash(
           :info,
           "Observation #{if socket.assigns.observation, do: "updated", else: "created"}"
         )
         |> push_navigate(to: ~p"/commercial/observations/#{observation}")}

      {:error, form} ->
        {:noreply,
         socket
         |> assign(:evidence_points_text, evidence_points_text)
         |> assign(:form, to_form(form))}
    end
  end

  defp assign_form(
         %{assigns: %{observation: observation, current_user: actor}} = socket,
         params
       ) do
    form =
      if observation do
        AshPhoenix.Form.for_update(observation, :update, actor: actor, domain: Commercial)
      else
        AshPhoenix.Form.for_create(
          Commercial.TargetObservation,
          :create,
          actor: actor,
          domain: Commercial,
          params: seed_params(params)
        )
      end

    assign(socket, form: to_form(form))
  end

  defp load_observation!(id, actor) do
    case Commercial.get_target_observation(id, actor: actor) do
      {:ok, observation} -> observation
      {:error, error} -> raise "failed to load target observation #{id}: #{inspect(error)}"
    end
  end

  defp load_target_accounts(actor) do
    case Commercial.list_target_accounts(actor: actor) do
      {:ok, targets} -> Enum.sort_by(targets, &String.downcase(&1.name || ""))
      {:error, error} -> raise "failed to load target accounts: #{inspect(error)}"
    end
  end

  defp load_discovery_programs(actor) do
    case Commercial.list_discovery_programs(actor: actor) do
      {:ok, programs} -> Enum.sort_by(programs, &String.downcase(&1.name || ""))
      {:error, error} -> raise "failed to load discovery programs: #{inspect(error)}"
    end
  end

  defp evidence_points_text(nil), do: ""
  defp evidence_points_text(observation), do: Enum.join(observation.evidence_points || [], "\n")

  defp normalized_params(params, evidence_points_text) do
    Map.put(params, "evidence_points", split_lines(evidence_points_text))
  end

  defp seed_params(params) do
    %{}
    |> maybe_put("target_account_id", params["target_account_id"])
    |> maybe_put("discovery_program_id", params["discovery_program_id"])
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp split_lines(value) do
    value
    |> String.split("\n", trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end
end
