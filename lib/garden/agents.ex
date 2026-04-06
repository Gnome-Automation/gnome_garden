defmodule GnomeGarden.Agents do
  @moduledoc """
  Domain for autonomous agent management.

  Provides Ash resources for agent templates, execution tracking,
  conversation history, and persistent memory with auto-generated
  Jido tools via AshJido.
  """

  use Ash.Domain,
    otp_app: :gnome_garden,
    extensions: [AshAdmin.Domain]

  admin do
    show? true
  end

  resources do
    resource GnomeGarden.Agents.Agent
    resource GnomeGarden.Agents.AgentRun
    resource GnomeGarden.Agents.AgentMessage
    resource GnomeGarden.Agents.Memory

    resource GnomeGarden.Agents.LeadSource do
      define :list_lead_sources, action: :read
      define :get_lead_source, action: :read, get_by: [:id]
    end

    resource GnomeGarden.Agents.Bid do
      define :list_bids, action: :read
      define :get_bid, action: :read, get_by: [:id]
      define :reject_bid, action: :reject
      define :park_bid, action: :park
      define :unpark_bid, action: :unpark
    end

    resource GnomeGarden.Agents.Prospect do
      define :list_prospects, action: :read
      define :get_prospect, action: :read, get_by: [:id]
      define :reject_prospect, action: :reject
    end
  end
end
