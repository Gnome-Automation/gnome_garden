defmodule GnomeGardenWeb.Commercial.SignalLive.Show do
  use GnomeGardenWeb, :live_view

  import GnomeGardenWeb.Commercial.Helpers

  alias GnomeGarden.Commercial

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    signal = load_signal!(id, socket.assigns.current_user)

    {:ok,
     socket
     |> assign(:page_title, signal.title)
     |> assign(:signal, signal)}
  end

  @impl true
  def handle_event("transition", %{"action" => action}, socket) do
    signal = socket.assigns.signal

    case transition_signal(signal, String.to_existing_atom(action), socket.assigns.current_user) do
      {:ok, updated_signal} ->
        {:noreply,
         socket
         |> assign(:signal, load_signal!(updated_signal.id, socket.assigns.current_user))
         |> put_flash(:info, "Signal updated")}

      {:error, error} ->
        {:noreply, put_flash(socket, :error, "Could not update signal: #{inspect(error)}")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.page class="pb-8">
      <.page_header eyebrow="Commercial">
        {@signal.title}
        <:subtitle>
          <span class="inline-flex items-center gap-2">
            <.status_badge status={@signal.status_variant}>
              {format_atom(@signal.status)}
            </.status_badge>
            <span class="text-zinc-400 dark:text-zinc-500">/</span>
            <span>{format_atom(@signal.signal_type)}</span>
          </span>
        </:subtitle>
        <:actions>
          <.button navigate={~p"/commercial/signals"}>
            <.icon name="hero-arrow-left" class="size-4" /> Back
          </.button>
          <.button
            :if={can_create_pursuit?(@signal)}
            navigate={~p"/commercial/pursuits/new?signal_id=#{@signal.id}"}
            variant="primary"
          >
            <.icon name="hero-arrow-trending-up" class="size-4" /> Create Pursuit
          </.button>
          <.button navigate={~p"/commercial/signals/#{@signal}/edit"}>
            <.icon name="hero-pencil-square" class="size-4" /> Edit
          </.button>
        </:actions>
      </.page_header>

      <.section
        title="Review Actions"
        description="Move the intake item through review and convert it into pipeline only when it deserves follow-up."
      >
        <div class="flex flex-wrap gap-3">
          <.button
            :for={action <- signal_actions(@signal)}
            phx-click="transition"
            phx-value-action={action.action}
            variant={action.variant}
          >
            <.icon name={action.icon} class="size-4" /> {action.label}
          </.button>
        </div>
      </.section>

      <div class="grid gap-6 lg:grid-cols-2">
        <.section title="Signal Context">
          <div class="grid gap-5 sm:grid-cols-2">
            <.property_item label="Signal Type" value={format_atom(@signal.signal_type)} />
            <.property_item label="Source Channel" value={format_atom(@signal.source_channel)} />
            <.property_item label="External Ref" value={@signal.external_ref || "-"} />
            <.property_item
              label="Observed"
              value={format_datetime(@signal.observed_at || @signal.inserted_at)}
            />
            <.property_item label="Source URL" value={@signal.source_url || "-"} />
            <.property_item label="Created" value={format_datetime(@signal.inserted_at)} />
          </div>
        </.section>

        <.section title="Operating Context">
          <div class="grid gap-5 sm:grid-cols-2">
            <.property_item
              label="Organization"
              value={(@signal.organization && @signal.organization.name) || "-"}
            />
            <.property_item label="Site" value={(@signal.site && @signal.site.name) || "-"} />
            <.property_item
              label="Managed System"
              value={(@signal.managed_system && @signal.managed_system.name) || "-"}
            />
            <.property_item
              label="Linked Pursuits"
              value={Integer.to_string(length(@signal.pursuits || []))}
            />
          </div>
        </.section>
      </div>

      <.section :if={@signal.description} title="Description">
        <p class="whitespace-pre-wrap text-sm leading-6 text-zinc-600 dark:text-zinc-300">
          {@signal.description}
        </p>
      </.section>

      <.section :if={@signal.notes} title="Notes">
        <p class="whitespace-pre-wrap text-sm leading-6 text-zinc-600 dark:text-zinc-300">
          {@signal.notes}
        </p>
      </.section>

      <.section
        title="Downstream Pursuits"
        description="Signals should only become pursuits after a clear accept-and-convert decision."
      >
        <div :if={Enum.empty?(@signal.pursuits || [])}>
          <.empty_state
            icon="hero-arrow-trending-up"
            title="No pursuits yet"
            description="Accept the signal, then convert it into a pursuit when someone is ready to own the follow-up."
          />
        </div>

        <div :if={!Enum.empty?(@signal.pursuits || [])} class="space-y-3">
          <.link
            :for={pursuit <- @signal.pursuits}
            navigate={~p"/commercial/pursuits/#{pursuit}"}
            class="flex items-center justify-between rounded-2xl border border-zinc-200 bg-zinc-50/70 px-4 py-4 transition hover:border-emerald-300 hover:bg-white dark:border-white/10 dark:bg-white/[0.03] dark:hover:border-emerald-400/40"
          >
            <div class="space-y-1">
              <p class="font-medium text-zinc-900 dark:text-white">{pursuit.name}</p>
              <p class="text-sm text-zinc-500 dark:text-zinc-400">
                {format_atom(pursuit.pursuit_type)}
              </p>
            </div>
            <.status_badge status={pursuit.stage_variant}>
              {format_atom(pursuit.stage)}
            </.status_badge>
          </.link>
        </div>
      </.section>
    </.page>
    """
  end

  attr :label, :string, required: true
  attr :value, :string, required: true

  defp property_item(assigns) do
    ~H"""
    <div class="space-y-1">
      <p class="text-xs font-semibold uppercase tracking-[0.2em] text-zinc-400 dark:text-zinc-500">
        {@label}
      </p>
      <p class="text-sm font-medium text-zinc-900 dark:text-white">{@value}</p>
    </div>
    """
  end

  defp load_signal!(id, actor) do
    case Commercial.get_signal(
           id,
           actor: actor,
           load: [
             :organization,
             :site,
             :managed_system,
             :status_variant,
             pursuits: [:stage_variant]
           ]
         ) do
      {:ok, signal} -> signal
      {:error, error} -> raise "failed to load signal #{id}: #{inspect(error)}"
    end
  end

  defp can_create_pursuit?(signal),
    do: signal.status == :accepted and Enum.empty?(signal.pursuits || [])

  defp signal_actions(%{status: :new}) do
    [
      %{action: "start_review", label: "Start Review", icon: "hero-eye", variant: nil},
      %{action: "accept", label: "Accept", icon: "hero-check", variant: "primary"},
      %{action: "reject", label: "Reject", icon: "hero-x-mark", variant: nil},
      %{action: "archive", label: "Archive", icon: "hero-archive-box", variant: nil}
    ]
  end

  defp signal_actions(%{status: :reviewing}) do
    [
      %{action: "accept", label: "Accept", icon: "hero-check", variant: "primary"},
      %{action: "reject", label: "Reject", icon: "hero-x-mark", variant: nil},
      %{action: "archive", label: "Archive", icon: "hero-archive-box", variant: nil}
    ]
  end

  defp signal_actions(%{status: :accepted}) do
    [
      %{action: "archive", label: "Archive", icon: "hero-archive-box", variant: nil}
    ]
  end

  defp signal_actions(%{status: :rejected}) do
    [
      %{action: "reopen", label: "Reopen", icon: "hero-arrow-path", variant: "primary"},
      %{action: "archive", label: "Archive", icon: "hero-archive-box", variant: nil}
    ]
  end

  defp signal_actions(%{status: :archived}) do
    [
      %{action: "reopen", label: "Reopen", icon: "hero-arrow-path", variant: "primary"}
    ]
  end

  defp signal_actions(_signal), do: []

  defp transition_signal(signal, :start_review, actor),
    do: Commercial.review_signal(signal, actor: actor)

  defp transition_signal(signal, :accept, actor),
    do: Commercial.accept_signal(signal, actor: actor)

  defp transition_signal(signal, :reject, actor),
    do: Commercial.reject_signal(signal, %{}, actor: actor)

  defp transition_signal(signal, :archive, actor),
    do: Commercial.archive_signal(signal, actor: actor)

  defp transition_signal(signal, :reopen, actor),
    do: Commercial.reopen_signal(signal, actor: actor)
end
