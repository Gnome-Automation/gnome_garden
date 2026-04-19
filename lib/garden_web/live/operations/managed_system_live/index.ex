defmodule GnomeGardenWeb.Operations.ManagedSystemLive.Index do
  use GnomeGardenWeb, :live_view

  import GnomeGardenWeb.Operations.Helpers

  alias GnomeGarden.Operations

  @impl true
  def mount(_params, _session, socket) do
    managed_systems = load_managed_systems(socket.assigns.current_user)

    {:ok,
     socket
     |> assign(:page_title, "Managed Systems")
     |> assign(:system_count, length(managed_systems))
     |> assign(:active_count, Enum.count(managed_systems, &(&1.lifecycle_status == :active)))
     |> assign(:critical_count, Enum.count(managed_systems, &(&1.criticality == :critical)))
     |> assign(
       :asset_count,
       Enum.reduce(managed_systems, 0, fn system, total -> total + (system.asset_count || 0) end)
     )
     |> stream(:managed_systems, managed_systems)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.page class="pb-8">
      <.page_header eyebrow="Operations">
        Managed Systems
        <:subtitle>
          Automation stacks, applications, integrations, and hybrid installations that sit between sites and assets.
        </:subtitle>
        <:actions>
          <.button navigate={~p"/operations/sites"}>
            <.icon name="hero-map-pin" class="size-4" /> Sites
          </.button>
          <.button navigate={~p"/operations/managed-systems/new"} variant="primary">
            <.icon name="hero-plus" class="size-4" /> New Managed System
          </.button>
        </:actions>
      </.page_header>

      <div class="grid gap-4 md:grid-cols-4">
        <.stat_card
          title="Managed Systems"
          value={Integer.to_string(@system_count)}
          description="Named system contexts that delivery, support, and assets can attach to."
          icon="hero-circle-stack"
        />
        <.stat_card
          title="Active"
          value={Integer.to_string(@active_count)}
          description="Systems currently in the live supported or delivered estate."
          icon="hero-check-badge"
          accent="emerald"
        />
        <.stat_card
          title="Critical"
          value={Integer.to_string(@critical_count)}
          description="Systems whose failure would carry high operational risk."
          icon="hero-exclamation-triangle"
          accent="amber"
        />
        <.stat_card
          title="Assets"
          value={Integer.to_string(@asset_count)}
          description="Assets already grouped under a managed system context."
          icon="hero-cpu-chip"
          accent="rose"
        />
      </div>

      <.section
        title="System Context"
        description="Managed systems keep automation, software, and hybrid installations explicit instead of burying them inside project or asset notes."
        compact
        body_class="p-0"
      >
        <div :if={@system_count == 0} class="p-6 sm:p-7">
          <.empty_state
            icon="hero-circle-stack"
            title="No managed systems yet"
            description="Create managed systems for the major automation, application, or integration stacks you build and support."
          >
            <:action>
              <.button navigate={~p"/operations/managed-systems/new"} variant="primary">
                Create Managed System
              </.button>
            </:action>
          </.empty_state>
        </div>

        <div :if={@system_count > 0} class="overflow-x-auto">
          <table class="min-w-full divide-y divide-zinc-200 text-sm dark:divide-white/10">
            <thead class="bg-zinc-50 dark:bg-white/[0.03]">
              <tr>
                <th class="px-5 py-3 text-left font-medium text-zinc-500 dark:text-zinc-400">
                  Managed System
                </th>
                <th class="px-5 py-3 text-left font-medium text-zinc-500 dark:text-zinc-400">
                  Organization
                </th>
                <th class="px-5 py-3 text-left font-medium text-zinc-500 dark:text-zinc-400">
                  Site
                </th>
                <th class="px-5 py-3 text-left font-medium text-zinc-500 dark:text-zinc-400">
                  Lifecycle
                </th>
                <th class="px-5 py-3 text-left font-medium text-zinc-500 dark:text-zinc-400">
                  Criticality
                </th>
              </tr>
            </thead>
            <tbody
              id="managed-systems"
              phx-update="stream"
              class="divide-y divide-zinc-200 dark:divide-white/10"
            >
              <tr :for={{dom_id, managed_system} <- @streams.managed_systems} id={dom_id}>
                <td class="px-5 py-4 align-top">
                  <div class="space-y-1">
                    <.link
                      navigate={~p"/operations/managed-systems/#{managed_system}"}
                      class="font-medium text-zinc-900 hover:text-emerald-600 dark:text-white"
                    >
                      {managed_system.name}
                    </.link>
                    <p class="text-sm text-zinc-500 dark:text-zinc-400">
                      {managed_system.code || "No system code"}
                    </p>
                  </div>
                </td>
                <td class="px-5 py-4 align-top text-zinc-600 dark:text-zinc-300">
                  {(managed_system.organization && managed_system.organization.name) || "-"}
                </td>
                <td class="px-5 py-4 align-top text-zinc-600 dark:text-zinc-300">
                  <div class="space-y-1">
                    <p>{(managed_system.site && managed_system.site.name) || "-"}</p>
                    <p class="text-xs text-zinc-400 dark:text-zinc-500">
                      {format_atom(managed_system.system_type)}
                    </p>
                  </div>
                </td>
                <td class="px-5 py-4 align-top">
                  <.status_badge status={managed_system.lifecycle_variant}>
                    {format_atom(managed_system.lifecycle_status)}
                  </.status_badge>
                </td>
                <td class="px-5 py-4 align-top">
                  <div class="space-y-1">
                    <.status_badge status={managed_system.criticality_variant}>
                      {format_atom(managed_system.criticality)}
                    </.status_badge>
                    <p class="text-xs text-zinc-400 dark:text-zinc-500">
                      {managed_system.asset_count || 0} assets
                    </p>
                  </div>
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </.section>
    </.page>
    """
  end

  defp load_managed_systems(actor) do
    case Operations.list_managed_systems(
           actor: actor,
           query: [sort: [name: :asc]],
           load: [
             :lifecycle_variant,
             :criticality_variant,
             :asset_count,
             organization: [],
             site: []
           ]
         ) do
      {:ok, managed_systems} -> managed_systems
      {:error, error} -> raise "failed to load managed systems: #{inspect(error)}"
    end
  end
end
