defmodule GnomeGardenWeb.Operations.AutomationRuleLive.Index do
  use GnomeGardenWeb, :live_view

  alias GnomeGarden.Automation

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Automation")
     |> assign_rules()}
  end

  @impl true
  def handle_event("install_starters", _params, socket) do
    case Automation.ensure_starter_automation_rules(
           %{default_owner_email: to_string(socket.assigns.current_user.email)},
           actor: socket.assigns.current_user
         ) do
      {:ok, results} ->
        created = Enum.count(results, fn {_name, outcome} -> outcome == :created end)

        {:noreply,
         socket
         |> put_flash(:info, "Starter rules installed as drafts (#{created} new)")
         |> assign_rules()}

      {:error, error} ->
        {:noreply, put_flash(socket, :error, "Could not install starters: #{inspect(error)}")}
    end
  end

  @impl true
  def handle_event(action, %{"id" => id}, socket)
      when action in ["publish", "disable", "enable", "delete_draft", "clone"] do
    with {:ok, rule} <- Automation.get_automation_rule(id, actor: socket.assigns.current_user),
         {:ok, message} <- perform(action, rule, socket.assigns.current_user) do
      {:noreply, socket |> put_flash(:info, message) |> assign_rules()}
    else
      {:error, error} ->
        {:noreply, put_flash(socket, :error, error_message(error)) |> assign_rules()}
    end
  end

  defp perform("publish", rule, actor) do
    with {:ok, _rule} <- Automation.publish_automation_rule(rule, actor: actor),
         do: {:ok, "Rule published — it is now live"}
  end

  defp perform("disable", rule, actor) do
    with {:ok, _rule} <- Automation.disable_automation_rule(rule, actor: actor),
         do: {:ok, "Rule disabled"}
  end

  defp perform("enable", rule, actor) do
    with {:ok, _rule} <- Automation.enable_automation_rule(rule, actor: actor),
         do: {:ok, "Rule re-enabled"}
  end

  defp perform("delete_draft", rule, actor) do
    with :ok <- Automation.delete_draft_automation_rule(rule, actor: actor),
         do: {:ok, "Draft deleted"}
  end

  defp perform("clone", rule, actor) do
    with {:ok, clone} <- Automation.clone_automation_rule(%{rule_id: rule.id}, actor: actor),
         do: {:ok, "Cloned as draft: #{clone.name}"}
  end

  defp error_message(error) when is_exception(error), do: Exception.message(error)
  defp error_message(error), do: inspect(error)

  @impl true
  def render(assigns) do
    ~H"""
    <.page class="pb-8">
      <.page_header eyebrow="Operations">
        Automation
        <:subtitle>
          Trigger + criteria + actions. Rules install and edit as drafts; nothing
          fires until you publish. Published rules are immutable — clone to change.
        </:subtitle>
        <:actions>
          <.button phx-click="install_starters" id="install-starter-rules">
            Install starters
          </.button>
          <.button navigate={~p"/operations/automation/new"} variant="primary">
            New Rule
          </.button>
        </:actions>
      </.page_header>

      <.section
        :for={{title, rules, empty} <- sections(@rules)}
        title={title}
        body_class="p-0"
      >
        <div :if={rules == []} class="p-4">
          <.empty_state icon="hero-bolt" title={empty} description="" />
        </div>
        <div :if={rules != []} class="divide-y divide-zinc-200 dark:divide-white/10">
          <div :for={rule <- rules} class="flex items-center justify-between gap-3 px-4 py-3">
            <.link navigate={~p"/operations/automation/#{rule}"} class="min-w-0 flex-1">
              <p class="font-medium text-base-content">{rule.name}</p>
              <p class="text-xs text-base-content/50">
                on {rule.trigger_resource}.{rule.trigger_action} · {length(rule.criteria)} criteria · {length(
                  rule.actions
                )} actions
              </p>
            </.link>
            <div class="flex shrink-0 items-center gap-2">
              <.button
                :if={rule.status == :draft}
                phx-click="publish"
                phx-value-id={rule.id}
                variant="primary"
              >
                Publish
              </.button>
              <.button :if={rule.status == :draft} phx-click="delete_draft" phx-value-id={rule.id}>
                Delete
              </.button>
              <.button :if={rule.status == :published} phx-click="disable" phx-value-id={rule.id}>
                Disable
              </.button>
              <.button :if={rule.status == :disabled} phx-click="enable" phx-value-id={rule.id}>
                Enable
              </.button>
              <.button
                :if={rule.status in [:published, :disabled]}
                phx-click="clone"
                phx-value-id={rule.id}
              >
                Clone
              </.button>
            </div>
          </div>
        </div>
      </.section>
    </.page>
    """
  end

  defp sections(rules) do
    grouped = Enum.group_by(rules, & &1.status)

    [
      {"Published", Map.get(grouped, :published, []), "No live rules yet"},
      {"Drafts", Map.get(grouped, :draft, []), "No drafts"},
      {"Disabled", Map.get(grouped, :disabled, []), "Nothing disabled"}
    ]
  end

  defp assign_rules(socket) do
    case Automation.list_automation_rules(
           actor: socket.assigns.current_user,
           query: [sort: [name: :asc]]
         ) do
      {:ok, rules} -> assign(socket, :rules, rules)
      {:error, error} -> raise "failed to load automation rules: #{inspect(error)}"
    end
  end
end
