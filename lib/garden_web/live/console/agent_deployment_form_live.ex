defmodule GnomeGardenWeb.Console.AgentDeploymentFormLive do
  use GnomeGardenWeb, :live_view

  alias GnomeGarden.Agents
  alias GnomeGarden.Agents.AgentDeployment
  alias GnomeGarden.Agents.TemplateCatalog

  @impl true
  def mount(params, _session, socket) do
    template_options = TemplateCatalog.template_options()

    deployment =
      if id = params["id"] do
        Agents.get_agent_deployment!(id, load: [:agent])
      else
        nil
      end

    config_json = pretty_json((deployment && deployment.config) || %{})
    source_scope_json = pretty_json((deployment && deployment.source_scope) || %{})

    {:ok,
     socket
     |> assign(:deployment, deployment)
     |> assign(:template_options, template_options)
     |> assign(:config_json, config_json)
     |> assign(:source_scope_json, source_scope_json)
     |> assign(:page_title, if(deployment, do: "Edit #{deployment.name}", else: "New Deployment"))
     |> assign_form()}
  end

  defp assign_form(%{assigns: %{deployment: deployment, current_user: actor}} = socket) do
    form =
      if deployment do
        AshPhoenix.Form.for_update(
          deployment,
          :update,
          actor: actor,
          domain: Agents
        )
      else
        AshPhoenix.Form.for_create(
          AgentDeployment,
          :create,
          actor: actor,
          domain: Agents,
          params: %{
            "visibility" => "private",
            "enabled" => "true"
          }
        )
      end

    assign(socket, form: to_form(form))
  end

  @impl true
  def handle_event("validate", params, socket) do
    form_params = Map.get(params, "form", %{})
    form = AshPhoenix.Form.validate(socket.assigns.form, form_params)

    {:noreply,
     socket
     |> assign(:form, to_form(form))
     |> assign(:config_json, Map.get(params, "config_json", socket.assigns.config_json))
     |> assign(
       :source_scope_json,
       Map.get(params, "source_scope_json", socket.assigns.source_scope_json)
     )}
  end

  @impl true
  def handle_event("save", params, socket) do
    form_params = Map.get(params, "form", %{})
    config_json = Map.get(params, "config_json", socket.assigns.config_json)
    source_scope_json = Map.get(params, "source_scope_json", socket.assigns.source_scope_json)

    with {:ok, config} <- decode_json(config_json, "Config"),
         {:ok, source_scope} <- decode_json(source_scope_json, "Source scope") do
      merged_params =
        Map.merge(form_params, %{
          "config" => config,
          "source_scope" => source_scope
        })

      case AshPhoenix.Form.submit(socket.assigns.form, params: merged_params) do
        {:ok, _deployment} ->
          {:noreply,
           socket
           |> put_flash(
             :info,
             "Deployment #{if(socket.assigns.deployment, do: "updated", else: "created")}."
           )
           |> push_navigate(to: ~p"/console/agents")}

        {:error, form} ->
          {:noreply,
           socket
           |> assign(:form, to_form(form))
           |> assign(:config_json, config_json)
           |> assign(:source_scope_json, source_scope_json)}
      end
    else
      {:error, message} ->
        {:noreply,
         socket
         |> assign(:config_json, config_json)
         |> assign(:source_scope_json, source_scope_json)
         |> put_flash(:error, message)}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.page max_width="max-w-5xl" class="pb-8">
      <.page_header eyebrow="Console">
        {@page_title}
        <:subtitle>
          Configure a deployment without relying on Ash Admin. Templates are synced automatically from the in-memory registry.
        </:subtitle>
        <:actions>
          <.button navigate={~p"/console/agents"}>
            Back to Agents Console
          </.button>
        </:actions>
      </.page_header>

      <.form
        for={@form}
        id="agent-deployment-form"
        phx-change="validate"
        phx-submit="save"
        class="space-y-6"
      >
        <.form_section
          title="Deployment"
          description="Identity, template binding, and operator-facing metadata."
        >
          <div class="grid grid-cols-1 gap-6 sm:grid-cols-6">
            <div class="sm:col-span-3">
              <.input field={@form[:name]} label="Deployment Name" required />
            </div>

            <div class="sm:col-span-3">
              <.input
                field={@form[:agent_id]}
                type="select"
                label="Template"
                prompt="Select template..."
                options={@template_options}
              />
            </div>

            <div class="sm:col-span-3">
              <.input
                field={@form[:visibility]}
                type="select"
                label="Visibility"
                options={[
                  {"Private", :private},
                  {"Shared", :shared},
                  {"System", :system}
                ]}
              />
            </div>

            <div class="sm:col-span-3 pt-8">
              <.input field={@form[:enabled]} type="checkbox" label="Enabled" />
            </div>

            <div class="sm:col-span-3">
              <.input field={@form[:schedule]} label="Schedule" placeholder="0 */6 * * *" />
            </div>

            <div class="sm:col-span-3">
              <.input
                field={@form[:memory_namespace]}
                label="Memory Namespace"
                placeholder="agents.bid_scanner.shared"
              />
            </div>

            <div class="col-span-full">
              <.input field={@form[:description]} type="textarea" label="Description" />
            </div>
          </div>
        </.form_section>

        <.form_section
          title="Execution Scope"
          description="Provide JSON payloads for runtime config and source scope. Invalid JSON blocks save."
        >
          <div class="grid grid-cols-1 gap-6 sm:grid-cols-2">
            <div>
              <label
                for="config_json"
                class="block text-sm/6 font-medium text-gray-900 dark:text-white"
              >
                Config JSON
              </label>
              <textarea
                id="config_json"
                name="config_json"
                rows="16"
                class="mt-2 block w-full rounded-md bg-white px-3 py-2 font-mono text-sm text-gray-900 outline-1 -outline-offset-1 outline-gray-300 placeholder:text-gray-400 focus:outline-2 focus:-outline-offset-2 focus:outline-emerald-600 dark:bg-white/5 dark:text-white dark:outline-white/10 dark:placeholder:text-gray-500 dark:focus:outline-emerald-500"
              ><%= @config_json %></textarea>
            </div>

            <div>
              <label
                for="source_scope_json"
                class="block text-sm/6 font-medium text-gray-900 dark:text-white"
              >
                Source Scope JSON
              </label>
              <textarea
                id="source_scope_json"
                name="source_scope_json"
                rows="16"
                class="mt-2 block w-full rounded-md bg-white px-3 py-2 font-mono text-sm text-gray-900 outline-1 -outline-offset-1 outline-gray-300 placeholder:text-gray-400 focus:outline-2 focus:-outline-offset-2 focus:outline-emerald-600 dark:bg-white/5 dark:text-white dark:outline-white/10 dark:placeholder:text-gray-500 dark:focus:outline-emerald-500"
              ><%= @source_scope_json %></textarea>
            </div>
          </div>
        </.form_section>

        <.section body_class="px-6 py-5 sm:px-7">
          <.form_actions
            cancel_path={~p"/console/agents"}
            submit_label="Save Deployment"
          />
        </.section>
      </.form>
    </.page>
    """
  end

  defp decode_json("", _label), do: {:ok, %{}}
  defp decode_json(nil, _label), do: {:ok, %{}}

  defp decode_json(json, label) when is_binary(json) do
    case Jason.decode(json) do
      {:ok, value} when is_map(value) -> {:ok, value}
      {:ok, _value} -> {:error, "#{label} must be a JSON object."}
      {:error, error} -> {:error, "#{label} JSON is invalid: #{Exception.message(error)}"}
    end
  end

  defp pretty_json(value), do: Jason.encode!(value, pretty: true)
end
