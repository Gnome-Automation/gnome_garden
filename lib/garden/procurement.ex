defmodule GnomeGarden.Procurement do
  @moduledoc """
  Procurement monitoring and opportunity discovery domain.

  Owns monitored procurement sources and the bid opportunities discovered from
  them. This is durable business state, not agent control-plane state.
  """

  use Ash.Domain,
    otp_app: :gnome_garden,
    extensions: [AshAdmin.Domain]

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
      define :list_review_bids, action: :needs_review
      define :list_active_bids, action: :active
      define :list_parked_bids, action: :parked
      define :list_rejected_bids, action: :rejected
      define :list_closed_bids, action: :closed
      define :review_bid, action: :start_review
      define :link_bid_signal, action: :link_signal
      define :link_bid_organization, action: :link_organization
      define :reject_bid, action: :reject
      define :park_bid, action: :park
      define :unpark_bid, action: :unpark
    end
  end
end
