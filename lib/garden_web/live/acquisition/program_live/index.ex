defmodule GnomeGardenWeb.Acquisition.ProgramLive.Index do
  use GnomeGardenWeb, :live_view

  import GnomeGardenWeb.Execution.Helpers, only: [format_datetime: 1]

  alias GnomeGarden.Acquisition

  @buckets [:all, :ready, :attention]
  @program_limit 75

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Acquisition Programs")
     |> assign(:buckets, @buckets)
     |> assign(:selected_bucket, :all)
     |> assign(:program_counts, empty_counts())
     |> assign(:programs, [])}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    bucket = parse_bucket(Map.get(params, "bucket"))
    programs = list_programs(socket.assigns.current_user)

    {:noreply,
     socket
     |> assign(:selected_bucket, bucket)
     |> assign(:program_counts, program_counts(programs))
     |> assign(:programs, bucket_programs(programs, bucket))}
  end

  @impl true
  def handle_event("launch_run", %{"id" => id}, socket) do
    with {:ok, program} <-
           Acquisition.get_program(id, actor: socket.assigns.current_user, load: [:runnable]),
         true <- program.runnable,
         {:ok, %{run: run}} <-
           Acquisition.launch_program_run(program,
             actor: socket.assigns.current_user
           ) do
      {:noreply,
       socket
       |> refresh_programs()
       |> put_flash(:info, "Launched discovery run #{run.id} for #{program.name}.")}
    else
      false ->
        {:noreply, put_flash(socket, :error, "Program is not launchable yet.")}

      {:error, error} ->
        {:noreply, put_flash(socket, :error, "Could not launch program run: #{inspect(error)}")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.page class="pb-8">
      <.page_header eyebrow="Acquisition">
        Program Registry
        <:subtitle>
          Durable acquisition programs define why the platform is scanning. This is the acquisition-native view of lane ownership, cadence, and output volume.
        </:subtitle>
        <:actions>
          <.button navigate={~p"/acquisition/findings"}>
            Queue
          </.button>
        </:actions>
      </.page_header>

      <.section
        title="Program Work Queue"
        description="Run durable acquisition lanes from here and open the findings each lane produces."
        compact
        body_class="p-0"
      >
        <div class="grid min-h-[34rem] lg:grid-cols-[17rem_minmax(0,1fr)]">
          <aside class="border-b border-zinc-200 bg-zinc-50/70 p-3 dark:border-white/10 dark:bg-white/[0.03] lg:border-b-0 lg:border-r">
            <div class="grid gap-2 sm:grid-cols-3 lg:grid-cols-1">
              <.bucket_link
                :for={bucket <- @buckets}
                bucket={bucket}
                selected_bucket={@selected_bucket}
                count={bucket_count(@program_counts, bucket)}
              />
            </div>

            <div class="mt-4 grid grid-cols-2 gap-2 lg:grid-cols-1">
              <.registry_count label="Total" value={@program_counts.total} />
              <.registry_count label="Healthy" value={@program_counts.healthy} />
              <.registry_count label="Attention" value={@program_counts.attention} />
              <.registry_count label="Runnable" value={@program_counts.runnable} />
            </div>
          </aside>

          <div class="min-w-0">
            <div class="flex flex-col gap-3 border-b border-zinc-200 px-3 py-3 dark:border-white/10 sm:flex-row sm:items-center sm:justify-between sm:px-4">
              <div class="min-w-0">
                <p class="text-sm font-semibold text-base-content">
                  {bucket_label(@selected_bucket)}
                </p>
                <p class="mt-0.5 text-xs text-base-content/50">
                  Showing {length(@programs)} of {bucket_count(@program_counts, @selected_bucket)} programs
                </p>
              </div>
              <.link navigate={~p"/acquisition/findings"} class="btn btn-sm btn-ghost">
                Open Review Queue
              </.link>
            </div>

            <div
              :if={@programs != []}
              id="acquisition-program-cards"
              class="divide-y divide-zinc-200 bg-base-100 dark:divide-white/10"
            >
              <.program_card :for={program <- @programs} program={program} />
            </div>

            <div :if={@programs == []} class="p-4">
              <.empty_state
                icon="hero-radar"
                title="No programs in this queue"
                description="Change the program queue filter or activate more acquisition programs."
              />
            </div>
          </div>
        </div>
      </.section>
    </.page>
    """
  end

  attr :bucket, :atom, required: true
  attr :selected_bucket, :atom, required: true
  attr :count, :integer, required: true

  defp bucket_link(assigns) do
    ~H"""
    <.link
      patch={~p"/acquisition/programs?bucket=#{@bucket}"}
      class={[
        "inline-flex min-w-0 items-center justify-between gap-2 rounded-md border px-3 py-2 text-sm font-medium transition",
        if(@selected_bucket == @bucket,
          do: "border-emerald-600 bg-emerald-600 text-white shadow-sm shadow-emerald-600/20",
          else:
            "border-zinc-200 bg-white text-zinc-600 hover:border-emerald-300 hover:text-emerald-700 dark:border-white/10 dark:bg-white/[0.03] dark:text-zinc-300 dark:hover:border-emerald-400/40 dark:hover:text-emerald-300"
        )
      ]}
    >
      <span class="truncate">{bucket_label(@bucket)}</span>
      <span class={[
        "rounded-full px-2 py-0.5 text-xs font-semibold",
        if(@selected_bucket == @bucket,
          do: "bg-white/20 text-white",
          else: "bg-zinc-100 text-zinc-500 dark:bg-white/10 dark:text-zinc-300"
        )
      ]}>
        {if @count > 99, do: "99+", else: @count}
      </span>
    </.link>
    """
  end

  attr :program, :map, required: true

  defp program_card(assigns) do
    ~H"""
    <article class="grid gap-3 px-3 py-3 transition hover:bg-zinc-50/80 dark:hover:bg-white/[0.025] sm:px-4 lg:grid-cols-[minmax(0,1fr)_16rem]">
      <div class="min-w-0 space-y-3">
        <div class="flex flex-col gap-3 sm:flex-row sm:items-start sm:justify-between">
          <div class="min-w-0">
            <div class="flex flex-wrap gap-2">
              <span class="badge badge-info badge-sm">{@program.program_family_label}</span>
              <span class="badge badge-outline badge-sm">{@program.program_type_label}</span>
            </div>
            <h3 class="mt-2 text-base font-semibold leading-6 text-base-content">
              {@program.name}
            </h3>
            <p class="mt-1 text-sm leading-5 text-base-content/60">
              {@program.description || "No description yet."}
            </p>
            <p :if={@program.owner_team_member} class="mt-1 text-xs text-base-content/40">
              Owner {@program.owner_team_member.display_name}
            </p>
          </div>

          <div class="flex shrink-0 flex-wrap gap-2 sm:justify-end">
            <.status_badge status={@program.status_variant}>
              {@program.status_label}
            </.status_badge>
            <.status_badge status={@program.health_variant}>
              {@program.health_label}
            </.status_badge>
          </div>
        </div>

        <div class="grid gap-2 text-sm sm:grid-cols-2 xl:grid-cols-4">
          <.program_fact label="Findings" value={"#{@program.finding_count} total"} />
          <.program_fact label="Review" value={"#{@program.review_finding_count} waiting"} />
          <.program_fact label="Promoted" value={"#{@program.promoted_finding_count} promoted"} />
          <.program_fact label="Last Run" value={format_datetime(@program.last_run_at)} />
        </div>

        <p class="text-sm leading-6 text-base-content/60">
          {@program.health_note}
        </p>
      </div>

      <div class="flex flex-col gap-2 border-t border-zinc-200 pt-3 dark:border-white/10 lg:border-l lg:border-t-0 lg:pl-4 lg:pt-0">
        <.button
          :if={@program.runnable}
          id={"launch-program-#{@program.id}"}
          phx-click="launch_run"
          phx-value-id={@program.id}
          class="px-3 py-2 text-sm"
          variant="primary"
        >
          Launch Run
        </.button>
        <.link
          navigate={
            ~p"/acquisition/findings?family=#{@program.program_family}&program_id=#{@program.id}"
          }
          class="btn btn-sm btn-ghost"
        >
          Open Queue
        </.link>
        <.link
          :if={@program.latest_run_id}
          navigate={~p"/console/agents/runs/#{@program.latest_run_id}"}
          class="btn btn-sm btn-ghost"
        >
          Open Run
        </.link>
      </div>
    </article>
    """
  end

  attr :label, :string, required: true
  attr :value, :string, required: true

  defp registry_count(assigns) do
    ~H"""
    <div class="rounded-md border border-base-content/10 bg-base-200/70 px-2.5 py-2">
      <p class="text-[10px] font-semibold uppercase tracking-[0.14em] text-base-content/45">
        {@label}
      </p>
      <p class="mt-0.5 text-sm font-semibold tabular-nums text-base-content">{@value}</p>
    </div>
    """
  end

  defp program_fact(assigns) do
    ~H"""
    <div class="rounded-md border border-base-content/10 bg-base-200/60 px-3 py-2">
      <p class="text-[11px] font-semibold uppercase tracking-[0.14em] text-base-content/45">
        {@label}
      </p>
      <p class="mt-1 truncate font-medium text-base-content">{@value}</p>
    </div>
    """
  end

  defp refresh_programs(socket) do
    programs = list_programs(socket.assigns.current_user)

    socket
    |> assign(:program_counts, program_counts(programs))
    |> assign(:programs, bucket_programs(programs, socket.assigns.selected_bucket))
  end

  defp list_programs(actor) do
    case Acquisition.list_console_programs(actor: actor) do
      {:ok, programs} -> programs
      {:error, _} -> []
    end
  end

  defp program_counts(programs) do
    %{
      total: length(programs),
      healthy: Enum.count(programs, &(&1.health_status in [:healthy, :running])),
      attention:
        Enum.count(
          programs,
          &(&1.health_status in [:failing, :stale, :noisy, :cancelled])
        ),
      runnable: Enum.count(programs, & &1.runnable),
      ready: Enum.count(programs, & &1.runnable),
      all: length(programs)
    }
  end

  defp empty_counts, do: %{total: 0, healthy: 0, attention: 0, runnable: 0, ready: 0, all: 0}

  defp bucket_programs(programs, bucket) do
    programs
    |> Enum.filter(&program_in_bucket?(&1, bucket))
    |> Enum.take(@program_limit)
  end

  defp program_in_bucket?(program, :ready), do: program.runnable

  defp program_in_bucket?(program, :attention),
    do: program.health_status in [:failing, :stale, :noisy, :cancelled]

  defp program_in_bucket?(_program, :all), do: true

  defp bucket_count(counts, :attention), do: counts.attention
  defp bucket_count(counts, bucket), do: Map.fetch!(counts, bucket)

  defp bucket_label(:ready), do: "Ready"
  defp bucket_label(:attention), do: "Attention"
  defp bucket_label(:all), do: "All"

  defp parse_bucket(bucket) when is_binary(bucket) do
    bucket
    |> String.to_existing_atom()
    |> then(fn bucket -> if bucket in @buckets, do: bucket, else: :all end)
  rescue
    ArgumentError -> :all
  end

  defp parse_bucket(_bucket), do: :all
end
