defmodule GnomeGardenWeb.Acquisition.SourceLive.Configure do
  use GnomeGardenWeb, :live_view

  import GnomeGardenWeb.Execution.Helpers, only: [format_atom: 1]

  alias GnomeGarden.Acquisition
  alias GnomeGarden.Agents.Procurement.SourceConfigurator
  alias GnomeGarden.Procurement

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    case load_source(id, socket.assigns.current_user) do
      {:ok, source} ->
        {:ok,
         socket
         |> assign(:page_title, "Configure Source")
         |> assign(:source, source)
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
