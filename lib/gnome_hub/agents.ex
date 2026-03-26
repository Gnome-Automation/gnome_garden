defmodule GnomeHub.Agents do
  @moduledoc """
  Domain for autonomous agent management.

  Provides Ash resources for agent templates, execution tracking,
  conversation history, and persistent memory with auto-generated
  Jido tools via AshJido.
  """

  use Ash.Domain,
    otp_app: :gnome_hub,
    extensions: [AshAdmin.Domain]

  admin do
    show? true
  end

  resources do
    resource GnomeHub.Agents.Agent
    resource GnomeHub.Agents.AgentRun
    resource GnomeHub.Agents.AgentMessage
    resource GnomeHub.Agents.Memory
    resource GnomeHub.Agents.LeadSource
    resource GnomeHub.Agents.Bid
    resource GnomeHub.Agents.Prospect
  end
end
