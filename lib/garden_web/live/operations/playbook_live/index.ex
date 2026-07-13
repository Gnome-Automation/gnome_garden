defmodule GnomeGardenWeb.Operations.PlaybookLive.Index do
  use GnomeGardenWeb, :live_view

  alias GnomeGarden.Operations

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Playbooks")
     |> assign_playbooks()}
  end

  @impl true
  def handle_event("install_starters", _params, socket) do
    case Operations.ensure_starter_playbooks(actor: socket.assigns.current_user) do
      {:ok, results} ->
        created = results |> Enum.count(fn {_name, outcome} -> outcome == :created end)

        {:noreply,
         socket
         |> put_flash(:info, "Starter playbooks installed (#{created} new)")
         |> assign_playbooks()}

      {:error, error} ->
        {:noreply, put_flash(socket, :error, "Could not install starters: #{inspect(error)}")}
    end
  end

  @impl true
  def handle_event("archive", %{"id" => id}, socket) do
    with {:ok, playbook} <- Operations.get_playbook(id, actor: socket.assigns.current_user),
         {:ok, _archived} <-
           Operations.archive_playbook(playbook, actor: socket.assigns.current_user) do
      {:noreply, socket |> put_flash(:info, "Playbook archived") |> assign_playbooks()}
    else
      {:error, error} ->
        {:noreply, put_flash(socket, :error, "Could not archive playbook: #{inspect(error)}")}
    end
  end

  @impl true
  def handle_event("reactivate", %{"id" => id}, socket) do
    with {:ok, playbook} <- Operations.get_playbook(id, actor: socket.assigns.current_user),
         {:ok, _active} <-
           Operations.reactivate_playbook(playbook, actor: socket.assigns.current_user) do
      {:noreply, socket |> put_flash(:info, "Playbook reactivated") |> assign_playbooks()}
    else
      {:error, error} ->
        {:noreply, put_flash(socket, :error, "Could not reactivate playbook: #{inspect(error)}")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.page class="pb-8">
      <.page_header eyebrow="Operations">
        Playbooks
        <:subtitle>
          Reusable task recipes. Apply one to a pursuit, project, or source to
          create its coordinated task set.
        </:subtitle>
        <:actions>
          <.button phx-click="install_starters" id="install-starters">
            Install starters
          </.button>
          <.button navigate={~p"/operations/playbooks/new"} variant="primary">
            New Playbook
          </.button>
        </:actions>
      </.page_header>

      <.section title="Active" body_class="p-0">
        <div :if={@active == []} class="p-4">
          <.empty_state
            icon="hero-book-open"
            title="No playbooks yet"
            description="Install the starters or create your first playbook."
          />
        </div>
        <div :if={@active != []} class="divide-y divide-zinc-200 dark:divide-white/10">
          <div
            :for={playbook <- @active}
            class="flex items-center justify-between gap-3 px-4 py-3 transition hover:bg-zinc-50 dark:hover:bg-white/[0.03]"
          >
            <.link navigate={~p"/operations/playbooks/#{playbook}"} class="min-w-0 flex-1">
              <p class="font-medium text-base-content">{playbook.name}</p>
              <p :if={playbook.description} class="truncate text-sm text-base-content/60">
                {playbook.description}
              </p>
            </.link>
            <div class="flex shrink-0 items-center gap-3">
              <span class="text-xs text-base-content/50">{playbook.step_count} steps</span>
              <.button phx-click="archive" phx-value-id={playbook.id}>
                Archive
              </.button>
            </div>
          </div>
        </div>
      </.section>

      <.section :if={@archived != []} title="Archived" body_class="p-0">
        <div class="divide-y divide-zinc-200 dark:divide-white/10">
          <div
            :for={playbook <- @archived}
            class="flex items-center justify-between gap-3 px-4 py-3"
          >
            <p class="font-medium text-base-content/60">{playbook.name}</p>
            <.button phx-click="reactivate" phx-value-id={playbook.id}>
              Reactivate
            </.button>
          </div>
        </div>
      </.section>
    </.page>
    """
  end

  defp assign_playbooks(socket) do
    case Operations.list_playbooks(
           actor: socket.assigns.current_user,
           load: [:step_count],
           query: [sort: [name: :asc]]
         ) do
      {:ok, playbooks} ->
        {active, archived} = Enum.split_with(playbooks, &(&1.status == :active))
        socket |> assign(:active, active) |> assign(:archived, archived)

      {:error, error} ->
        raise "failed to load playbooks: #{inspect(error)}"
    end
  end
end
