defmodule GnomeGardenWeb.Company.QualificationLive.Form do
  use GnomeGardenWeb, :live_view

  alias GnomeGarden.Company
  alias GnomeGarden.Operations

  @impl true
  def mount(params, _session, socket) do
    qualification = if id = params["id"], do: load_qualification!(id, socket.assigns.current_user)

    {:ok,
     socket
     |> assign(:qualification, qualification)
     |> assign(
       :page_title,
       if(qualification, do: "Edit Qualification", else: "New Qualification")
     )
     |> assign(:team_members, load_team_members(socket.assigns.current_user))
     |> assign(:details_text, initial_details_text(qualification))
     |> assign(:details_error, nil)
     |> assign_form()}
  end

  # Details JSON is kept as raw text while typing (validating a half-typed
  # `{` would otherwise clobber the textarea) and only parsed at save.
  @impl true
  def handle_event("validate", %{"form" => params}, socket) do
    form =
      AshPhoenix.Form.validate(
        socket.assigns.form,
        params |> Map.delete("details") |> normalize(socket)
      )

    {:noreply,
     socket
     |> assign(:details_text, params["details"] || "")
     |> assign(form: to_form(form))}
  end

  @impl true
  def handle_event("save", %{"form" => params}, socket) do
    with {:ok, details} <- parse_details(params["details"]),
         {:ok, _qualification} <-
           AshPhoenix.Form.submit(socket.assigns.form,
             params: params |> Map.put("details", details) |> normalize(socket)
           ) do
      {:noreply,
       socket
       |> put_flash(:info, "Qualification saved")
       |> push_navigate(to: ~p"/company/qualifications")}
    else
      {:invalid_json, message} ->
        {:noreply,
         socket
         |> assign(:details_text, params["details"] || "")
         |> assign(:details_error, message)}

      {:error, form} ->
        {:noreply,
         socket
         |> assign(:details_text, params["details"] || "")
         |> assign(form: to_form(form))}
    end
  end

  # unlocks arrives as a comma-separated string.
  defp normalize(params, socket) do
    params
    |> Map.update("unlocks", [], &split_list/1)
    |> maybe_put_profile(socket)
  end

  defp maybe_put_profile(params, %{assigns: %{qualification: nil}} = socket),
    do: Map.put(params, "company_profile_id", primary_profile_id(socket))

  defp maybe_put_profile(params, _socket), do: params

  defp split_list(value) when is_binary(value) do
    value |> String.split(",") |> Enum.map(&String.trim/1) |> Enum.reject(&(&1 == ""))
  end

  defp split_list(value), do: value

  defp parse_details(value) when is_binary(value) and value != "" do
    case Jason.decode(value) do
      {:ok, %{} = details} -> {:ok, details}
      {:ok, _not_object} -> {:invalid_json, "details must be a JSON object"}
      {:error, _error} -> {:invalid_json, "details is not valid JSON"}
    end
  end

  defp parse_details(_blank), do: {:ok, %{}}

  defp initial_details_text(nil), do: ""
  defp initial_details_text(%{details: details}) when map_size(details) == 0, do: ""
  defp initial_details_text(%{details: details}), do: Jason.encode!(details, pretty: true)

  @impl true
  def render(assigns) do
    ~H"""
    <.page max_width="max-w-3xl" class="pb-8">
      <.page_header eyebrow="Company">
        {@page_title}
        <:actions>
          <.button navigate={~p"/company/qualifications"}>
            Back
          </.button>
        </:actions>
      </.page_header>

      <.form
        for={@form}
        id="qualification-form"
        phx-change="validate"
        phx-submit="save"
        class="space-y-6"
      >
        <.form_section title="Capability">
          <div class="grid grid-cols-1 gap-6 sm:grid-cols-6">
            <div class="sm:col-span-2">
              <.input field={@form[:kind]} type="select" label="Kind" options={kind_options()} />
            </div>
            <div class="sm:col-span-4">
              <.input field={@form[:name]} label="Name" required />
            </div>
            <div class="sm:col-span-3">
              <.input field={@form[:issuing_authority]} label="Issuing authority" required />
            </div>
            <div class="sm:col-span-3">
              <.input field={@form[:identifier]} label="Identifier / number" />
            </div>
            <div class="sm:col-span-2">
              <.input field={@form[:effective_on]} type="date" label="Effective" />
            </div>
            <div class="sm:col-span-2">
              <.input field={@form[:expires_on]} type="date" label="Expires" />
            </div>
            <div class="sm:col-span-2">
              <.input
                field={@form[:renewal_lead_days]}
                type="number"
                label="Renewal lead (days)"
                min="1"
              />
            </div>
            <div class="sm:col-span-3">
              <.input field={@form[:verification_url]} label="Verification URL" />
            </div>
            <div class="sm:col-span-3">
              <.input
                field={@form[:owner_team_member_id]}
                type="select"
                label="Owner"
                prompt="Unassigned"
                options={Enum.map(@team_members, &{&1.display_name, &1.id})}
              />
            </div>
            <div class="col-span-full">
              <.input
                field={@form[:unlocks]}
                label="Unlocks (comma-separated markets/service lines)"
                value={unlocks_value(@form)}
              />
            </div>
          </div>
        </.form_section>

        <.form_section
          title="Kind-Specific Details"
          description="JSON object validated per kind — e.g. bonding requires single_project_limit and aggregate_limit."
        >
          <textarea
            id="qualification-details"
            name="form[details]"
            rows="4"
            class="block w-full rounded-md bg-white px-3 py-1.5 font-mono text-sm text-gray-900 outline-1 -outline-offset-1 outline-gray-300 focus:outline-2 focus:-outline-offset-2 focus:outline-emerald-600 dark:bg-white/5 dark:text-white dark:outline-white/10"
          >{@details_text}</textarea>
          <p :if={@details_error} class="mt-2 text-sm text-error">{@details_error}</p>
        </.form_section>

        <.section body_class="px-6 py-5 sm:px-7">
          <.form_actions
            cancel_path={~p"/company/qualifications"}
            submit_label={if @qualification, do: "Save Changes", else: "Create Qualification"}
          />
        </.section>
      </.form>
    </.page>
    """
  end

  defp unlocks_value(form) do
    case AshPhoenix.Form.value(form.source, :unlocks) do
      list when is_list(list) -> Enum.join(list, ", ")
      _other -> ""
    end
  end

  defp assign_form(%{assigns: %{qualification: qualification, current_user: actor}} = socket) do
    form =
      if qualification do
        AshPhoenix.Form.for_update(qualification, :update, actor: actor, domain: Company)
      else
        AshPhoenix.Form.for_create(Company.Qualification, :create, actor: actor, domain: Company)
      end

    assign(socket, :form, to_form(form))
  end

  defp kind_options do
    [
      {"Registration", :registration},
      {"License", :license},
      {"Certification", :certification},
      {"Insurance", :insurance},
      {"Bonding", :bonding},
      {"Partner standing", :partner_standing}
    ]
  end

  defp primary_profile_id(socket) do
    case Company.get_primary_company_profile(actor: socket.assigns.current_user) do
      {:ok, profile} -> profile.id
      {:error, error} -> raise "no primary company profile: #{inspect(error)}"
    end
  end

  defp load_team_members(actor) do
    case Operations.list_active_team_members(actor: actor) do
      {:ok, members} -> members
      {:error, _error} -> []
    end
  end

  defp load_qualification!(id, actor) do
    case Company.get_company_qualification(id, actor: actor) do
      {:ok, qualification} -> qualification
      {:error, error} -> raise "failed to load qualification #{id}: #{inspect(error)}"
    end
  end
end
