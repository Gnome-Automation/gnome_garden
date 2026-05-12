defmodule GnomeGardenWeb.Acquisition.FindingEvidenceLive.Form do
  use GnomeGardenWeb, :live_view

  alias GnomeGarden.Acquisition
  alias GnomeGarden.Commercial

  @impl true
  def mount(params, _session, socket) do
    evidence =
      if id = params["id"], do: load_evidence!(id, socket.assigns.current_user)

    seed_finding = load_seed_finding(params, evidence, socket.assigns.current_user)

    discovery_records =
      if seed_finding, do: [], else: load_discovery_records(socket.assigns.current_user)

    discovery_programs = load_discovery_programs(socket.assigns.current_user)

    {:ok,
     socket
     |> assign(:observation, evidence)
     |> assign(:seed_finding, seed_finding)
     |> assign(:discovery_records, discovery_records)
     |> assign(:discovery_programs, discovery_programs)
     |> assign(:page_title, if(evidence, do: "Edit Evidence", else: "New Evidence"))
     |> assign(:evidence_points_text, evidence_points_text(evidence))
     |> assign_form(params)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.page class="pb-8">
      <.page_header eyebrow="Acquisition">
        {@page_title}
        <:subtitle>
          Capture durable discovery evidence against an intake finding so promotion stays explainable.
        </:subtitle>
        <:actions>
          <.button navigate={back_path(@seed_finding)}>
            Back
          </.button>
        </:actions>
      </.page_header>

      <div class="grid gap-5 lg:grid-cols-[minmax(0,1fr)_22rem]">
        <.form
          for={@form}
          id="finding-evidence-form"
          phx-change="validate"
          phx-submit="save"
          class="space-y-5"
        >
          <.section
            title="Evidence Capture"
            description="Attach durable source observations that explain why this discovery finding exists."
          >
            <div class="grid grid-cols-1 gap-6 sm:grid-cols-6">
              <div :if={@seed_finding} class="col-span-full">
                <.input field={@form[:discovery_record_id]} type="hidden" />
                <.input field={@form[:discovery_program_id]} type="hidden" />
              </div>

              <div :if={is_nil(@seed_finding)} class="sm:col-span-3">
                <.input
                  field={@form[:discovery_record_id]}
                  type="select"
                  label="Discovery Record"
                  prompt="Select record..."
                  options={Enum.map(@discovery_records, &{&1.name, &1.id})}
                />
              </div>

              <div :if={is_nil(@seed_finding)} class="sm:col-span-3">
                <.input
                  field={@form[:discovery_program_id]}
                  type="select"
                  label="Program"
                  prompt="Select program..."
                  options={Enum.map(@discovery_programs, &{&1.name, &1.id})}
                />
              </div>

              <div class="sm:col-span-3">
                <.input
                  field={@form[:observation_type]}
                  type="select"
                  label="Evidence Type"
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
          </.section>

          <.section body_class="px-4 py-4 sm:px-5">
            <.form_actions
              cancel_path={back_path(@seed_finding)}
              submit_label={if @observation, do: "Update Evidence", else: "Create Evidence"}
            />
          </.section>
        </.form>

        <aside class="space-y-5">
          <.section title="Finding Context">
            <div class="space-y-3">
              <%= if @seed_finding do %>
                <div>
                  <p class="text-xs font-semibold uppercase tracking-[0.18em] text-base-content/40">
                    Intake Finding
                  </p>
                  <p class="mt-1 text-sm font-semibold text-base-content">
                    {@seed_finding.title}
                  </p>
                  <p class="mt-1 text-sm text-base-content/70">
                    {@seed_finding.summary || "No summary captured yet."}
                  </p>
                </div>

                <div class="grid gap-2 text-sm">
                  <.context_fact
                    label="Program"
                    value={
                      if @seed_finding.program,
                        do: @seed_finding.program.name,
                        else: "No program linked"
                    }
                  />
                  <.context_fact
                    label="Discovery Record"
                    value={
                      if @seed_finding.source_discovery_record,
                        do: @seed_finding.source_discovery_record.name,
                        else: "No discovery record linked"
                    }
                  />
                  <.context_fact
                    label="Family"
                    value={format_context_atom(@seed_finding.finding_family)}
                  />
                </div>
              <% else %>
                <p class="text-sm leading-6 text-base-content/65">
                  Choose a discovery record or program in the form. Evidence created here will sync back into the acquisition finding for that discovery record.
                </p>
              <% end %>
            </div>
          </.section>

          <.section title="Evidence Quality">
            <div class="space-y-2">
              <.quality_rule label="Specific source URL" />
              <.quality_rule label="Short summary" />
              <.quality_rule label="Raw excerpt when available" />
              <.quality_rule label="One point per line" />
            </div>
          </.section>
        </aside>
      </div>
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
           "Evidence #{if socket.assigns.observation, do: "updated", else: "created"}"
         )
         |> push_navigate(to: redirect_path_for_observation(observation))}

      {:error, form} ->
        {:noreply,
         socket
         |> assign(:evidence_points_text, evidence_points_text)
         |> assign(:form, to_form(form))}
    end
  end

  attr :label, :string, required: true
  attr :value, :string, required: true

  defp context_fact(assigns) do
    ~H"""
    <div class="rounded-lg border border-base-content/10 bg-base-200/70 px-3 py-2">
      <p class="text-[11px] font-semibold uppercase tracking-[0.14em] text-base-content/45">
        {@label}
      </p>
      <p class="mt-1 text-sm font-medium text-base-content">{@value}</p>
    </div>
    """
  end

  attr :label, :string, required: true

  defp quality_rule(assigns) do
    ~H"""
    <div class="flex items-center gap-2 rounded-lg border border-sky-200 bg-sky-50/70 px-3 py-2 text-sm text-sky-800 dark:border-sky-400/20 dark:bg-sky-400/10 dark:text-sky-200">
      <.icon name="hero-check" class="size-4" />
      <span>{@label}</span>
    </div>
    """
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
          Commercial.DiscoveryEvidence,
          :create,
          actor: actor,
          domain: Commercial,
          params: seed_params(params, actor)
        )
      end

    assign(socket, form: to_form(form))
  end

  defp load_evidence!(id, actor) do
    case Commercial.get_discovery_evidence(id, actor: actor) do
      {:ok, evidence} -> evidence
      {:error, error} -> raise "failed to load discovery evidence #{id}: #{inspect(error)}"
    end
  end

  defp load_discovery_records(actor) do
    case Commercial.list_discovery_records(actor: actor) do
      {:ok, targets} -> Enum.sort_by(targets, &String.downcase(&1.name || ""))
      {:error, error} -> raise "failed to load discovery records: #{inspect(error)}"
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

  defp seed_params(params, actor) do
    %{}
    |> put_finding_seed(params["finding_id"], actor)
    |> maybe_put("discovery_record_id", params["discovery_record_id"])
    |> maybe_put("discovery_program_id", params["discovery_program_id"])
  end

  defp load_seed_finding(params, observation, actor) do
    cond do
      is_binary(params["finding_id"]) ->
        case Acquisition.get_finding(
               params["finding_id"],
               actor: actor,
               load: [:source_discovery_record, program: [:discovery_program]]
             ) do
          {:ok, finding} -> finding
          _ -> nil
        end

      observation && observation.discovery_record_id ->
        case Acquisition.get_finding_by_source_discovery_record(
               observation.discovery_record_id,
               actor: actor,
               load: [:source_discovery_record, program: [:discovery_program]]
             ) do
          {:ok, finding} -> finding
          _ -> nil
        end

      true ->
        nil
    end
  end

  defp put_finding_seed(map, nil, _actor), do: map

  defp put_finding_seed(map, finding_id, actor) do
    case Acquisition.get_finding(
           finding_id,
           actor: actor,
           load: [:source_discovery_record, program: [:discovery_program]]
         ) do
      {:ok, finding} ->
        map
        |> maybe_put("discovery_record_id", finding.source_discovery_record_id)
        |> maybe_put("discovery_program_id", discovery_program_id(finding))

      _ ->
        map
    end
  end

  defp discovery_program_id(%{program: %{discovery_program_id: program_id}}),
    do: program_id

  defp discovery_program_id(_finding), do: nil

  defp redirect_path_for_observation(observation) do
    case Acquisition.get_finding_by_source_discovery_record(observation.discovery_record_id) do
      {:ok, finding} -> ~p"/acquisition/findings/#{finding.id}"
      _ -> ~p"/acquisition/findings?family=discovery"
    end
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp split_lines(value) do
    value
    |> String.split("\n", trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  defp back_path(nil), do: ~p"/acquisition/findings?family=discovery"
  defp back_path(%{id: finding_id}), do: ~p"/acquisition/findings/#{finding_id}"

  defp format_context_atom(nil), do: "-"

  defp format_context_atom(value) do
    value
    |> to_string()
    |> String.replace("_", " ")
    |> String.capitalize()
  end
end
