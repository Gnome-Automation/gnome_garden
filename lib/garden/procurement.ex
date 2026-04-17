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
      define :update_procurement_source, action: :update
      define :approve_procurement_source, action: :approve
      define :ignore_procurement_source, action: :ignore
      define :block_procurement_source, action: :block
      define :reconsider_procurement_source, action: :reconsider
      define :queue_procurement_source, action: :queue
      define :config_fail_procurement_source, action: :config_fail
      define :scan_procurement_source, action: :scan
      define :retry_procurement_source_config, action: :retry_config
      define :retry_procurement_source_scan, action: :retry_scan
    end

    resource GnomeGarden.Procurement.Bid do
      define :list_bids, action: :read
      define :get_bid, action: :read, get_by: [:id]
      define :reject_bid, action: :reject
      define :park_bid, action: :park
      define :unpark_bid, action: :unpark
    end
  end
end
