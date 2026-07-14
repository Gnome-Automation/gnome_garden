defmodule GnomeGardenWeb.Company.QualificationLive.Index do
  use GnomeGardenWeb, :live_view

  import GnomeGardenWeb.Operations.Helpers, only: [format_atom: 1]

  alias GnomeGarden.Company

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      GnomeGardenWeb.Endpoint.subscribe("company_qualification:created")
      GnomeGardenWeb.Endpoint.subscribe("company_qualification:updated")
    end

    {:ok,
     socket
     |> assign(:page_title, "Qualifications")
     |> assign_qualifications()}
  end

  @impl true
  def handle_event(action, %{"id" => id}, socket)
      when action in ["activate", "suspend", "expire", "retire"] do
    actor = socket.assigns.current_user

    with {:ok, qualification} <- Company.get_company_qualification(id, actor: actor),
         {:ok, _updated} <- transition(action, qualification, actor) do
      {:noreply,
       socket |> put_flash(:info, "Qualification #{action}d") |> assign_qualifications()}
    else
      {:error, error} ->
        {:noreply, put_flash(socket, :error, "Could not update: #{inspect(error)}")}
    end
  end

  defp transition("activate", qualification, actor),
    do: Company.activate_company_qualification(qualification, %{}, actor: actor)

  defp transition("suspend", qualification, actor),
    do: Company.suspend_company_qualification(qualification, actor: actor)

  defp transition("expire", qualification, actor),
    do: Company.expire_company_qualification(qualification, actor: actor)

  defp transition("retire", qualification, actor),
    do: Company.retire_company_qualification(qualification, actor: actor)

  @impl true
  def handle_info(%{topic: "company_qualification:" <> _event}, socket) do
    {:noreply, assign_qualifications(socket)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.page class="pb-8">
      <.page_header eyebrow="Company">
        Qualifications
        <:subtitle>
          The durable capabilities Gnome holds — registrations, licenses,
          certifications, insurance, bonding, and partner standing — with
          expirations and evidence.
        </:subtitle>
        <:actions>
          <.button navigate={~p"/company/qualifications/new"} variant="primary">
            New Qualification
          </.button>
        </:actions>
      </.page_header>

      <.section title="Registry" body_class="p-0">
        <div :if={@qualifications == []} class="p-4">
          <.empty_state
            icon="hero-shield-check"
            title="No qualifications recorded"
            description="Record what Gnome already holds, then grow the list through initiatives."
          />
        </div>
        <div
          :if={@qualifications != []}
          class="divide-y divide-zinc-200 dark:divide-white/10"
        >
          <div
            :for={qualification <- @qualifications}
            class="flex flex-col gap-2 px-4 py-3 md:flex-row md:items-center md:justify-between"
          >
            <.link navigate={~p"/company/qualifications/#{qualification}/edit"} class="min-w-0">
              <p class="font-medium text-base-content">{qualification.name}</p>
              <p class="text-xs text-base-content/50">
                {format_atom(qualification.kind)} · {qualification.issuing_authority}
                <span :if={qualification.identifier}>· {qualification.identifier}</span>
                <span :if={qualification.expires_on}>
                  · expires {qualification.expires_on}
                </span>
                <span :if={qualification.owner_team_member}>
                  · {qualification.owner_team_member.display_name}
                </span>
              </p>
            </.link>
            <div class="flex shrink-0 items-center gap-2">
              <.status_badge status={qualification.status_variant}>
                {format_atom(qualification.status)}
              </.status_badge>
              <.button
                :if={qualification.status in [:pending, :suspended, :expired]}
                phx-click="activate"
                phx-value-id={qualification.id}
                variant="primary"
              >
                Activate
              </.button>
              <.button
                :if={qualification.status == :active}
                phx-click="suspend"
                phx-value-id={qualification.id}
              >
                Suspend
              </.button>
              <.button
                :if={qualification.status in [:active, :suspended]}
                phx-click="expire"
                phx-value-id={qualification.id}
              >
                Expire
              </.button>
              <.button
                :if={qualification.status != :retired}
                phx-click="retire"
                phx-value-id={qualification.id}
              >
                Retire
              </.button>
            </div>
          </div>
        </div>
      </.section>
    </.page>
    """
  end

  defp assign_qualifications(socket) do
    case Company.list_company_qualification_registry(actor: socket.assigns.current_user) do
      {:ok, qualifications} -> assign(socket, :qualifications, qualifications)
      {:error, error} -> raise "failed to load qualifications: #{inspect(error)}"
    end
  end
end
