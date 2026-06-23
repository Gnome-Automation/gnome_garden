defmodule GnomeGardenWeb.Acquisition.SourceLive.Form do
  use GnomeGardenWeb, :live_view

  alias GnomeGarden.Procurement
  alias GnomeGarden.Procurement.ProcurementSource

  import GnomeGardenWeb.Execution.Helpers, only: [format_atom: 1]

  @impl true
  def mount(params, _session, socket) do
    source = if id = params["id"], do: load_source!(id, socket.assigns.current_user)

    {:ok,
     socket
     |> assign(:source, source)
     |> assign(:page_title, if(source, do: "Edit Source", else: "Add Source"))
     |> assign_form()}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.page max_width="max-w-5xl" class="pb-8">
      <.page_header eyebrow="Acquisition">
        {@page_title}
        <:subtitle>
          Add procurement portals and discovery sources that can feed the acquisition queue.
        </:subtitle>
        <:actions>
          <.button navigate={~p"/acquisition/sources"}>
            Back to sources
          </.button>
        </:actions>
      </.page_header>

      <.form
        for={@form}
        id="source-form"
        phx-change="validate"
        phx-submit="save"
        class="space-y-6"
      >
        <.form_section title="Source Details">
          <div class="grid grid-cols-1 gap-6 sm:grid-cols-6">
            <div class="sm:col-span-4">
              <.input field={@form[:name]} label="Name" required />
            </div>
            <div class="sm:col-span-2">
              <.input
                field={@form[:status]}
                type="select"
                label="Status"
                options={status_options()}
              />
            </div>
            <div class="col-span-full">
              <.input field={@form[:url]} label="URL" required />
            </div>
            <div class="sm:col-span-2">
              <.input
                field={@form[:source_type]}
                type="select"
                label="Source Type"
                options={source_type_options()}
              />
            </div>
            <div class="sm:col-span-2">
              <.input field={@form[:portal_id]} label="Portal ID" />
            </div>
            <div class="sm:col-span-2">
              <.input
                field={@form[:region]}
                type="select"
                label="Region"
                options={region_options()}
              />
            </div>
            <div class="sm:col-span-2">
              <.input
                field={@form[:priority]}
                type="select"
                label="Priority"
                options={priority_options()}
              />
            </div>
            <div class="sm:col-span-2">
              <.input
                field={@form[:scan_frequency_hours]}
                type="number"
                label="Scan Every Hours"
              />
            </div>
            <div class="sm:col-span-2">
              <.input field={@form[:scrape_selector]} label="Listing Selector" />
            </div>
            <div class="sm:col-span-2">
              <.input field={@form[:enabled]} type="checkbox" label="Enabled" />
            </div>
            <div class="sm:col-span-2">
              <.input field={@form[:requires_login]} type="checkbox" label="Requires Login" />
            </div>
            <div class="sm:col-span-2">
              <.input field={@form[:api_available]} type="checkbox" label="API Available" />
            </div>
            <div class="col-span-full">
              <.input field={@form[:notes]} type="textarea" label="Notes" />
            </div>
          </div>
        </.form_section>

        <.section body_class="px-6 py-5 sm:px-7">
          <.form_actions
            cancel_path={~p"/acquisition/sources"}
            submit_label={if @source, do: "Update Source", else: "Create Source"}
          />
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

  @impl true
  def handle_event("save", %{"form" => params}, socket) do
    case AshPhoenix.Form.submit(socket.assigns.form.source, params: params) do
      {:ok, _source} ->
        {:noreply,
         socket
         |> put_flash(
           :info,
           "Source #{if socket.assigns.source, do: "updated", else: "created"}."
         )
         |> push_navigate(to: ~p"/acquisition/sources")}

      {:error, form} ->
        {:noreply, assign(socket, form: to_form(form))}
    end
  end

  defp assign_form(%{assigns: %{source: source, current_user: actor}} = socket) do
    form =
      if source do
        AshPhoenix.Form.for_update(source, :update, actor: actor, domain: Procurement)
      else
        AshPhoenix.Form.for_create(ProcurementSource, :create,
          actor: actor,
          domain: Procurement,
          params: default_params()
        )
      end

    assign(socket, :form, to_form(form))
  end

  defp load_source!(id, actor) do
    case Procurement.get_procurement_source(id, actor: actor) do
      {:ok, source} -> source
      {:error, error} -> raise "failed to load procurement source #{id}: #{inspect(error)}"
    end
  end

  defp default_params do
    %{
      "source_type" => default_source_type(),
      "region" => default_attribute_value(:region),
      "priority" => default_attribute_value(:priority),
      "scan_frequency_hours" => default_attribute_value(:scan_frequency_hours),
      "enabled" => default_attribute_value(:enabled),
      "status" => default_attribute_value(:status)
    }
  end

  defp source_type_options, do: enum_options(:source_type)
  defp region_options, do: enum_options(:region)
  defp priority_options, do: enum_options(:priority)
  defp status_options, do: enum_options(:status)

  defp enum_options(attribute_name) do
    ProcurementSource
    |> Ash.Resource.Info.attribute(attribute_name)
    |> Map.fetch!(:constraints)
    |> Keyword.fetch!(:one_of)
    |> Enum.map(&{format_atom(&1), &1})
  end

  defp default_source_type do
    values =
      ProcurementSource
      |> Ash.Resource.Info.attribute(:source_type)
      |> Map.fetch!(:constraints)
      |> Keyword.fetch!(:one_of)

    cond do
      :custom in values -> :custom
      values != [] -> List.first(values)
      true -> nil
    end
  end

  defp default_attribute_value(attribute_name) do
    ProcurementSource
    |> Ash.Resource.Info.attribute(attribute_name)
    |> Map.get(:default)
  end
end
