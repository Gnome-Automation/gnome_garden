defmodule GnomeGardenWeb.Operations.AutomationRuleLive.Form do
  use GnomeGardenWeb, :live_view

  alias GnomeGarden.Automation

  @input_class "block w-full rounded-md bg-white px-3 py-1.5 text-base text-gray-900 outline-1 -outline-offset-1 outline-gray-300 placeholder:text-gray-400 focus:outline-2 focus:-outline-offset-2 focus:outline-emerald-600 sm:text-sm/6 dark:bg-white/5 dark:text-white dark:outline-white/10 dark:placeholder:text-gray-500 dark:focus:outline-emerald-500"
  @label_class "block text-sm/6 font-medium text-gray-900 dark:text-white"

  @trigger_options [
    {"Bid scored (tier changed)", "bid|scored"},
    {"Bid deadline approaching", "bid|due_soon"},
    {"Pursuit qualified", "pursuit|qualified"},
    {"Pursuit proposed", "pursuit|proposed"},
    {"Source credential failed", "source_credential|failed"},
    {"Task overdue", "task|overdue"}
  ]

  @impl true
  def mount(params, _session, socket) do
    rule = if id = params["id"], do: load_rule!(id, socket.assigns.current_user)

    if rule && rule.status != :draft do
      {:ok,
       socket
       |> put_flash(:error, "Published rules are immutable — clone to edit.")
       |> push_navigate(to: ~p"/operations/automation/#{rule}")}
    else
      {:ok,
       socket
       |> assign(:rule, rule)
       |> assign(:page_title, if(rule, do: "Edit Rule", else: "New Rule"))
       |> assign(:error, nil)}
    end
  end

  @impl true
  def handle_event("save", params, socket) do
    with {:ok, attrs} <- build_attrs(params),
         {:ok, rule} <- save(socket, attrs) do
      {:noreply,
       socket
       |> put_flash(:info, "Rule saved as draft")
       |> push_navigate(to: ~p"/operations/automation/#{rule}")}
    else
      {:error, message} when is_binary(message) ->
        {:noreply, assign(socket, :error, message)}

      {:error, error} ->
        {:noreply, assign(socket, :error, Exception.message(error))}
    end
  end

  defp save(%{assigns: %{rule: nil, current_user: actor}}, attrs),
    do: Automation.create_automation_rule(attrs, actor: actor)

  defp save(%{assigns: %{rule: rule, current_user: actor}}, attrs),
    do: Automation.update_automation_rule(rule, attrs, actor: actor)

  defp build_attrs(params) do
    with {:ok, criteria} <- parse_json_list(params["criteria"], "criteria"),
         {:ok, actions} <- parse_json_list(params["actions"], "actions"),
         {:ok, {resource, action}} <- parse_trigger(params["trigger"]) do
      {:ok,
       %{
         name: params["name"],
         description: params["description"],
         trigger_resource: resource,
         trigger_action: action,
         criteria: criteria,
         actions: actions
       }}
    end
  end

  defp parse_trigger(trigger) when is_binary(trigger) do
    case String.split(trigger, "|") do
      [resource, action] -> {:ok, {resource, action}}
      _other -> {:error, "pick a trigger"}
    end
  end

  defp parse_trigger(_trigger), do: {:error, "pick a trigger"}

  defp parse_json_list(nil, _label), do: {:ok, []}
  defp parse_json_list("", _label), do: {:ok, []}

  defp parse_json_list(json, label) do
    case Jason.decode(json) do
      {:ok, list} when is_list(list) -> {:ok, list}
      {:ok, _other} -> {:error, "#{label} must be a JSON list"}
      {:error, _error} -> {:error, "#{label} is not valid JSON"}
    end
  end

  @impl true
  def render(assigns) do
    assigns =
      assigns
      |> assign(:input_class, @input_class)
      |> assign(:label_class, @label_class)
      |> assign(:trigger_options, @trigger_options)

    ~H"""
    <.page max_width="max-w-3xl" class="pb-8">
      <.page_header eyebrow="Automation">
        {@page_title}
        <:subtitle>
          Rules save as drafts and only fire after you publish them.
        </:subtitle>
        <:actions>
          <.button navigate={~p"/operations/automation"}>
            Back
          </.button>
        </:actions>
      </.page_header>

      <form id="automation-rule-form" phx-submit="save" class="space-y-6">
        <.form_section title="Rule">
          <div class="grid grid-cols-1 gap-6">
            <div>
              <label for="rule-name" class={@label_class}>Name</label>
              <input
                id="rule-name"
                name="name"
                required
                value={@rule && @rule.name}
                class={["mt-2", @input_class]}
              />
            </div>
            <div>
              <label for="rule-description" class={@label_class}>Description</label>
              <textarea id="rule-description" name="description" rows="2" class={["mt-2", @input_class]}>{@rule && @rule.description}</textarea>
            </div>
            <div>
              <label for="rule-trigger" class={@label_class}>Trigger</label>
              <select id="rule-trigger" name="trigger" class={["mt-2", @input_class]}>
                {Phoenix.HTML.Form.options_for_select(
                  @trigger_options,
                  @rule && "#{@rule.trigger_resource}|#{@rule.trigger_action}"
                )}
              </select>
            </div>
          </div>
        </.form_section>

        <.form_section
          title="Criteria"
          description={~s(JSON list of predicates, e.g. [{"field": "score_tier", "op": "eq", "value": "hot"}]. Ops: eq, neq, gt, gte, lt, lte, contains, in, is_nil, not_nil. Empty list means always fire.)}
        >
          <textarea id="rule-criteria" name="criteria" rows="4" class={["font-mono", @input_class]}>{encode(@rule && @rule.criteria)}</textarea>
        </.form_section>

        <.form_section
          title="Actions"
          description={~s(JSON list of typed actions: {"type": "create_task", "title": "...", "task_type": "review", "priority": "high", "due_offset_days": 2} or {"type": "apply_playbook", "playbook_name": "New bid review"}.)}
        >
          <textarea id="rule-actions" name="actions" rows="6" class={["font-mono", @input_class]}>{encode(@rule && @rule.actions)}</textarea>
        </.form_section>

        <p :if={@error} class="text-sm text-error">{@error}</p>

        <.section body_class="px-6 py-5 sm:px-7">
          <.form_actions
            cancel_path={~p"/operations/automation"}
            submit_label={if @rule, do: "Save Draft", else: "Create Draft"}
          />
        </.section>
      </form>
    </.page>
    """
  end

  defp encode(nil), do: ""
  defp encode([]), do: ""
  defp encode(list), do: Jason.encode!(list, pretty: true)

  defp load_rule!(id, actor) do
    case Automation.get_automation_rule(id, actor: actor) do
      {:ok, rule} -> rule
      {:error, error} -> raise "failed to load automation rule #{id}: #{inspect(error)}"
    end
  end
end
