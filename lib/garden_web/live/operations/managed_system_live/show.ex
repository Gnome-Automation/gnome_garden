defmodule GnomeGardenWeb.Operations.ManagedSystemLive.Show do
  use GnomeGardenWeb, :live_view

  import GnomeGardenWeb.Operations.Helpers

  alias GnomeGarden.Operations

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    managed_system = load_managed_system!(id, socket.assigns.current_user)

    {:ok,
     socket
     |> assign(:page_title, managed_system.name)
     |> assign(:managed_system, managed_system)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.page class="pb-8">
      <.page_header eyebrow="Operations">
        {@managed_system.name}
        <:subtitle>
          <span class="inline-flex items-center gap-2">
            <.status_badge status={@managed_system.lifecycle_variant}>
              {format_atom(@managed_system.lifecycle_status)}
            </.status_badge>
            <span class="text-zinc-400 dark:text-zinc-500">/</span>
            <span>{@managed_system.code || "No system code"}</span>
          </span>
        </:subtitle>
        <:actions>
          <.button navigate={~p"/operations/managed-systems"}>
            <.icon name="hero-arrow-left" class="size-4" /> Back
          </.button>
          <.button navigate={~p"/operations/assets/new?managed_system_id=#{@managed_system.id}"}>
            <.icon name="hero-cpu-chip" class="size-4" /> New Asset
          </.button>
          <.button navigate={~p"/operations/managed-systems/#{@managed_system}/edit"}>
            <.icon name="hero-pencil-square" class="size-4" /> Edit
          </.button>
        </:actions>
      </.page_header>

      <div class="grid gap-6 lg:grid-cols-2">
        <.section title="System Profile">
          <div class="grid gap-5 sm:grid-cols-2">
            <.property_item label="System Type" value={format_atom(@managed_system.system_type)} />
            <.property_item
              label="Delivery Mode"
              value={format_atom(@managed_system.delivery_mode)}
            />
            <.property_item
              label="Lifecycle"
              value={format_atom(@managed_system.lifecycle_status)}
            />
            <.property_item label="Criticality" value={format_atom(@managed_system.criticality)} />
            <.property_item label="Vendor" value={@managed_system.vendor || "-"} />
            <.property_item label="Platform" value={@managed_system.platform || "-"} />
          </div>
        </.section>

        <.section title="Operational Context">
          <div class="grid gap-5 sm:grid-cols-2">
            <.property_item
              label="Organization"
              value={(@managed_system.organization && @managed_system.organization.name) || "-"}
            />
            <.property_item
              label="Site"
              value={(@managed_system.site && @managed_system.site.name) || "-"}
            />
            <.property_item
              label="Assets"
              value={Integer.to_string(@managed_system.asset_count || 0)}
            />
          </div>
        </.section>
      </div>

      <.section :if={@managed_system.description} title="Description">
        <p class="whitespace-pre-wrap text-sm leading-6 text-zinc-600 dark:text-zinc-300">
          {@managed_system.description}
        </p>
      </.section>

      <.section :if={@managed_system.notes} title="Notes">
        <p class="whitespace-pre-wrap text-sm leading-6 text-zinc-600 dark:text-zinc-300">
          {@managed_system.notes}
        </p>
      </.section>

      <.section
        title="Assets"
        description="Use assets for the specific physical or digital components that sit inside this managed system."
      >
        <div :if={Enum.empty?(@managed_system.assets || [])}>
          <.empty_state
            icon="hero-cpu-chip"
            title="No assets yet"
            description="Create assets here when this managed system contains panels, controllers, applications, or other managed components."
          />
        </div>

        <div :if={!Enum.empty?(@managed_system.assets || [])} class="space-y-3">
          <.link
            :for={asset <- @managed_system.assets}
            navigate={~p"/operations/assets/#{asset}"}
            class="flex items-center justify-between rounded-2xl border border-zinc-200 bg-zinc-50/70 px-4 py-4 transition hover:border-emerald-300 hover:bg-white dark:border-white/10 dark:bg-white/[0.03] dark:hover:border-emerald-400/40"
          >
            <div class="space-y-1">
              <p class="font-medium text-zinc-900 dark:text-white">{asset.name}</p>
              <p class="text-sm text-zinc-500 dark:text-zinc-400">
                {asset.asset_tag || "No asset tag"}
              </p>
            </div>
            <.status_badge status={asset.lifecycle_variant}>
              {format_atom(asset.lifecycle_status)}
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

  defp load_managed_system!(id, actor) do
    case Operations.get_managed_system(
           id,
           actor: actor,
           load: [
             :lifecycle_variant,
             :criticality_variant,
             :asset_count,
             organization: [],
             site: [],
             assets: [:lifecycle_variant]
           ]
         ) do
      {:ok, managed_system} -> managed_system
      {:error, error} -> raise "failed to load managed system #{id}: #{inspect(error)}"
    end
  end
end
