defmodule GnomeGardenWeb.Agents.ProcurementTargetingLive do
  use GnomeGardenWeb, :live_view

  alias GnomeGarden.Commercial.CompanyProfileLearning

  @modes [:industrial_core, :industrial_plus_software, :broad_software]

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      GnomeGardenWeb.Endpoint.subscribe("company_profile:updated")
      GnomeGardenWeb.Endpoint.subscribe("company_profile:created")
    end

    {:ok,
     socket
     |> stream_configure(:learned_exclude, dom_id: &"learned-exclude-#{slugify_term(&1)}")
     |> stream_configure(:feedback_history, dom_id: &history_dom_id/1)
     |> assign(:page_title, "Procurement Targeting")
     |> assign(:selected_mode, :industrial_plus_software)
     |> assign(:modes, @modes)
     |> assign(:snapshot, nil)
     |> assign(:learned_exclude_count, 0)
     |> assign(:history_count, 0)
     |> assign(:manual_form, to_form(%{"terms" => ""}, as: :manual_exclude))
     |> stream(:learned_exclude, [], reset: true)
     |> stream(:feedback_history, [], reset: true)}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    mode = parse_mode(params["mode"])

    {:noreply,
     socket
     |> assign(:selected_mode, mode)
     |> assign(:manual_form, to_form(%{"terms" => ""}, as: :manual_exclude))
     |> load_snapshot()}
  end

  @impl true
  def handle_info(%{topic: "company_profile:" <> _}, socket) do
    {:noreply, load_snapshot(socket)}
  end

  @impl true
  def handle_event("add_excludes", %{"manual_exclude" => %{"terms" => terms}}, socket) do
    case CompanyProfileLearning.add_learned_excludes(
           company_profile_mode: Atom.to_string(socket.assigns.selected_mode),
           exclude_terms: terms,
           reason: "Manual procurement targeting adjustment"
         ) do
      {:ok, _result} ->
        {:noreply,
         socket
         |> assign(:manual_form, to_form(%{"terms" => ""}, as: :manual_exclude))
         |> load_snapshot()
         |> put_flash(:info, "Updated learned exclusions for this procurement mode.")}

      {:error, error} ->
        {:noreply, put_flash(socket, :error, "Could not update targeting: #{inspect(error)}")}
    end
  end

  def handle_event("remove_exclude", %{"term" => term}, socket) do
    case CompanyProfileLearning.remove_learned_exclude(
           company_profile_mode: Atom.to_string(socket.assigns.selected_mode),
           exclude_term: term
         ) do
      {:ok, _result} ->
        {:noreply,
         socket
         |> load_snapshot()
         |> put_flash(:info, "Removed learned exclusion: #{term}")}

      {:error, error} ->
        {:noreply, put_flash(socket, :error, "Could not remove exclusion: #{inspect(error)}")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.page class="pb-8">
      <.page_header eyebrow="Procurement">
        Targeting Controls
        <:subtitle>
          Review what the bid queue has learned, add manual suppressions, and remove bad exclusions before they distort discovery.
        </:subtitle>
        <:actions>
          <.button navigate={~p"/acquisition/findings?family=procurement"}>
            Procurement Intake
          </.button>
          <.button navigate={~p"/acquisition/sources"}>
            Sources
          </.button>
        </:actions>
      </.page_header>

      <div class="grid gap-4 md:grid-cols-3">
        <.stat_card
          title="Mode"
          value={mode_label(@selected_mode)}
          description="Current procurement scoring lane."
          icon="hero-funnel"
        />
        <.stat_card
          title="Learned Excludes"
          value={Integer.to_string(@learned_exclude_count)}
          description="Keywords added from operator feedback and manual tuning."
          icon="hero-no-symbol"
          accent="amber"
        />
        <.stat_card
          title="Recent Feedback"
          value={Integer.to_string(@history_count)}
          description="Latest targeting adjustments for this mode."
          icon="hero-clock"
          accent="sky"
        />
      </div>

      <.section
        title="Profile Mode"
        description="Switch between the same company profile modes that drive bid scoring and discovery prompts."
        compact
      >
        <div class="flex flex-wrap items-center gap-2">
          <.mode_link :for={mode <- @modes} mode={mode} selected_mode={@selected_mode} />
        </div>
      </.section>

      <div class="grid gap-6 xl:grid-cols-[1.1fr_0.9fr]">
        <.section
          title="Learned Suppressions"
          description="These terms are applied on top of the fixed profile excludes for the selected mode."
          compact
        >
          <.form for={@manual_form} id="procurement-targeting-form" phx-submit="add_excludes">
            <div class="space-y-3">
              <.input
                field={@manual_form[:terms]}
                label="Add keywords to suppress"
                type="text"
                placeholder="e.g. cctv, video surveillance, security camera"
              />
              <div class="flex justify-end">
                <.button type="submit" variant="primary">
                  Add Excludes
                </.button>
              </div>
            </div>
          </.form>

          <div class="mt-6 space-y-4">
            <div>
              <h3 class="text-sm font-semibold text-base-content">Fixed Excludes</h3>
              <div class="mt-2 flex flex-wrap gap-2">
                <span
                  :for={term <- @snapshot.fixed_exclude}
                  class="badge badge-outline badge-sm border-zinc-300 text-zinc-600 dark:border-white/15 dark:text-zinc-300"
                >
                  {term}
                </span>
                <span :if={@snapshot.fixed_exclude == []} class="text-sm text-zinc-500">
                  No fixed excludes.
                </span>
              </div>
            </div>

            <div>
              <h3 class="text-sm font-semibold text-base-content">Learned Excludes</h3>
              <div id="learned-exclude" phx-update="stream" class="mt-2 flex flex-wrap gap-2">
                <div :for={{dom_id, term} <- @streams.learned_exclude} id={dom_id}>
                  <button
                    type="button"
                    phx-click="remove_exclude"
                    phx-value-term={term}
                    class="inline-flex items-center gap-2 rounded-full border border-amber-300 bg-amber-50 px-3 py-1 text-sm text-amber-900 transition hover:border-amber-400 hover:bg-amber-100 dark:border-amber-400/30 dark:bg-amber-400/10 dark:text-amber-100"
                  >
                    <span>{term}</span>
                    <.icon name="hero-x-mark" class="size-4" />
                  </button>
                </div>
                <span
                  :if={@learned_exclude_count == 0}
                  class="text-sm text-zinc-500"
                >
                  No learned excludes yet for this mode.
                </span>
              </div>
            </div>

            <div>
              <h3 class="text-sm font-semibold text-base-content">Include Keywords</h3>
              <div class="mt-2 flex flex-wrap gap-2">
                <span
                  :for={term <- @snapshot.include_keywords}
                  class="badge badge-success badge-sm"
                >
                  {term}
                </span>
                <span :if={@snapshot.include_keywords == []} class="text-sm text-zinc-500">
                  No include keywords.
                </span>
              </div>
            </div>
          </div>
        </.section>

        <.section
          title="Recent Feedback"
          description="Latest operator adjustments that shaped the selected procurement mode."
          compact
        >
          <div id="feedback-history" phx-update="stream" class="space-y-3">
            <div
              :for={{dom_id, entry} <- @streams.feedback_history}
              id={dom_id}
              class="rounded-2xl border border-zinc-200 bg-zinc-50/70 px-4 py-4 dark:border-white/10 dark:bg-white/[0.03]"
            >
              <div class="flex flex-wrap items-center gap-2">
                <span class="badge badge-outline badge-sm">
                  {feedback_scope_label(entry["feedback_scope"])}
                </span>
                <span class="text-xs text-zinc-500">{entry["recorded_at"] || "-"}</span>
              </div>
              <p class="mt-2 text-sm text-base-content/80">
                {entry["reason"] || "No reason recorded."}
              </p>
              <div class="mt-3 flex flex-wrap gap-2">
                <span
                  :for={term <- List.wrap(entry["exclude_terms"])}
                  class="badge badge-error badge-sm"
                >
                  {term}
                </span>
              </div>
            </div>
            <div :if={@history_count == 0} class="text-sm text-zinc-500">
              No feedback recorded yet for this mode.
            </div>
          </div>
        </.section>
      </div>
    </.page>
    """
  end

  attr :mode, :atom, required: true
  attr :selected_mode, :atom, required: true

  defp mode_link(assigns) do
    selected? = assigns.mode == assigns.selected_mode
    assigns = assign(assigns, :selected?, selected?)

    ~H"""
    <.link
      patch={~p"/procurement/targeting?mode=#{@mode}"}
      class={[
        "inline-flex items-center rounded-full border px-3 py-1.5 text-sm font-medium transition",
        if(
          @selected?,
          do: "border-emerald-500 bg-emerald-500 text-white shadow-sm shadow-emerald-500/25",
          else:
            "border-zinc-200 bg-white text-zinc-600 hover:border-emerald-300 hover:text-emerald-600 dark:border-white/10 dark:bg-white/[0.03] dark:text-zinc-300 dark:hover:border-emerald-400/40 dark:hover:text-emerald-300"
        )
      ]}
    >
      {mode_label(@mode)}
    </.link>
    """
  end

  defp load_snapshot(socket) do
    case CompanyProfileLearning.mode_snapshot(mode: Atom.to_string(socket.assigns.selected_mode)) do
      {:ok, snapshot} ->
        socket
        |> assign(:snapshot, snapshot)
        |> assign(:learned_exclude_count, length(snapshot.learned_exclude))
        |> assign(:history_count, length(snapshot.feedback_history))
        |> stream(:learned_exclude, snapshot.learned_exclude, reset: true)
        |> stream(:feedback_history, snapshot.feedback_history, reset: true)

      {:error, error} ->
        put_flash(socket, :error, "Could not load targeting controls: #{inspect(error)}")
    end
  end

  defp parse_mode(nil), do: :industrial_plus_software

  defp parse_mode(mode) when is_binary(mode) do
    mode
    |> String.to_existing_atom()
    |> then(fn parsed -> if parsed in @modes, do: parsed, else: :industrial_plus_software end)
  rescue
    ArgumentError -> :industrial_plus_software
  end

  defp mode_label(:industrial_core), do: "Industrial Core"
  defp mode_label(:industrial_plus_software), do: "Industrial + Software"
  defp mode_label(:broad_software), do: "Broad Software"

  defp feedback_scope_label("out_of_scope"), do: "Out of Scope"
  defp feedback_scope_label("not_targeting_right_now"), do: "Not Targeting Now"
  defp feedback_scope_label("manual"), do: "Manual Add"
  defp feedback_scope_label("manual_remove"), do: "Manual Remove"
  defp feedback_scope_label(nil), do: "Feedback"
  defp feedback_scope_label(value), do: value |> to_string() |> String.replace("_", " ")

  defp slugify_term(term) do
    term
    |> to_string()
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/u, "-")
    |> String.trim("-")
  end

  defp history_dom_id(entry) do
    scope = Map.get(entry, "feedback_scope", "entry") |> slugify_term()
    recorded_at = Map.get(entry, "recorded_at", "unknown") |> slugify_term()
    terms = Map.get(entry, "exclude_terms", []) |> List.wrap() |> Enum.join("-") |> slugify_term()

    "feedback-history-#{scope}-#{recorded_at}-#{terms}"
  end
end
