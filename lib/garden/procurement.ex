defmodule GnomeGarden.Procurement do
  @moduledoc """
  Procurement monitoring and opportunity discovery domain.

  Owns monitored procurement sources and the bid opportunities discovered from
  them. This is durable business state, not agent control-plane state.
  """

  use Ash.Domain,
    otp_app: :gnome_garden,
    extensions: [AshAdmin.Domain]

  alias GnomeGarden.Procurement.ScanRunner

  admin do
    show? true
  end

  resources do
    resource GnomeGarden.Procurement.ProcurementSource do
      define :list_procurement_sources, action: :read
      define :list_console_procurement_sources, action: :console
      define :get_procurement_source, action: :read, get_by: [:id]
      define :get_procurement_source_by_url, action: :by_url, args: [:url]
      define :create_procurement_source, action: :create
      define :create_procurement_source_for_organization, action: :create_for_organization
      define :update_procurement_source, action: :update
      define :approve_procurement_source, action: :approve
      define :ignore_procurement_source, action: :ignore
      define :block_procurement_source, action: :block
      define :reconsider_procurement_source, action: :reconsider
      define :queue_procurement_source, action: :queue
      define :configure_procurement_source, action: :configure
      define :config_fail_procurement_source, action: :config_fail
      define :scan_procurement_source, action: :scan
      define :scan_fail_procurement_source, action: :scan_fail
      define :retry_procurement_source_config, action: :retry_config
      define :retry_procurement_source_scan, action: :retry_scan
      define :mark_procurement_source_scanned, action: :mark_scanned

      define :list_procurement_sources_needing_configuration, action: :needs_configuration

      define :list_procurement_sources_ready_for_scan,
        action: :ready_for_scan,
        args: [:since_hours]

      define :list_procurement_sources_by_type,
        action: :by_type,
        args: [:source_type]

      define :list_procurement_sources_by_organization,
        action: :by_organization,
        args: [:organization_id]
    end

    resource GnomeGarden.Procurement.Bid do
      define :list_bids, action: :read
      define :list_bids_for_organization, action: :for_organization, args: [:organization_id]
      define :get_bid, action: :read, get_by: [:id]
      define :get_bid_by_url, action: :by_url, args: [:url]
      define :create_bid, action: :create
      define :update_bid, action: :update
      define :list_active_bids, action: :active
      define :list_parked_bids, action: :parked
      define :list_rejected_bids, action: :rejected
      define :list_closed_bids, action: :closed
      define :review_bid, action: :start_review
      define :link_bid_signal, action: :link_signal
      define :link_bid_organization, action: :link_organization
      define :pursue_bid, action: :pursue
      define :submit_bid, action: :submit
      define :win_bid, action: :mark_won
      define :lose_bid, action: :mark_lost
      define :reject_bid, action: :reject
      define :park_bid, action: :park
      define :unpark_bid, action: :unpark
      define :expire_bid, action: :expire
    end
  end

  def launch_procurement_source_scan(source_or_id, opts \\ []) do
    ScanRunner.launch_source_scan(source_or_id, opts)
  end

  def save_source_config(attrs, opts \\ []) when is_map(attrs) do
    actor = Keyword.get(opts, :actor)

    with {:ok, source} <- source_from_attrs(attrs, actor),
         {:ok, scrape_config} <- scrape_config_from_attrs(attrs) do
      configure_procurement_source(
        source,
        %{scrape_config: scrape_config},
        actor: actor
      )
    end
  end

  def run_source_scan(attrs, opts \\ []) when is_map(attrs) do
    actor = Keyword.get(opts, :actor)

    with {:ok, source} <- source_from_attrs(attrs, actor) do
      GnomeGarden.Agents.Procurement.ScannerRouter.scan(source, %{
        actor: actor,
        pi_rpc?: true
      })
    end
  end

  defp source_from_attrs(attrs, actor) do
    cond do
      id = value(attrs, :procurement_source_id) || value(attrs, :source_id) ->
        get_procurement_source(id, actor: actor)

      url = value(attrs, :url) || value(attrs, :source_url) ->
        get_procurement_source_by_url(url, actor: actor)

      true ->
        {:error, "procurement_source_id, source_id, or url is required"}
    end
  end

  defp scrape_config_from_attrs(attrs) do
    cond do
      config = value(attrs, :scrape_config) ->
        {:ok, config}

      value(attrs, :listing_url) && value(attrs, :listing_selector) &&
          value(attrs, :title_selector) ->
        {:ok,
         %{
           listing_url: value(attrs, :listing_url),
           listing_selector: value(attrs, :listing_selector),
           title_selector: value(attrs, :title_selector),
           date_selector: value(attrs, :date_selector),
           link_selector: value(attrs, :link_selector),
           description_selector: value(attrs, :description_selector),
           agency_selector: value(attrs, :agency_selector),
           pagination: %{
             type: value(attrs, :pagination_type) || "none",
             selector: value(attrs, :pagination_selector)
           },
           search_selector: value(attrs, :search_selector),
           notes: value(attrs, :notes)
         }}

      true ->
        {:error, "listing_url, listing_selector, and title_selector are required"}
    end
  end

  defp value(attrs, key) when is_atom(key) do
    Map.get(attrs, key) || Map.get(attrs, Atom.to_string(key))
  end
end
