defmodule GnomeGardenWeb.Acquisition.SourceLive.Configure do
  use GnomeGardenWeb, :live_view

  import GnomeGardenWeb.Execution.Helpers, only: [format_atom: 1]

  alias GnomeGarden.Acquisition
  alias GnomeGarden.Agents.Procurement.SourceConfigurator
  alias GnomeGarden.Procurement

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    if connected?(socket) do
      GnomeGardenWeb.Endpoint.subscribe("procurement_source_search_filter:created")
      GnomeGardenWeb.Endpoint.subscribe("procurement_source_search_filter:updated")
      GnomeGardenWeb.Endpoint.subscribe("procurement_source_search_filter:destroyed")
    end

    case load_source(id, socket.assigns.current_user) do
      {:ok, source} ->
        {:ok,
         socket
         |> assign(:page_title, "Configure Source")
         |> assign(:source, source)
         |> assign_search_filters()
         |> assign_search_filter_form(%{})
         |> assign_form(config_params(source))}

      {:error, error} ->
        {:ok,
         socket
         |> put_flash(:error, "Could not load source: #{inspect(error)}")
         |> push_navigate(to: ~p"/acquisition/sources")}
    end
  end

  @impl true
  def handle_event("validate", %{"config" => params}, socket) do
    {:noreply, assign_form(socket, params)}
  end

  @impl true
  def handle_event("save", %{"config" => params}, socket) do
    params =
      params
      |> Map.put("procurement_source_id", socket.assigns.source.procurement_source_id)
      |> compact_config_params()

    case Procurement.save_source_config(params, actor: socket.assigns.current_user) do
      {:ok, _source} ->
        {:noreply,
         socket
         |> put_flash(:info, "Source configuration saved.")
         |> push_navigate(to: ~p"/acquisition/sources")}

      {:error, error} ->
        {:noreply,
         socket
         |> assign_form(params)
         |> put_flash(:error, "Could not save source configuration: #{inspect(error)}")}
    end
  end

  @impl true
  def handle_event("start_discovery", _params, socket) do
    source = socket.assigns.source.procurement_source

    case SourceConfigurator.discover_source(source, actor: socket.assigns.current_user) do
      {:ok, %{mode: :started}} ->
        {:noreply,
         socket
         |> put_flash(:info, "Discovery started for #{source.name}.")
         |> push_navigate(to: ~p"/acquisition/sources")}

      {:ok, %{mode: :already_pending}} ->
        {:noreply,
         socket
         |> put_flash(:info, "#{source.name} is already queued for discovery.")
         |> push_navigate(to: ~p"/acquisition/sources")}

      {:error, error} ->
        {:noreply, put_flash(socket, :error, "Could not start discovery: #{inspect(error)}")}
    end
  end

  @impl true
  def handle_event("add_search_filter", %{"search_filter" => params}, socket) do
    source = socket.assigns.source.procurement_source
    attrs = search_filter_attrs(source, params)

    case Procurement.create_source_search_filter(attrs, actor: socket.assigns.current_user) do
      {:ok, _filter} ->
        {:noreply,
         socket
         |> assign_search_filters()
         |> assign_search_filter_form(%{})
         |> put_flash(:info, "Search filter added.")}

      {:error, error} ->
        {:noreply,
         socket
         |> assign_search_filter_form(params)
         |> put_flash(:error, "Could not add search filter: #{inspect(error)}")}
    end
  end

  @impl true
  def handle_event("toggle_search_filter", %{"id" => id}, socket) do
    with {:ok, filter} <-
           Procurement.get_source_search_filter(id, actor: socket.assigns.current_user),
         {:ok, _filter} <-
           Procurement.update_source_search_filter(
             filter,
             %{enabled: !filter.enabled},
             actor: socket.assigns.current_user
           ) do
      {:noreply, assign_search_filters(socket)}
    else
      error ->
        {:noreply, put_flash(socket, :error, "Could not update search filter: #{inspect(error)}")}
    end
  end

  @impl true
  def handle_event("disable_noisy_search_filter", %{"id" => id}, socket) do
    with {:ok, filter} <-
           Procurement.get_source_search_filter(id, actor: socket.assigns.current_user),
         {:ok, _filter} <-
           Procurement.disable_noisy_source_search_filter(filter,
             actor: socket.assigns.current_user
           ) do
      {:noreply,
       socket
       |> assign_search_filters()
       |> put_flash(:info, "Search filter disabled as noisy.")}
    else
      error ->
        {:noreply,
         put_flash(socket, :error, "Could not disable search filter: #{inspect(error)}")}
    end
  end

  @impl true
  def handle_event("keep_searching_filter", %{"id" => id}, socket) do
    with {:ok, filter} <-
           Procurement.get_source_search_filter(id, actor: socket.assigns.current_user),
         {:ok, _filter} <-
           Procurement.keep_searching_source_search_filter(filter,
             actor: socket.assigns.current_user
           ) do
      {:noreply,
       socket
       |> assign_search_filters()
       |> put_flash(:info, "Search filter kept for the next run.")}
    else
      error ->
        {:noreply, put_flash(socket, :error, "Could not keep search filter: #{inspect(error)}")}
    end
  end

  @impl true
  def handle_event("delete_search_filter", %{"id" => id}, socket) do
    with {:ok, filter} <-
           Procurement.get_source_search_filter(id, actor: socket.assigns.current_user),
         {:ok, _filter} <-
           Procurement.delete_source_search_filter(filter, actor: socket.assigns.current_user) do
      {:noreply, assign_search_filters(socket)}
    else
      error ->
        {:noreply, put_flash(socket, :error, "Could not delete search filter: #{inspect(error)}")}
    end
  end

  @impl true
  def handle_info(%{topic: "procurement_source_search_filter:" <> _event}, socket) do
    {:noreply, assign_search_filters(socket)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.page class="pb-8">
      <.page_header>
        Configure Source
        <:subtitle>
          Save the selectors needed for deterministic scans, or start browser discovery for this source.
        </:subtitle>
        <:actions>
          <.button navigate={~p"/acquisition/sources"}>
            Sources
          </.button>
        </:actions>
      </.page_header>

      <div class="grid gap-4 lg:grid-cols-[minmax(0,1fr)_22rem]">
        <.section title={@source.name} description={@source.url}>
          <div class="mb-4 rounded-lg border border-info/20 bg-info/10 p-3 text-sm text-base-content">
            <div class="flex flex-col gap-3 sm:flex-row sm:items-start sm:justify-between">
              <div class="space-y-1">
                <p class="font-semibold">If you do not know these selectors, use discovery first.</p>
                <p class="leading-5 text-base-content/70">
                  Selectors tell the scanner which parts of the portal are bid listings. For example,
                  <code class="rounded bg-base-100 px-1 py-0.5 text-xs">.bid-row</code>
                  could mean one listing, and
                  <code class="rounded bg-base-100 px-1 py-0.5 text-xs">.bid-title</code>
                  could mean the title inside it. Browser discovery is the safer path when nobody has inspected this portal yet.
                </p>
              </div>
              <div class="flex shrink-0 flex-wrap gap-2">
                <.button
                  :if={discoverable?(@source.procurement_source)}
                  type="button"
                  variant="primary"
                  phx-click="start_discovery"
                  phx-disable-with="Starting..."
                >
                  Start Discovery
                </.button>
                <.link
                  href={@source.url}
                  target="_blank"
                  class="inline-flex items-center justify-center rounded-md border border-zinc-300 bg-white px-3 py-2 text-sm font-semibold text-zinc-800 shadow-sm transition hover:border-zinc-400 hover:bg-zinc-50 dark:border-white/10 dark:bg-white/[0.04] dark:text-white dark:hover:border-white/20 dark:hover:bg-white/[0.08]"
                >
                  Open Source
                </.link>
              </div>
            </div>
          </div>

          <.form for={@form} id="source-config-form" phx-change="validate" phx-submit="save">
            <div class="grid gap-4 md:grid-cols-2">
              <.config_input
                field={@form[:listing_url]}
                type="url"
                label="Listing URL"
                hint="The exact page where bid listings appear. This can be different from the portal home page."
                required
              />
              <.config_input
                field={@form[:listing_selector]}
                type="text"
                label="Listing Selector"
                hint="The repeated wrapper for one bid or opportunity row. Example: .bid-row, tr.notice, .solicitation-card."
                required
              />
              <.config_input
                field={@form[:title_selector]}
                type="text"
                label="Title Selector"
                hint="Inside each listing, the element containing the bid title. Example: .title, h3 a, td:nth-child(2)."
                required
              />
              <.config_input
                field={@form[:link_selector]}
                type="text"
                label="Link Selector"
                hint="Inside each listing, the link to the bid detail page. Often just a or .title a."
              />
              <.config_input
                field={@form[:date_selector]}
                type="text"
                label="Date Selector"
                hint="Optional due-date or posted-date element inside the listing row."
              />
              <.config_input
                field={@form[:agency_selector]}
                type="text"
                label="Agency Selector"
                hint="Optional agency or buyer name inside the listing row."
              />
              <.config_input
                field={@form[:description_selector]}
                type="text"
                label="Description Selector"
                hint="Optional short description or scope text inside the listing row."
              />
              <.config_input
                field={@form[:search_selector]}
                type="text"
                label="Search Selector"
                hint="Optional search box selector if this source needs a keyword search before listings appear."
              />
              <.input
                field={@form[:pagination_type]}
                type="select"
                label="Pagination Type"
                options={[
                  {"None", "none"},
                  {"Numbered", "numbered"},
                  {"Load More", "load_more"},
                  {"Infinite", "infinite"}
                ]}
              />
              <.input
                field={@form[:pagination_selector]}
                type="text"
                label="Pagination Selector"
                placeholder=".next, button.load-more"
              />
              <div class="md:col-span-2">
                <.config_input
                  field={@form[:notes]}
                  type="textarea"
                  label="Notes"
                  hint="Capture what you learned about the source, why selectors were chosen, or why discovery is needed."
                />
              </div>
            </div>

            <div class="mt-5 flex flex-col-reverse gap-2 sm:flex-row sm:items-center sm:justify-end">
              <.button type="button" navigate={~p"/acquisition/sources"}>
                Cancel
              </.button>
              <.button type="submit" variant="primary" phx-disable-with="Saving...">
                Save Configuration
              </.button>
            </div>
          </.form>
        </.section>

        <div class="space-y-4">
          <.section title="Source State">
            <div class="space-y-3 text-sm">
              <div class="flex items-center justify-between gap-3">
                <span class="text-base-content/60">Procurement status</span>
                <.status_badge status={procurement_status_variant(@source.procurement_source.status)}>
                  {format_atom(@source.procurement_source.status)}
                </.status_badge>
              </div>
              <div class="flex items-center justify-between gap-3">
                <span class="text-base-content/60">Config status</span>
                <.status_badge status={
                  config_status_variant(@source.procurement_source.config_status)
                }>
                  {format_atom(@source.procurement_source.config_status)}
                </.status_badge>
              </div>
              <div class="flex items-center justify-between gap-3">
                <span class="text-base-content/60">Type</span>
                <span class="font-medium">{format_atom(@source.procurement_source.source_type)}</span>
              </div>
              <div class="flex items-center justify-between gap-3">
                <span class="text-base-content/60">Region</span>
                <span class="font-medium">{format_atom(@source.procurement_source.region)}</span>
              </div>
            </div>
          </.section>

          <.section
            :if={sam_gov_source?(@source.procurement_source)}
            title="SAM.gov Search"
            description="NAICS filters control which federal opportunity searches run. Keep the useful ones enabled and remove noise."
          >
            <div class="space-y-4">
              <div
                :if={@search_filters == []}
                class="rounded-lg border border-dashed border-base-content/20 bg-base-200/50 p-3 text-sm text-base-content/65"
              >
                No saved filters yet. The scanner will use the default profile NAICS codes until you add filters here.
              </div>

              <div :if={@search_filters != []} class="space-y-2">
                <div
                  :for={filter <- @search_filters}
                  class={[
                    "rounded-lg border p-3 text-sm",
                    filter.enabled &&
                      "border-emerald-300 bg-emerald-50/80 dark:border-emerald-400/20 dark:bg-emerald-400/10",
                    !filter.enabled &&
                      "border-zinc-200 bg-zinc-50 text-base-content/55 dark:border-white/10 dark:bg-white/[0.03]"
                  ]}
                >
                  <div class="flex items-start justify-between gap-3">
                    <div class="min-w-0">
                      <div class="flex flex-wrap items-center gap-2">
                        <span class="font-semibold text-base-content">{filter.value}</span>
                        <span class="text-xs uppercase tracking-wide text-base-content/50">
                          {format_atom(filter.filter_type)}
                        </span>
                        <.status_badge status={if(filter.enabled, do: :success, else: :default)}>
                          {if(filter.enabled, do: "Enabled", else: "Off")}
                        </.status_badge>
                        <.status_badge status={filter.performance_variant}>
                          {filter.performance_recommendation}
                        </.status_badge>
                      </div>
                      <p :if={filter.label} class="mt-1 text-base-content/70">{filter.label}</p>
                      <p :if={filter.performance_note} class="mt-1 text-xs text-base-content/60">
                        {filter.performance_note}
                      </p>
                      <div class="mt-2 grid grid-cols-2 gap-2 text-xs text-base-content/60 sm:grid-cols-5">
                        <div>
                          <span class="block font-semibold text-base-content">
                            {filter.per_run_limit}
                          </span>
                          per run
                        </div>
                        <div>
                          <span class="block font-semibold text-base-content">
                            {filter.last_returned_count}
                          </span>
                          returned
                        </div>
                        <div>
                          <span class="block font-semibold text-base-content">
                            {filter.last_saved_count}
                          </span>
                          saved
                        </div>
                        <div>
                          <span class="block font-semibold text-base-content">
                            {filter.accepted_feedback_count}
                          </span>
                          accepted
                        </div>
                        <div>
                          <span class="block font-semibold text-base-content">
                            {filter.rejected_feedback_count + filter.suppressed_feedback_count}
                          </span>
                          rejected
                        </div>
                      </div>
                    </div>
                    <div class="flex shrink-0 flex-col gap-1">
                      <.button
                        :if={show_disable_noisy_action?(filter)}
                        type="button"
                        phx-click="disable_noisy_search_filter"
                        phx-value-id={filter.id}
                        variant="primary"
                      >
                        Disable Noisy
                      </.button>
                      <.button
                        :if={show_keep_searching_action?(filter)}
                        type="button"
                        phx-click="keep_searching_filter"
                        phx-value-id={filter.id}
                      >
                        Keep Searching
                      </.button>
                      <.button
                        type="button"
                        phx-click="toggle_search_filter"
                        phx-value-id={filter.id}
                      >
                        {if(filter.enabled, do: "Disable", else: "Enable")}
                      </.button>
                      <.button
                        type="button"
                        phx-click="delete_search_filter"
                        phx-value-id={filter.id}
                      >
                        Remove
                      </.button>
                    </div>
                  </div>
                </div>
              </div>

              <.form
                for={@search_filter_form}
                id="sam-search-filter-form"
                phx-submit="add_search_filter"
                class="space-y-3 rounded-lg border border-base-content/10 bg-base-100/70 p-3"
              >
                <.input
                  field={@search_filter_form[:value]}
                  type="text"
                  label="Add Related NAICS Code"
                  placeholder="541330"
                  required
                />
                <.input
                  field={@search_filter_form[:label]}
                  type="text"
                  label="Label"
                  placeholder="Engineering services"
                />
                <.input
                  field={@search_filter_form[:per_run_limit]}
                  type="number"
                  label="Per-Code Limit"
                  min="1"
                  max="25"
                  placeholder="5"
                />
                <div class="flex justify-end">
                  <.button type="submit" variant="primary">Add Filter</.button>
                </div>
              </.form>
            </div>
          </.section>

          <.section
            title="Discovery"
            description="Use browser discovery when selectors are unknown or the portal layout needs inspection."
          >
            <div class="flex flex-col gap-2">
              <.button
                :if={discoverable?(@source.procurement_source)}
                type="button"
                variant="primary"
                phx-click="start_discovery"
                phx-disable-with="Starting..."
              >
                Start Discovery
              </.button>
              <.link
                href={@source.url}
                target="_blank"
                class="inline-flex items-center justify-center rounded-md border border-zinc-300 bg-white px-3 py-2 text-sm font-semibold text-zinc-800 shadow-sm transition hover:border-zinc-400 hover:bg-zinc-50 dark:border-white/10 dark:bg-white/[0.04] dark:text-white dark:hover:border-white/20 dark:hover:bg-white/[0.08]"
              >
                Open Source
              </.link>
            </div>
          </.section>
        </div>
      </div>
    </.page>
    """
  end

  defp load_source(id, actor) do
    with {:ok, source} <- Acquisition.get_source(id, actor: actor, load: [:procurement_source]),
         %{procurement_source: procurement_source} when not is_nil(procurement_source) <- source do
      {:ok, source}
    else
      %{procurement_source: nil} -> {:error, "Only procurement-backed sources can be configured."}
      error -> error
    end
  end

  defp assign_search_filters(socket) do
    filters =
      case socket.assigns.source.procurement_source do
        %{id: id} ->
          case Procurement.list_source_search_filters(id, actor: socket.assigns.current_user) do
            {:ok, filters} -> filters
            _ -> []
          end

        _ ->
          []
      end

    assign(socket, :search_filters, filters)
  end

  defp assign_search_filter_form(socket, params) do
    params =
      Map.merge(
        %{"value" => "", "label" => "", "per_run_limit" => "5"},
        stringify_keys(params)
      )

    assign(socket, :search_filter_form, to_form(params, as: :search_filter))
  end

  defp assign_form(socket, params) do
    assign(socket, :form, to_form(params, as: :config))
  end

  defp config_params(%{procurement_source: %{scrape_config: config, url: url}})
       when is_map(config) do
    pagination = value(config, "pagination") || %{}

    %{
      "listing_url" => value(config, "listing_url") || url,
      "listing_selector" => value(config, "listing_selector"),
      "title_selector" => value(config, "title_selector"),
      "date_selector" => value(config, "date_selector"),
      "link_selector" => value(config, "link_selector"),
      "description_selector" => value(config, "description_selector"),
      "agency_selector" => value(config, "agency_selector"),
      "pagination_type" => value(pagination, "type") || "none",
      "pagination_selector" => value(pagination, "selector"),
      "search_selector" => value(config, "search_selector"),
      "notes" => value(config, "notes")
    }
  end

  defp config_params(%{url: url}), do: %{"listing_url" => url, "pagination_type" => "none"}

  defp compact_config_params(params) do
    Map.new(params, fn {key, value} ->
      value =
        case value do
          "" -> nil
          value -> value
        end

      {key, value}
    end)
  end

  defp search_filter_attrs(source, params) do
    value =
      params
      |> Map.get("value", "")
      |> String.trim()

    per_run_limit =
      params
      |> Map.get("per_run_limit")
      |> parse_positive_integer(5)

    %{
      procurement_source_id: source.id,
      filter_type: :naics,
      value: value,
      label: blank_to_nil(Map.get(params, "label")),
      per_run_limit: per_run_limit,
      enabled: true,
      priority: :medium
    }
  end

  defp stringify_keys(params) do
    Map.new(params, fn {key, value} -> {to_string(key), value} end)
  end

  defp parse_positive_integer(value, default) do
    case Integer.parse(to_string(value || "")) do
      {integer, _} when integer > 0 -> integer
      _ -> default
    end
  end

  defp blank_to_nil(nil), do: nil
  defp blank_to_nil(""), do: nil

  defp blank_to_nil(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp blank_to_nil(value), do: value

  defp value(map, key), do: Map.get(map, key) || Map.get(map, config_key_atom(key))

  attr :field, Phoenix.HTML.FormField, required: true
  attr :type, :string, default: "text"
  attr :label, :string, required: true
  attr :hint, :string, required: true

  attr :rest, :global,
    include: ~w(autocomplete cols disabled form list max maxlength min minlength pattern
                placeholder readonly required rows size step)

  defp config_input(assigns) do
    ~H"""
    <div>
      <.input field={@field} type={@type} label={@label} {@rest} />
      <p class="mt-1.5 text-xs leading-5 text-base-content/55">
        {@hint}
      </p>
    </div>
    """
  end

  defp config_key_atom("listing_url"), do: :listing_url
  defp config_key_atom("listing_selector"), do: :listing_selector
  defp config_key_atom("title_selector"), do: :title_selector
  defp config_key_atom("date_selector"), do: :date_selector
  defp config_key_atom("link_selector"), do: :link_selector
  defp config_key_atom("description_selector"), do: :description_selector
  defp config_key_atom("agency_selector"), do: :agency_selector
  defp config_key_atom("pagination"), do: :pagination
  defp config_key_atom("type"), do: :type
  defp config_key_atom("selector"), do: :selector
  defp config_key_atom("search_selector"), do: :search_selector
  defp config_key_atom("notes"), do: :notes

  defp discoverable?(%{status: :approved, config_status: status})
       when status in [:found, :pending, :config_failed],
       do: true

  defp discoverable?(_source), do: false

  defp sam_gov_source?(%{source_type: :sam_gov}), do: true
  defp sam_gov_source?(_source), do: false

  defp show_disable_noisy_action?(%{
         enabled: true,
         performance_recommendation: "Disable noisy filter"
       }),
       do: true

  defp show_disable_noisy_action?(_filter), do: false

  defp show_keep_searching_action?(%{enabled: false}), do: true

  defp show_keep_searching_action?(%{performance_recommendation: recommendation})
       when recommendation in ["Keep searching", "Watch next run"],
       do: true

  defp show_keep_searching_action?(_filter), do: false

  defp procurement_status_variant(:approved), do: :success
  defp procurement_status_variant(:blocked), do: :error
  defp procurement_status_variant(:ignored), do: :default
  defp procurement_status_variant(_status), do: :warning

  defp config_status_variant(:configured), do: :success
  defp config_status_variant(:pending), do: :warning
  defp config_status_variant(:config_failed), do: :error
  defp config_status_variant(:scan_failed), do: :error
  defp config_status_variant(:manual), do: :info
  defp config_status_variant(_status), do: :default
end
