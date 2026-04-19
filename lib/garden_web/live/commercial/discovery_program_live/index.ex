defmodule GnomeGardenWeb.Commercial.DiscoveryProgramLive.Index do
  use GnomeGardenWeb, :live_view

  import GnomeGardenWeb.Commercial.Helpers

  alias GnomeGarden.Commercial

  @impl true
  def mount(_params, _session, socket) do
    programs = load_programs(socket.assigns.current_user)

    {:ok,
     socket
     |> assign(:page_title, "Discovery Programs")
     |> assign(:program_count, length(programs))
     |> assign(:active_count, Enum.count(programs, &(&1.status == :active)))
     |> assign(:review_target_count, Enum.reduce(programs, 0, &(&1.review_target_count + &2)))
     |> assign(:last_run_count, Enum.count(programs, & &1.last_run_at))
     |> stream(:programs, programs)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.page class="pb-8">
      <.page_header eyebrow="Commercial">
        Discovery Programs
        <:subtitle>
          Durable lead-finder definitions for regions, industries, and search motions. Programs own the discovery backlog without confusing it with runtime-only agent state.
        </:subtitle>
        <:actions>
          <.button navigate={~p"/commercial/targets"}>
            <.icon name="hero-magnifying-glass" class="size-4" /> Targets
          </.button>
          <.button navigate={~p"/commercial/discovery-programs/new"} variant="primary">
            <.icon name="hero-plus" class="size-4" /> New Program
          </.button>
        </:actions>
      </.page_header>

      <div class="grid gap-4 md:grid-cols-4">
        <.stat_card
          title="Programs"
          value={Integer.to_string(@program_count)}
          description="Defined outbound and market-discovery motions."
          icon="hero-radar"
        />
        <.stat_card
          title="Active"
          value={Integer.to_string(@active_count)}
          description="Programs currently intended to drive discovery work."
          icon="hero-play-circle"
          accent="emerald"
        />
        <.stat_card
          title="Review Targets"
          value={Integer.to_string(@review_target_count)}
          description="Backlog of targets currently attached to these programs."
          icon="hero-magnifying-glass"
          accent="sky"
        />
        <.stat_card
          title="Recently Run"
          value={Integer.to_string(@last_run_count)}
          description="Programs that have an execution timestamp recorded."
          icon="hero-clock"
          accent="amber"
        />
      </div>

      <.section
        title="Discovery Portfolio"
        description="Treat lead finding as a real operating motion with explicit scope, cadence, and backlog ownership."
        compact
        body_class="p-0"
      >
        <div :if={@program_count == 0} class="p-6 sm:p-7">
          <.empty_state
            icon="hero-radar"
            title="No discovery programs yet"
            description="Create a program for a region, industry, or target hunt before scaling discovery."
          >
            <:action>
              <.button navigate={~p"/commercial/discovery-programs/new"} variant="primary">
                Create Discovery Program
              </.button>
            </:action>
          </.empty_state>
        </div>

        <div :if={@program_count > 0} class="overflow-x-auto">
          <table class="min-w-full divide-y divide-zinc-200 text-sm dark:divide-white/10">
            <thead class="bg-zinc-50 dark:bg-white/[0.03]">
              <tr>
                <th class="px-5 py-3 text-left font-medium text-zinc-500 dark:text-zinc-400">
                  Program
                </th>
                <th class="px-5 py-3 text-left font-medium text-zinc-500 dark:text-zinc-400">
                  Scope
                </th>
                <th class="px-5 py-3 text-left font-medium text-zinc-500 dark:text-zinc-400">
                  Backlog
                </th>
                <th class="px-5 py-3 text-left font-medium text-zinc-500 dark:text-zinc-400">
                  Cadence
                </th>
                <th class="px-5 py-3 text-left font-medium text-zinc-500 dark:text-zinc-400">
                  Status
                </th>
              </tr>
            </thead>
            <tbody
              id="discovery-programs"
              phx-update="stream"
              class="divide-y divide-zinc-200 dark:divide-white/10"
            >
              <tr :for={{dom_id, program} <- @streams.programs} id={dom_id}>
                <td class="px-5 py-4 align-top">
                  <div class="space-y-1">
                    <.link
                      navigate={~p"/commercial/discovery-programs/#{program}"}
                      class="font-medium text-zinc-900 hover:text-emerald-600 dark:text-white"
                    >
                      {program.name}
                    </.link>
                    <p class="text-sm text-zinc-500 dark:text-zinc-400">
                      {format_atom(program.program_type)}
                    </p>
                  </div>
                </td>
                <td class="px-5 py-4 align-top text-zinc-600 dark:text-zinc-300">
                  <div class="space-y-1">
                    <p>{summary_list(program.target_regions, "No regions")}</p>
                    <p class="text-xs text-zinc-400 dark:text-zinc-500">
                      {summary_list(program.target_industries, "No industries")}
                    </p>
                  </div>
                </td>
                <td class="px-5 py-4 align-top text-zinc-600 dark:text-zinc-300">
                  <div class="space-y-1">
                    <p>{program.target_account_count} targets</p>
                    <p class="text-xs text-zinc-400 dark:text-zinc-500">
                      {program.review_target_count} waiting review
                    </p>
                  </div>
                </td>
                <td class="px-5 py-4 align-top text-zinc-600 dark:text-zinc-300">
                  <div class="space-y-1">
                    <p>Every {program.cadence_hours}h</p>
                    <div class="flex flex-wrap items-center gap-2 text-xs text-zinc-400 dark:text-zinc-500">
                      <span>{format_datetime(program.last_run_at)}</span>
                      <.status_badge status={program.run_status_variant}>
                        {program.run_status_label}
                      </.status_badge>
                    </div>
                  </div>
                </td>
                <td class="px-5 py-4 align-top">
                  <div class="space-y-2">
                    <.status_badge status={program.status_variant}>
                      {format_atom(program.status)}
                    </.status_badge>
                    <.status_badge status={program.priority_variant}>
                      {format_atom(program.priority)}
                    </.status_badge>
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

  defp load_programs(actor) do
    case Commercial.list_discovery_programs(
           actor: actor,
           query: [sort: [priority: :desc, inserted_at: :desc]],
           load: [
             :status_variant,
             :priority_variant,
             :is_due_to_run,
             :run_status_variant,
             :run_status_label,
             :target_account_count,
             :review_target_count,
             :observation_count,
             :latest_observed_at
           ]
         ) do
      {:ok, programs} -> programs
      {:error, error} -> raise "failed to load discovery programs: #{inspect(error)}"
    end
  end

  defp summary_list([], empty_label), do: empty_label
  defp summary_list(values, _empty_label), do: Enum.join(values, ", ")
end
