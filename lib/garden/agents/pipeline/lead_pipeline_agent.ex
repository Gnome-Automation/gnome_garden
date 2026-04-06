defmodule GnomeGarden.Agents.Pipeline.LeadPipelineAgent do
  @moduledoc """
  Autonomous lead pipeline agent.

  Reacts to signals from the Jido Signal Bus to orchestrate
  the full lead lifecycle:

    1. New bid discovered → qualify and create lead if HOT/WARM
    2. New lead created   → enrich with company research
    3. Lead enriched      → auto-qualify or flag for review

  Started as a supervised process and subscribes to
  GnomeGarden.SignalBus for relevant signal patterns.
  """
  use Jido.Agent,
    name: "lead_pipeline",
    description: "Orchestrates the autonomous lead qualification pipeline",
    schema: [
      bids_processed: [type: :integer, default: 0],
      leads_created: [type: :integer, default: 0],
      leads_qualified: [type: :integer, default: 0],
      leads_held: [type: :integer, default: 0],
      status: [type: :atom, default: :running]
    ]

  alias GnomeGarden.Agents.Pipeline.{
    QualifyBidAction,
    EnrichLeadAction,
    QualifyLeadAction
  }

  @impl true
  def signal_routes do
    [
      {"sales.bid.created", QualifyBidAction},
      {"sales.bid.scored", QualifyBidAction},
      {"sales.lead.created", EnrichLeadAction},
      {"sales.lead.needs_enrichment", EnrichLeadAction},
      {"sales.lead.enriched", QualifyLeadAction}
    ]
  end
end
