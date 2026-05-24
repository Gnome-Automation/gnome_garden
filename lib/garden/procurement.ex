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
  alias GnomeGarden.Procurement.SourcePipeline

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
      define :auto_configure_procurement_source, action: :auto_configure
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

    resource GnomeGarden.Procurement.CrawlRun do
      define :list_crawl_runs, action: :read
      define :list_crawl_runs_for_source, action: :for_source, args: [:procurement_source_id]
      define :get_crawl_run, action: :read, get_by: [:id]
      define :start_crawl_run, action: :start
      define :complete_crawl_run, action: :complete
      define :fail_crawl_run, action: :fail
      define :delete_crawl_run, action: :destroy
    end

    resource GnomeGarden.Procurement.CrawlPage do
      define :list_crawl_pages, action: :read
      define :list_crawl_pages_for_run, action: :for_run, args: [:crawl_run_id]
      define :get_crawl_page, action: :read, get_by: [:id]
      define :record_crawl_page, action: :record
      define :delete_crawl_page, action: :destroy
    end

    resource GnomeGarden.Procurement.CrawlEdge do
      define :list_crawl_edges, action: :read
      define :list_crawl_edges_for_run, action: :for_run, args: [:crawl_run_id]
      define :get_crawl_edge, action: :read, get_by: [:id]
      define :record_crawl_edge, action: :record
      define :delete_crawl_edge, action: :destroy
    end

    resource GnomeGarden.Procurement.PageArtifact do
      define :list_page_artifacts, action: :read
      define :list_page_artifacts_for_page, action: :for_page, args: [:crawl_page_id]
      define :get_page_artifact, action: :read, get_by: [:id]
      define :record_page_artifact, action: :record
      define :delete_page_artifact, action: :destroy
    end

    resource GnomeGarden.Procurement.ExtractionCandidate do
      define :list_extraction_candidates, action: :read
      define :list_extraction_candidates_for_run, action: :for_run, args: [:crawl_run_id]
      define :get_extraction_candidate, action: :read, get_by: [:id]
      define :propose_extraction_candidate, action: :propose
      define :accept_extraction_candidate, action: :accept
      define :reject_extraction_candidate, action: :reject
      define :mark_duplicate_extraction_candidate, action: :mark_duplicate
      define :delete_extraction_candidate, action: :destroy
    end

    resource GnomeGarden.Procurement.SourceSearchFilter do
      define :list_source_search_filters, action: :for_source, args: [:procurement_source_id]
      define :get_source_search_filter, action: :read, get_by: [:id]

      define :list_enabled_source_search_filters,
        action: :enabled_for_source,
        args: [:procurement_source_id]

      define :create_source_search_filter, action: :create
      define :update_source_search_filter, action: :update
      define :disable_noisy_source_search_filter, action: :disable_noisy
      define :keep_searching_source_search_filter, action: :keep_searching
      define :delete_source_search_filter, action: :destroy
      define :record_source_search_filter_run, action: :record_run
    end

    resource GnomeGarden.Procurement.SourceSearchFilterFeedback do
      define :list_source_search_filter_feedback,
        action: :for_filter,
        args: [:source_search_filter_id]

      define :list_source_search_filter_feedback_for_finding,
        action: :for_finding,
        args: [:finding_id]

      define :record_source_search_filter_feedback, action: :record
      define :get_source_search_filter_feedback, action: :read, get_by: [:id]
    end

    resource GnomeGarden.Procurement.Bid do
      define :list_bids, action: :read
      define :list_bids_for_organization, action: :for_organization, args: [:organization_id]
      define :get_bid, action: :read, get_by: [:id]
      define :get_bid_by_url, action: :by_url, args: [:url]
      define :create_bid, action: :create
      define :update_bid, action: :update
      define :record_bid_document_ingest, action: :record_document_ingest
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
    scanner_context = Keyword.get(opts, :scanner_context, %{actor: actor})

    with {:ok, source} <- source_from_attrs(attrs, actor) do
      opts =
        opts
        |> Keyword.put(:actor, actor)
        |> Keyword.put(:scanner_context, scanner_context)

      SourcePipeline.scan_source(source, opts)
    end
  end

  def inspect_procurement_source(source_or_id, opts \\ []) do
    SourcePipeline.inspect_source(source_or_id, opts)
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
