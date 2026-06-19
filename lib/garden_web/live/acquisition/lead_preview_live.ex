defmodule GnomeGardenWeb.Acquisition.LeadPreviewLive do
  @moduledoc """
  Operator console for the Exa lead-preview → promote loop.

  Running a preview is a deliberate, cheap dry-run (Exa search only). It creates
  nothing. The operator reviews the ranked, classified candidates and promotes
  the ones worth pursuing — which is the only step that writes to the system,
  routed by the `LeadDedup` classification. Signal pages whose domain isn't the
  prospect surface as "needs enrichment" so the deferred pile is visible.
  """

  use GnomeGardenWeb, :live_view

  import GnomeGardenWeb.Finance.Helpers, only: [format_atom: 1]

  alias GnomeGarden.Acquisition.{LeadPreview, LeadPromote}
  alias GnomeGarden.Commercial

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Lead Preview")
     |> assign(:form, default_form())
     |> assign(:programs, programs(socket.assigns.current_user))
     |> assign(:program_id, "")
     |> assign(:preview, nil)
     |> assign(:candidates, [])
     |> assign(:running?, false)}
  end

  @impl true
  def handle_event("run_preview", %{"preview" => params}, socket) do
    opts =
      [
        industries: split(params["industries"]),
        regions: split(params["regions"]),
        search_terms: split(params["terms"]),
        max_queries: to_int(params["max_queries"], 6),
        spend_ceiling: to_float(params["ceiling"], 0.15),
        actor: socket.assigns.current_user
      ]
      |> maybe_put(:start_published_date, blank_to_nil(params["since"]))

    {:ok, preview} = LeadPreview.run(opts)

    candidates =
      preview.candidates
      |> Enum.with_index()
      |> Enum.map(fn {candidate, index} ->
        candidate
        |> Map.put(:index, index)
        |> Map.put(:route, LeadPromote.route(candidate))
        |> Map.put(:status, :pending)
      end)

    {:noreply,
     socket
     |> assign(:form, params)
     |> assign(:program_id, params["program_id"] || "")
     |> assign(:preview, preview)
     |> assign(:candidates, candidates)
     |> maybe_warn_failures(preview)}
  end

  @impl true
  def handle_event("promote", %{"index" => index}, socket) do
    with {idx, _} <- Integer.parse(to_string(index)),
         candidate when not is_nil(candidate) <- Enum.find(socket.assigns.candidates, &(&1.index == idx)) do
      {status, kind, message} = promote_outcome(candidate, socket)

      {:noreply,
       socket
       |> assign(:candidates, update_status(socket.assigns.candidates, idx, status))
       |> put_flash(kind, message)}
    else
      _ ->
        {:noreply, put_flash(socket, :error, "That candidate is no longer available — re-run the preview.")}
    end
  end

  @impl true
  def handle_event("promote_keepers", _params, socket) do
    program_id = blank_to_nil(socket.assigns.program_id)
    actor = socket.assigns.current_user

    candidates =
      Enum.map(socket.assigns.candidates, fn candidate ->
        if candidate.route == :promote and candidate.status != :promoted do
          status =
            case LeadPromote.promote(candidate, actor: actor, discovery_program_id: program_id) do
              {:promoted, _} -> :promoted
              {:needs_enrichment, _} -> :needs_enrichment
              {:skipped, _} -> :skipped
            end

          %{candidate | status: status}
        else
          candidate
        end
      end)

    promoted = Enum.count(candidates, &(&1.status == :promoted))
    {:noreply, socket |> assign(:candidates, candidates) |> put_flash(:info, "Promoted #{promoted} candidate(s) to the review queue.")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.page class="pb-8">
      <.page_header eyebrow="Acquisition">
        Lead Preview
        <:subtitle>
          Dry-run Exa lead discovery, classified against what we already have. Preview creates
          nothing — promotion is the explicit step into the review queue.
        </:subtitle>
      </.page_header>

      <.section title="Search" description="Signal-shaped queries are built from these inputs (the word 'automation' is intentionally avoided).">
        <form id="lead-preview-form" phx-submit="run_preview" class="grid grid-cols-1 gap-x-6 gap-y-4 sm:grid-cols-6">
          <.preview_input name="industries" label="Industries" value={@form["industries"]} placeholder="food processing, packaging" span="3" />
          <.preview_input name="regions" label="Regions" value={@form["regions"]} placeholder="orange county, southern california" span="3" />
          <.preview_input name="terms" label="Extra terms (optional)" value={@form["terms"]} placeholder="comma-separated" span="6" />
          <.preview_input name="since" label="Published since (optional)" value={@form["since"]} placeholder="2026-01-01" span="2" />
          <.preview_input name="max_queries" label="Max queries" value={@form["max_queries"] || "6"} placeholder="6" span="2" />
          <.preview_input name="ceiling" label="Spend ceiling ($)" value={@form["ceiling"] || "0.15"} placeholder="0.15" span="2" />

          <div class="sm:col-span-4">
            <label class="block text-sm/6 font-medium text-gray-900 dark:text-white">Promote into program (optional)</label>
            <select name="preview[program_id]" class="mt-2 block w-full rounded-md bg-white px-3 py-1.5 text-base text-gray-900 outline-1 -outline-offset-1 outline-gray-300 sm:text-sm/6 dark:bg-white/5 dark:text-white">
              <option value="">— none (ad-hoc) —</option>
              <option :for={p <- @programs} value={p.id} selected={@program_id == p.id}>{p.name}</option>
            </select>
          </div>

          <div class="sm:col-span-2 flex items-end">
            <.button type="submit" variant="primary">
              <.icon name="hero-magnifying-glass" class="size-4" /> Run preview
            </.button>
          </div>
        </form>
      </.section>

      <div :if={@preview}>
        <div class="grid gap-2 sm:grid-cols-4">
          <.stat_card title="Candidates" value={"#{@preview.candidate_count}"} description={"#{@preview.queries_run} queries"} icon="hero-rectangle-stack" />
          <.stat_card title="Promotable" value={"#{count(@candidates, :promote)}"} description="company / known-org" icon="hero-check-circle" accent="emerald" />
          <.stat_card title="Needs enrichment" value={"#{count(@candidates, :needs_enrichment)}"} description="signal pages" icon="hero-sparkles" accent="amber" />
          <.stat_card title="Cost" value={"$#{@preview.total_cost}"} description="this run" icon="hero-banknotes" accent="sky" />
        </div>

        <.section title="Promotable" description="Company pages and known-org signals — promote into the review queue.">
          <:actions>
            <.button :if={count(@candidates, :promote) > 0} phx-click="promote_keepers" variant="primary">
              Promote all promotable
            </.button>
          </:actions>
          <div class="space-y-2">
            <.candidate_row :for={c <- by_route(@candidates, :promote)} candidate={c} promotable />
            <p :if={by_route(@candidates, :promote) == []} class="text-sm text-base-content/60">Nothing directly promotable in this run.</p>
          </div>
        </.section>

        <.section title="Needs enrichment" description="Signal pages (job boards, agendas, press) — the domain isn't the prospect; the company must be extracted first.">
          <div class="space-y-2">
            <.candidate_row :for={c <- by_route(@candidates, :needs_enrichment)} candidate={c} />
            <p :if={by_route(@candidates, :needs_enrichment) == []} class="text-sm text-base-content/60">None.</p>
          </div>
        </.section>

        <.section title="Suppressed" description="Already in the system, a configured source, or a saved bid — context, not new leads.">
          <div class="space-y-2">
            <.candidate_row :for={c <- by_route(@candidates, :skip)} candidate={c} />
            <p :if={by_route(@candidates, :skip) == []} class="text-sm text-base-content/60">None.</p>
          </div>
        </.section>
      </div>
    </.page>
    """
  end

  attr :name, :string, required: true
  attr :label, :string, required: true
  attr :value, :any, default: nil
  attr :placeholder, :string, default: nil
  attr :span, :string, default: "3"

  defp preview_input(assigns) do
    ~H"""
    <div class={"sm:col-span-#{@span}"}>
      <label class="block text-sm/6 font-medium text-gray-900 dark:text-white">{@label}</label>
      <input
        type="text"
        name={"preview[#{@name}]"}
        value={@value}
        placeholder={@placeholder}
        class="mt-2 block w-full rounded-md bg-white px-3 py-1.5 text-base text-gray-900 outline-1 -outline-offset-1 outline-gray-300 placeholder:text-gray-400 focus:outline-2 focus:-outline-offset-2 focus:outline-emerald-600 sm:text-sm/6 dark:bg-white/5 dark:text-white dark:outline-white/10"
      />
    </div>
    """
  end

  attr :candidate, :map, required: true
  attr :promotable, :boolean, default: false

  defp candidate_row(assigns) do
    ~H"""
    <div class="flex items-start justify-between gap-3 rounded-lg border border-base-content/10 bg-base-200 px-3 py-3">
      <div class="min-w-0">
        <p class="truncate font-medium text-base-content">{@candidate.title || "(no title)"}</p>
        <a href={@candidate.url} target="_blank" class="truncate text-xs text-emerald-600 hover:underline">{@candidate.url}</a>
        <p class="mt-1 text-xs text-base-content/60">
          [{@candidate.type}/{format_atom(@candidate.dedupe.context)}] — {@candidate.dedupe.recommendation}
        </p>
      </div>
      <div class="flex shrink-0 items-center gap-2">
        <.status_badge :if={@candidate.status != :pending} status={status_variant(@candidate.status)}>
          {format_atom(@candidate.status)}
        </.status_badge>
        <.button :if={@promotable and @candidate.status != :promoted} phx-click="promote" phx-value-index={@candidate.index} variant="primary">
          Promote
        </.button>
      </div>
    </div>
    """
  end

  defp status_variant(:promoted), do: :success
  defp status_variant(:needs_enrichment), do: :warning
  defp status_variant(_), do: :default

  defp by_route(candidates, route), do: Enum.filter(candidates, &(&1.route == route))
  defp count(candidates, route), do: Enum.count(candidates, &(&1.route == route))

  defp update_status(candidates, index, status) do
    Enum.map(candidates, fn c -> if c.index == index, do: %{c | status: status}, else: c end)
  end

  defp maybe_warn_failures(socket, %{failed_queries: failed}) when failed > 0 do
    sample = socket.assigns.preview.errors |> List.first() |> inspect()
    put_flash(socket, :error, "#{failed} search query(ies) failed (e.g. #{sample}) — results may be incomplete.")
  end

  defp maybe_warn_failures(socket, _preview), do: socket

  defp promote_outcome(candidate, socket) do
    case LeadPromote.promote(candidate,
           actor: socket.assigns.current_user,
           discovery_program_id: blank_to_nil(socket.assigns.program_id)
         ) do
      {:promoted, _record} -> {:promoted, :info, "Promoted to the review queue."}
      {:needs_enrichment, _} -> {:needs_enrichment, :error, "Needs enrichment — the page domain isn't the prospect."}
      {:skipped, %{reason: reason}} -> {:skipped, :error, "Skipped: #{reason}"}
    end
  end

  defp programs(actor) do
    case Commercial.list_active_discovery_programs(actor: actor) do
      {:ok, programs} -> programs
      _ -> []
    end
  end

  defp default_form, do: %{"industries" => "", "regions" => "", "terms" => "", "since" => "", "max_queries" => "6", "ceiling" => "0.15", "program_id" => ""}

  defp split(nil), do: []
  defp split(value), do: value |> String.split(",") |> Enum.map(&String.trim/1) |> Enum.reject(&(&1 == ""))

  defp to_int(value, default) do
    case Integer.parse(to_string(value)) do
      {int, _} -> int
      _ -> default
    end
  end

  defp to_float(value, default) do
    case Float.parse(to_string(value)) do
      {float, _} -> float
      _ -> default
    end
  end

  defp blank_to_nil(nil), do: nil
  defp blank_to_nil(""), do: nil
  defp blank_to_nil(value), do: value

  defp maybe_put(opts, _key, nil), do: opts
  defp maybe_put(opts, key, value), do: Keyword.put(opts, key, value)
end
