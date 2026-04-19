defmodule GnomeGarden.Agents do
  @moduledoc """
  Agent control-plane domain.

  Owns agent templates, deployments, runs, messages, and memory.
  """

  use Ash.Domain,
    otp_app: :gnome_garden,
    extensions: [AshAdmin.Domain, AshPhoenix]

  admin do
    show? true
  end

  resources do
    resource GnomeGarden.Agents.Agent do
      define :list_agent_templates, action: :read
      define :get_agent_template, action: :read, get_by: [:id]
      define :get_agent_template_by_name, action: :read, get_by: [:name]
      define :create_agent_template, action: :create
      define :update_agent_template, action: :update
    end

    resource GnomeGarden.Agents.AgentDeployment do
      define :list_agent_deployments, action: :visible
      define :list_console_agent_deployments, action: :console
      define :list_enabled_agent_deployments, action: :enabled
      define :list_scheduled_agent_deployments, action: :scheduled
      define :get_agent_deployment, action: :read, get_by: [:id]
      define :get_agent_deployment_by_name, action: :read, get_by: [:name]
      define :create_agent_deployment, action: :create
      define :update_agent_deployment, action: :update
      define :delete_agent_deployment, action: :destroy
      define :pause_agent_deployment, action: :pause
      define :resume_agent_deployment, action: :resume
    end

    resource GnomeGarden.Agents.AgentRun do
      define :list_agent_runs, action: :read
      define :list_active_agent_runs, action: :active
      define :list_recent_agent_runs, action: :recent, args: [:limit]
      define :list_agent_runs_by_deployment, action: :by_deployment, args: [:deployment_id]

      define :list_scheduled_agent_runs_for_slot,
        action: :scheduled_for_slot,
        args: [:deployment_id, :schedule_slot]

      define :get_agent_run, action: :read, get_by: [:id]
      define :create_agent_run, action: :create
      define :start_agent_run, action: :start
      define :complete_agent_run, action: :complete
      define :fail_agent_run, action: :fail
      define :cancel_agent_run, action: :cancel
    end

    resource GnomeGarden.Agents.AgentRunOutput do
      define :list_agent_run_outputs_for_run, action: :by_run, args: [:agent_run_id]
      define :create_agent_run_output, action: :create
    end

    resource GnomeGarden.Agents.AgentMessage do
      define :list_agent_messages_for_run, action: :by_run, args: [:agent_run_id]
      define :list_recent_agent_messages, action: :recent, args: [:agent_run_id, :limit]
      define :create_agent_message, action: :create
    end

    resource GnomeGarden.Agents.Memory

    resource GnomeGarden.Agents.Prospect do
      define :list_prospects, action: :read
      define :get_prospect, action: :read, get_by: [:id]
      define :create_prospect, action: :create
      define :update_prospect, action: :update
      define :convert_prospect_to_organization, action: :convert_to_organization
      define :convert_prospect_to_signal, action: :convert_to_signal
      define :reject_prospect, action: :reject
    end
  end
end
