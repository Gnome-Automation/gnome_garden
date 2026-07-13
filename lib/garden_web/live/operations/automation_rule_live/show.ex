defmodule GnomeGardenWeb.Operations.AutomationRuleLive.Show do
  use GnomeGardenWeb, :live_view

  import GnomeGardenWeb.Operations.Helpers, only: [format_atom: 1, format_datetime: 1]

  alias GnomeGarden.Automation

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    rule = load_rule!(id, socket.assigns.current_user)

    if connected?(socket) do
      GnomeGardenWeb.Endpoint.subscribe("automation_run:rule:#{rule.id}")
    end

    {:ok,
     socket
     |> assign(:page_title, rule.name)
     |> assign(:rule, rule)
     |> assign(:dry_run, nil)
     |> assign_runs()}
  end

  @impl true
  def handle_event("dry_run", _params, socket) do
    case Automation.dry_run_automation_rule(socket.assigns.rule.id,
           actor: socket.assigns.current_user
         ) do
      {:ok, result} ->
        {:noreply, assign(socket, :dry_run, result)}

      {:error, error} ->
        {:noreply, put_flash(socket, :error, "Dry run failed: #{inspect(error)}")}
    end
  end

  @impl true
  def handle_event(action, _params, socket)
      when action in ["publish", "disable", "enable"] do
    rule = socket.assigns.rule

    result =
      case action do
        "publish" -> Automation.publish_automation_rule(rule, actor: socket.assigns.current_user)
        "disable" -> Automation.disable_automation_rule(rule, actor: socket.assigns.current_user)
        "enable" -> Automation.enable_automation_rule(rule, actor: socket.assigns.current_user)
      end

    case result do
      {:ok, updated} ->
        {:noreply,
         socket
         |> put_flash(:info, "Rule #{action}d")
         |> assign(:rule, updated)}

      {:error, error} ->
        {:noreply, put_flash(socket, :error, Exception.message(error))}
    end
  end

  @impl true
  def handle_info(%{topic: "automation_run:rule:" <> _rule_id}, socket) do
    {:noreply, assign_runs(socket)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.page max_width="max-w-4xl" class="pb-8">
      <.page_header eyebrow="Automation Rule">
        {@rule.name}
        <:subtitle>
          <span class="inline-flex items-center gap-2">
            <.status_badge status={status_variant(@rule.status)}>
              {format_atom(@rule.status)}
            </.status_badge>
            <span>on {@rule.trigger_resource}.{@rule.trigger_action}</span>
          </span>
        </:subtitle>
        <:actions>
          <.button navigate={~p"/operations/automation"}>
            Back
          </.button>
          <.button :if={@rule.status == :draft} navigate={~p"/operations/automation/#{@rule}/edit"}>
            Edit Draft
          </.button>
          <.button id="rule-dry-run" phx-click="dry_run">
            Dry Run
          </.button>
          <.button :if={@rule.status == :draft} phx-click="publish" variant="primary">
            Publish
          </.button>
          <.button :if={@rule.status == :published} phx-click="disable">
            Disable
          </.button>
          <.button :if={@rule.status == :disabled} phx-click="enable" variant="primary">
            Enable
          </.button>
        </:actions>
      </.page_header>

      <.section
        :if={@dry_run}
        title="Dry Run"
        description="Evaluated against recent matching events without executing anything."
      >
        <p class="text-sm text-base-content/80" id="dry-run-result">
          {@dry_run["would_fire"]} of {@dry_run["tested_events"]} recent {@rule.trigger_resource}.{@rule.trigger_action} events would fire this rule.
        </p>
      </.section>

      <div class="grid gap-6 lg:grid-cols-2">
        <.section title="Criteria" description="All must match (AND). Empty means always fire.">
          <pre
            class="overflow-x-auto rounded-md bg-zinc-50 p-3 text-xs dark:bg-white/[0.04]"
            phx-no-curly-interpolation
          ><%= pretty(@rule.criteria) %></pre>
        </.section>

        <.section title="Actions" description="Executed in order through Ash interfaces.">
          <pre
            class="overflow-x-auto rounded-md bg-zinc-50 p-3 text-xs dark:bg-white/[0.04]"
            phx-no-curly-interpolation
          ><%= pretty(@rule.actions) %></pre>
        </.section>
      </div>

      <.section :if={@rule.cloned_from_rule_id} title="Lineage">
        <.link
          navigate={~p"/operations/automation/#{@rule.cloned_from_rule_id}"}
          class="text-sm text-emerald-600 hover:text-primary"
        >
          Cloned from an earlier version — view ancestor
        </.link>
      </.section>

      <.section title="Run History" body_class="p-0">
        <div :if={@runs == []} class="p-4">
          <.empty_state
            icon="hero-bolt"
            title="No runs yet"
            description="Every firing of this rule will be recorded here with its results."
          />
        </div>
        <div :if={@runs != []} class="divide-y divide-zinc-200 dark:divide-white/10">
          <div :for={run <- @runs} class="px-4 py-3">
            <div class="flex items-center justify-between gap-3">
              <.status_badge status={run_variant(run.status)}>
                {format_atom(run.status)}
              </.status_badge>
              <span class="text-xs text-base-content/50">{format_datetime(run.inserted_at)}</span>
            </div>
            <p :for={result <- run.action_results} class="mt-1 text-xs text-base-content/60">
              {result["type"]}: {result["status"]}
              <span :if={result["detail"]}>— {result["detail"]}</span>
            </p>
            <p :if={run.error} class="mt-1 text-xs text-error">{run.error}</p>
          </div>
        </div>
      </.section>
    </.page>
    """
  end

  defp status_variant(:published), do: :success
  defp status_variant(:draft), do: :info
  defp status_variant(_status), do: :default

  defp run_variant(:succeeded), do: :success
  defp run_variant(:failed), do: :error
  defp run_variant(_status), do: :info

  defp pretty([]), do: "[]"
  defp pretty(list), do: Jason.encode!(list, pretty: true)

  defp assign_runs(socket) do
    case Automation.list_automation_runs_for_rule(socket.assigns.rule.id,
           actor: socket.assigns.current_user
         ) do
      {:ok, runs} -> assign(socket, :runs, runs)
      {:error, error} -> raise "failed to load automation runs: #{inspect(error)}"
    end
  end

  defp load_rule!(id, actor) do
    case Automation.get_automation_rule(id, actor: actor) do
      {:ok, rule} -> rule
      {:error, error} -> raise "failed to load automation rule #{id}: #{inspect(error)}"
    end
  end
end
