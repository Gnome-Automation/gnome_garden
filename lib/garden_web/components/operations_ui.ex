defmodule GnomeGardenWeb.Components.OperationsUI do
  @moduledoc """
  Shared operations UI components.
  """

  use GnomeGardenWeb, :html

  import GnomeGardenWeb.Operations.Helpers, only: [format_atom: 1, format_datetime: 1]

  attr :tasks, :list, default: []
  attr :title, :string, default: "Related Tasks"
  attr :description, :string, default: nil
  attr :empty_title, :string, default: "No related tasks"

  attr :empty_description, :string,
    default: "Task follow-up linked to this record will appear here."

  attr :new_task_path, :string, default: nil
  attr :new_task_label, :string, default: "New Task"

  def related_tasks_panel(assigns) do
    ~H"""
    <.section title={@title} description={@description} compact body_class="p-0">
      <:actions :if={@new_task_path}>
        <.button href={@new_task_path} variant="primary">
          {@new_task_label}
        </.button>
      </:actions>

      <div :if={@tasks == []} class="p-4">
        <.empty_state
          icon="hero-clipboard-document-list"
          title={@empty_title}
          description={@empty_description}
        />
      </div>

      <div :if={@tasks != []} class="divide-y divide-zinc-200 dark:divide-white/10">
        <.link
          :for={task <- @tasks}
          navigate={~p"/operations/tasks/#{task}"}
          class="block px-3 py-3 transition hover:bg-zinc-50 dark:hover:bg-white/[0.03] sm:px-4 lg:px-5"
        >
          <div class="flex flex-col gap-3 md:flex-row md:items-start md:justify-between">
            <div class="min-w-0 space-y-2">
              <div class="flex flex-wrap items-center gap-2">
                <.status_badge status={variant(task.status_variant)}>
                  {format_atom(task.status)}
                </.status_badge>
                <.status_badge status={variant(task.priority_variant)}>
                  {format_atom(task.priority)}
                </.status_badge>
                <.tag color={origin_color(task.origin_domain)}>
                  {format_atom(task.origin_domain)}
                </.tag>
                <span class="text-xs text-base-content/40">
                  {format_atom(task.task_type)}
                </span>
              </div>

              <div class="space-y-1">
                <p class="font-medium text-base-content">{task.title}</p>
                <p
                  :if={task.description}
                  class="line-clamp-2 text-sm leading-5 text-base-content/60"
                >
                  {task.description}
                </p>
              </div>
            </div>

            <div class="shrink-0 text-left text-xs text-base-content/50 md:text-right">
              <p>Due {format_datetime(task.due_at)}</p>
              <p>{context_line(task)}</p>
            </div>
          </div>
        </.link>
      </div>
    </.section>
    """
  end

  defp variant(value) when value in [:default, :success, :warning, :error, :info], do: value
  defp variant(_value), do: :default

  defp context_line(task) do
    case Map.get(task, :context_label) do
      label when is_binary(label) and label != "" -> label
      _not_loaded_or_nil -> task.origin_label || task.origin_resource || "Manual task"
    end
  end

  attr :runs, :list, default: []
  attr :playbooks, :list, default: []
  attr :description, :string, default: "Apply a playbook to create its task set for this record."

  def playbook_runs_panel(assigns) do
    ~H"""
    <.section title="Playbooks" description={@description} compact body_class="p-0">
      <:actions :if={@playbooks != []}>
        <form id="apply-playbook-form" phx-submit="apply_playbook" class="flex items-center gap-2">
          <select
            name="playbook_id"
            class="rounded-md bg-white px-3 py-1.5 text-sm text-gray-900 outline-1 -outline-offset-1 outline-gray-300 focus:outline-2 focus:-outline-offset-2 focus:outline-emerald-600 dark:bg-white/5 dark:text-white dark:outline-white/10"
          >
            {Phoenix.HTML.Form.options_for_select(
              Enum.map(@playbooks, &{&1.name, &1.id}),
              nil
            )}
          </select>
          <.button type="submit" variant="primary">Apply</.button>
        </form>
      </:actions>

      <div :if={@runs == []} class="p-4">
        <.empty_state
          icon="hero-book-open"
          title="No playbook runs"
          description="Applied playbooks and their progress will appear here."
        />
      </div>

      <div :if={@runs != []} class="divide-y divide-zinc-200 dark:divide-white/10">
        <div :for={run <- @runs} class="px-4 py-3">
          <div class="flex items-center justify-between gap-3">
            <p class="min-w-0 truncate font-medium text-base-content">{run.playbook_name}</p>
            <span class="shrink-0 text-xs text-base-content/50">
              {run.completed_task_count} of {run.task_count} done
            </span>
          </div>
          <div class="mt-2 h-1.5 w-full overflow-hidden rounded-full bg-zinc-200 dark:bg-white/10">
            <div
              class="h-full rounded-full bg-emerald-600 dark:bg-emerald-500"
              style={"width: #{progress_percent(run)}%"}
            />
          </div>
        </div>
      </div>
    </.section>
    """
  end

  defp progress_percent(%{task_count: 0}), do: 0

  defp progress_percent(%{task_count: total, completed_task_count: completed}),
    do: round(completed / total * 100)

  @doc """
  Route to the most specific record a task is linked to, built from foreign
  keys so no relationship loading is required. Bid and procurement-source
  links have no routable page yet and fall through to broader contexts.
  """
  def context_path(%{work_item_id: id}) when is_binary(id), do: "/execution/work-items/#{id}"
  def context_path(%{work_order_id: id}) when is_binary(id), do: "/execution/work-orders/#{id}"
  def context_path(%{project_id: id}) when is_binary(id), do: "/execution/projects/#{id}"
  def context_path(%{pursuit_id: id}) when is_binary(id), do: "/commercial/pursuits/#{id}"
  def context_path(%{signal_id: id}) when is_binary(id), do: "/commercial/signals/#{id}"
  def context_path(%{finding_id: id}) when is_binary(id), do: "/acquisition/findings/#{id}"
  def context_path(%{agent_run_id: id}) when is_binary(id), do: "/console/agents/runs/#{id}"

  def context_path(%{organization_id: id}) when is_binary(id),
    do: "/operations/organizations/#{id}"

  def context_path(%{person_id: id}) when is_binary(id), do: "/operations/people/#{id}"
  def context_path(_task), do: nil

  defp origin_color(:acquisition), do: :emerald
  defp origin_color(:agents), do: :sky
  defp origin_color(:commercial), do: :amber
  defp origin_color(:finance), do: :rose
  defp origin_color(:execution), do: :sky
  defp origin_color(:operations), do: :zinc
  defp origin_color(_origin_domain), do: :zinc
end
