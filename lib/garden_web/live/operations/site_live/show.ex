defmodule GnomeGardenWeb.Operations.SiteLive.Show do
  use GnomeGardenWeb, :live_view

  import GnomeGardenWeb.Operations.Helpers

  alias GnomeGarden.Operations

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    site = load_site!(id, socket.assigns.current_user)

    {:ok,
     socket
     |> assign(:page_title, site.name)
     |> assign(:site, site)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.page class="pb-8">
      <.page_header eyebrow="Operations">
        {@site.name}
        <:subtitle>
          <span class="inline-flex items-center gap-2">
            <.status_badge status={@site.status_variant}>
              {format_atom(@site.status)}
            </.status_badge>
            <span class="text-zinc-400 dark:text-zinc-500">/</span>
            <span>{@site.code || "No site code"}</span>
          </span>
        </:subtitle>
        <:actions>
          <.button navigate={~p"/operations/sites"}>
            <.icon name="hero-arrow-left" class="size-4" /> Back
          </.button>
          <.button navigate={~p"/operations/managed-systems/new?site_id=#{@site.id}"}>
            <.icon name="hero-circle-stack" class="size-4" /> New Managed System
          </.button>
          <.button navigate={~p"/operations/assets/new?site_id=#{@site.id}"}>
            <.icon name="hero-cpu-chip" class="size-4" /> New Asset
          </.button>
          <.button navigate={~p"/operations/sites/#{@site}/edit"}>
            <.icon name="hero-pencil-square" class="size-4" /> Edit
          </.button>
        </:actions>
      </.page_header>

      <div class="grid gap-6 lg:grid-cols-2">
        <.section title="Site Profile">
          <div class="grid gap-5 sm:grid-cols-2">
            <.property_item label="Site Kind" value={format_atom(@site.site_kind)} />
            <.property_item label="Status" value={format_atom(@site.status)} />
            <.property_item label="Address 1" value={@site.address1 || "-"} />
            <.property_item label="Address 2" value={@site.address2 || "-"} />
            <.property_item label="City" value={@site.city || "-"} />
            <.property_item label="State" value={@site.state || "-"} />
            <.property_item label="Postal Code" value={@site.postal_code || "-"} />
            <.property_item label="Country" value={@site.country_code || "-"} />
            <.property_item label="Timezone" value={@site.timezone || "-"} />
          </div>
        </.section>

        <.section title="Operational Context">
          <div class="grid gap-5 sm:grid-cols-2">
            <.property_item
              label="Organization"
              value={(@site.organization && @site.organization.name) || "-"}
            />
            <.property_item
              label="Managed Systems"
              value={Integer.to_string(@site.managed_system_count || 0)}
            />
            <.property_item label="Assets" value={Integer.to_string(@site.asset_count || 0)} />
          </div>
        </.section>
      </div>

      <.section :if={@site.notes} title="Notes">
        <p class="whitespace-pre-wrap text-sm leading-6 text-zinc-600 dark:text-zinc-300">
          {@site.notes}
        </p>
      </.section>

      <.section
        title="Managed Systems"
        description="Use managed systems to represent the automation stacks, applications, and hybrid installations tied to this site."
      >
        <div :if={Enum.empty?(@site.managed_systems || [])}>
          <.empty_state
            icon="hero-circle-stack"
            title="No managed systems yet"
            description="Add managed systems to describe the major automation, software, or integration stacks at this site."
          />
        </div>

        <div :if={!Enum.empty?(@site.managed_systems || [])} class="space-y-3">
          <.link
            :for={managed_system <- @site.managed_systems}
            navigate={~p"/operations/managed-systems/#{managed_system}"}
            class="flex items-center justify-between rounded-2xl border border-zinc-200 bg-zinc-50/70 px-4 py-4 transition hover:border-emerald-300 hover:bg-white dark:border-white/10 dark:bg-white/[0.03] dark:hover:border-emerald-400/40"
          >
            <div class="space-y-1">
              <p class="font-medium text-zinc-900 dark:text-white">{managed_system.name}</p>
              <p class="text-sm text-zinc-500 dark:text-zinc-400">
                {managed_system.code || "No system code"}
              </p>
            </div>
            <.status_badge status={managed_system.lifecycle_variant}>
              {format_atom(managed_system.lifecycle_status)}
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

  defp load_site!(id, actor) do
    case Operations.get_site(
           id,
           actor: actor,
           load: [
             :status_variant,
             :managed_system_count,
             :asset_count,
             organization: [],
             managed_systems: [:lifecycle_variant]
           ]
         ) do
      {:ok, site} -> site
      {:error, error} -> raise "failed to load site #{id}: #{inspect(error)}"
    end
  end
end
