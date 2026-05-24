defmodule GnomeGardenWeb.Acquisition.SourceLive.Configure do
  use GnomeGardenWeb, :live_view

  import GnomeGardenWeb.Execution.Helpers, only: [format_atom: 1, format_datetime: 1]

  alias GnomeGarden.Acquisition
  alias GnomeGarden.Agents.Procurement.SourceAutoConfigurator
  alias GnomeGarden.Procurement

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    if connected?(socket) do
      GnomeGardenWeb.Endpoint.subscribe("source:updated")
      GnomeGardenWeb.Endpoint.subscribe("procurement_source:queued")
      GnomeGardenWeb.Endpoint.subscribe("procurement_source:configured")
      GnomeGardenWeb.Endpoint.subscribe("procurement_source:config_failed")
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

    case SourceAutoConfigurator.configure_source(source, actor: socket.assigns.current_user) do
      {:ok, %{mode: :auto_configured}} ->
        {:noreply,
         socket
         |> refresh_source()
         |> put_flash(:info, "Source configured automatically for #{source.name}.")}

      {:ok, %{mode: :already_configured}} ->
        {:noreply,
         socket
         |> refresh_source()
         |> put_flash(:info, "#{source.name} is already configured.")}

      {:ok, %{mode: :discovery_started}} ->
        {:noreply,
         socket
         |> refresh_source()
         |> put_flash(:info, "Discovery started for #{source.name}.")}

      {:ok, %{mode: :already_pending}} ->
        {:noreply,
         socket
         |> refresh_source()
         |> put_flash(:info, "#{source.name} is already queued for discovery.")}

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

  def handle_info(%{topic: "source:updated"}, socket) do
    {:noreply, refresh_source(socket)}
  end

  def handle_info(%{topic: "procurement_source:" <> _event}, socket) do
    {:noreply, refresh_source(socket)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.page class="pb-8">
      <.page_header>
        Configure Source
        <:subtitle>
          System setup is the default. Manual selectors are only a fallback when browser discovery cannot identify clear listing data.
        </:subtitle>
        <:actions>
          <.button navigate={~p"/acquisition/sources"}>
            Sources
          </.button>
        </:actions>
      </.page_header>

      <div class="grid gap-4 lg:grid-cols-[minmax(0,1fr)_22rem]">
        <.section title={@source.name} description={@source.url}>
          <.discovery_status_panel source={@source} />

          <div class="mb-4 rounded-lg border border-info/20 bg-info/10 p-3 text-sm text-base-content">
            <div class="flex flex-col gap-3 sm:flex-row sm:items-start sm:justify-between">
              <div class="space-y-1">
                <p class="font-semibold">System configuration runs first.</p>
                <p class="leading-5 text-base-content/70">
                  Known portals like PlanetBids and BidNet are configured immediately. Unknown portals
                  are sent to browser discovery. Use manual selectors only after setup fails:
                  <code class="rounded bg-base-100 px-1 py-0.5 text-xs">.bid-row</code>
                  could mean one listing, and
                  <code class="rounded bg-base-100 px-1 py-0.5 text-xs">.bid-title</code>
                  could mean the title inside it.
                </p>
              </div>
              <div class="flex shrink-0 flex-wrap gap-2">
                <.button
                  :if={discoverable?(@source.procurement_source)}
                  type="button"
                  variant="primary"
                  phx-click="start_discovery"
                  disabled={discovery_running?(@source)}
                  phx-disable-with="Starting..."
                >
                  {if discovery_running?(@source),
                    do: "Discovery Running",
                    else: "Configure"}
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

          <div
            :if={!manual_config_available?(@source)}
            class="rounded-lg border border-dashed border-base-content/20 bg-base-200/40 p-4 text-sm leading-6 text-base-content/65"
          >
            Manual selector fields are hidden until the automatic setup path fails or a source is marked for manual configuration.
          </div>

          <.form
            :if={manual_config_available?(@source)}
            for={@form}
            id="source-config-form"
            phx-change="validate"
            phx-submit="save"
          >
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
            title="Automatic Setup"
            description="Known portals are configured immediately. Unknown portals are sent to browser discovery."
          >
            <div class="flex flex-col gap-2">
              <.discovery_status_panel source={@source} compact />
              <.button
                :if={discoverable?(@source.procurement_source)}
                type="button"
                variant="primary"
                phx-click="start_discovery"
                disabled={discovery_running?(@source)}
                phx-disable-with="Starting..."
              >
                {if discovery_running?(@source),
                  do: "Discovery Running",
                  else: "Configure"}
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

  defp refresh_source(socket) do
    case load_source(socket.assigns.source.id, socket.assigns.current_user) do
      {:ok, source} ->
        socket
        |> assign(:source, source)
        |> assign_search_filters()
        |> assign_form(config_params(source))

      {:error, _error} ->
        socket
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

  defp manual_config_available?(%{procurement_source: %{config_status: status}})
       when status in [:config_failed, :manual],
       do: true

  defp manual_config_available?(_source), do: false

  defp discovery_running?(%{procurement_source: %{config_status: :pending}}), do: true
  defp discovery_running?(_source), do: false

  attr :source, :map, required: true
  attr :compact, :boolean, default: false

  defp discovery_status_panel(assigns) do
    assigns =
      assigns
      |> assign(:status_label, discovery_status_label(assigns.source))
      |> assign(:status_variant, discovery_status_variant(assigns.source))
      |> assign(:status_note, discovery_status_note(assigns.source))
      |> assign(:next_step, discovery_next_step(assigns.source))
      |> assign(
        :run_id,
        metadata_value(assigns.source.procurement_source.metadata, "last_agent_run_id")
      )
      |> assign(
        :run_state,
        metadata_value(assigns.source.procurement_source.metadata, "last_agent_run_state")
      )
      |> assign(
        :config_error,
        metadata_value(assigns.source.procurement_source.metadata, "last_config_error")
      )

    ~H"""
    <div class={[
      "rounded-lg border border-base-content/10 bg-base-200/60 p-3 text-sm",
      !@compact && "mb-4"
    ]}>
      <div class="flex flex-col gap-3 sm:flex-row sm:items-start sm:justify-between">
        <div class="min-w-0">
          <div class="flex flex-wrap items-center gap-2">
            <p class="font-semibold text-base-content">Discovery Status</p>
            <.status_badge status={@status_variant}>{@status_label}</.status_badge>
            <.status_badge :if={@run_state} status={run_state_variant(@run_state)}>
              Run {format_run_state(@run_state)}
            </.status_badge>
          </div>
          <p class="mt-1 leading-5 text-base-content/70">
            {@status_note}
          </p>
          <div
            :if={@config_error}
            class="mt-3 rounded-md border border-error/30 bg-error/10 px-3 py-2 text-error"
          >
            <p class="font-semibold">Browser discovery could not get clear data from this source.</p>
            <p class="mt-1 leading-5">{@config_error}</p>
          </div>
          <p class="mt-2 text-xs font-medium uppercase tracking-[0.14em] text-base-content/45">
            Next step
          </p>
          <p class="mt-1 leading-5 text-base-content/70">
            {@next_step}
          </p>
        </div>

        <div class="shrink-0 text-xs text-base-content/55 sm:text-right">
          <p>Config changed {format_datetime(@source.procurement_source.updated_at)}</p>
          <.link
            :if={@run_id}
            navigate={~p"/console/agents/runs/#{@run_id}"}
            class="mt-2 inline-flex font-semibold text-emerald-700 hover:text-emerald-600 dark:text-emerald-300"
          >
            Open Run
          </.link>
        </div>
      </div>
    </div>
    """
  end

  defp discovery_status_label(%{procurement_source: %{config_status: :found}}),
    do: "Needs discovery"

  defp discovery_status_label(%{procurement_source: %{config_status: :pending}}),
    do: "Discovery running"

  defp discovery_status_label(%{procurement_source: %{config_status: :configured}}),
    do: "Configured"

  defp discovery_status_label(%{procurement_source: %{config_status: :config_failed}}),
    do: "Discovery failed"

  defp discovery_status_label(%{procurement_source: %{config_status: :scan_failed}}),
    do: "Scan failed"

  defp discovery_status_label(%{procurement_source: %{config_status: :manual}}),
    do: "Manual config"

  defp discovery_status_label(%{procurement_source: %{config_status: status}}),
    do: format_atom(status)

  defp discovery_status_variant(%{procurement_source: %{config_status: :configured}}),
    do: :success

  defp discovery_status_variant(%{procurement_source: %{config_status: :pending}}), do: :info

  defp discovery_status_variant(%{procurement_source: %{config_status: :config_failed}}),
    do: :error

  defp discovery_status_variant(%{procurement_source: %{config_status: :scan_failed}}), do: :error
  defp discovery_status_variant(%{procurement_source: %{config_status: :manual}}), do: :info
  defp discovery_status_variant(_source), do: :warning

  defp discovery_status_note(%{procurement_source: %{config_status: :found}}),
    do:
      "This source exists, but the scanner does not know which page elements contain listings yet."

  defp discovery_status_note(%{procurement_source: %{config_status: :pending}}),
    do:
      "Browser discovery has been queued or is running. This page will update when the source becomes configured or fails."

  defp discovery_status_note(%{procurement_source: %{config_status: :configured}}),
    do: "Selectors are saved. This source can be scanned from the source registry."

  defp discovery_status_note(%{procurement_source: %{config_status: :config_failed}}),
    do:
      "Automatic setup failed because browser discovery could not produce a usable scanner configuration."

  defp discovery_status_note(%{procurement_source: %{config_status: :scan_failed}}),
    do: "The scanner configuration exists, but the most recent scan failed."

  defp discovery_status_note(%{procurement_source: %{config_status: :manual}}),
    do: "This source is marked for manual configuration instead of browser discovery."

  defp discovery_status_note(_source), do: "Source state is available below."

  defp discovery_next_step(%{procurement_source: %{config_status: :found}}),
    do:
      "Click Configure. Known portals will be configured immediately; unknown portals will go to browser discovery."

  defp discovery_next_step(%{procurement_source: %{config_status: :pending}}),
    do: "Wait for discovery to finish. If it fails, review the source URL and try again."

  defp discovery_next_step(%{procurement_source: %{config_status: :configured}}),
    do: "Return to Sources and launch a scan to create reviewable findings."

  defp discovery_next_step(%{procurement_source: %{config_status: :config_failed}}),
    do:
      "Retry Configure after checking the portal page, or use the manual fallback fields now shown below."

  defp discovery_next_step(%{procurement_source: %{config_status: :scan_failed}}),
    do: "Edit the selectors or launch a retry scan from the source registry."

  defp discovery_next_step(%{procurement_source: %{config_status: :manual}}),
    do: "Fill in the scanner selectors manually and save configuration."

  defp discovery_next_step(_source), do: "Review the current source state."

  defp run_state_variant("completed"), do: :success
  defp run_state_variant("running"), do: :info
  defp run_state_variant("failed"), do: :error
  defp run_state_variant("cancelled"), do: :warning
  defp run_state_variant(_state), do: :default

  defp format_run_state(state) do
    state
    |> to_string()
    |> String.replace("_", " ")
    |> String.capitalize()
  end

  defp metadata_value(metadata, key) when is_map(metadata) do
    Map.get(metadata, key) || Map.get(metadata, metadata_key_atom(key))
  end

  defp metadata_value(_metadata, _key), do: nil

  defp metadata_key_atom("last_agent_run_id"), do: :last_agent_run_id
  defp metadata_key_atom("last_agent_run_state"), do: :last_agent_run_state
  defp metadata_key_atom("last_config_error"), do: :last_config_error
  defp metadata_key_atom("last_config_error_at"), do: :last_config_error_at
  defp metadata_key_atom(key), do: config_key_atom(key)

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
