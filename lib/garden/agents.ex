defmodule GnomeGarden.Agents do
  @moduledoc """
  Agent control-plane domain.

  Owns agent templates, deployments, runs, messages, and memory.
  """

  use Ash.Domain,
    otp_app: :gnome_garden,
    extensions: [AshAdmin.Domain, AshAi, AshPhoenix]

  admin do
    show? true
  end

  tools do
    tool :agent_recent_runs, GnomeGarden.Agents.AgentRun, :recent do
      action_parameters [:input]
      description "List recent agent runs for operator triage."
    end

    tool :agent_recent_failed_runs, GnomeGarden.Agents.AgentRun, :failed_recent do
      action_parameters [:input]
      description "List recent failed agent runs that need operator attention."
    end

    tool :agent_workflow_definition,
         GnomeGarden.Agents.AgentWorkflowDefinition,
         :published_by_key do
      action_parameters [:input]
      description "Fetch the latest published workflow definition by workflow key."
    end

    tool :agent_eval_cases_for_workflow, GnomeGarden.Agents.AgentEvalCase, :by_workflow_key do
      action_parameters [:input]
      description "List evaluation cases for a workflow key."
    end

    tool :agent_recent_eval_runs, GnomeGarden.Agents.AgentEvalRun, :recent do
      action_parameters [:input]
      description "List recent agent evaluation runs."
    end

    tool :agent_eval_runs_for_case, GnomeGarden.Agents.AgentEvalRun, :by_eval_case do
      action_parameters [:input]
      description "List evaluation runs for a specific evaluation case."
    end
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
      define :list_agent_deployments, action: :visible, args: [:owner_team_member_id]
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
      define :list_recent_failed_agent_runs, action: :failed_recent, args: [:limit]

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

    resource GnomeGarden.Agents.AgentWorkflowDefinition do
      define :list_agent_workflow_definitions, action: :read
      define :list_agent_workflow_definitions_by_key, action: :by_key, args: [:key]

      define :get_published_agent_workflow_definition,
        action: :published_by_key,
        args: [:key]

      define :get_agent_workflow_definition, action: :read, get_by: [:id]
      define :create_agent_workflow_definition, action: :create_draft
      define :clone_agent_workflow_definition_version, action: :clone_version
      define :update_agent_workflow_definition_draft, action: :update_draft
      define :validate_agent_workflow_definition, action: :validate
      define :publish_agent_workflow_definition, action: :publish
      define :disable_agent_workflow_definition, action: :disable
      define :archive_agent_workflow_definition, action: :archive
      define :delete_agent_workflow_definition, action: :destroy
    end

    resource GnomeGarden.Agents.AgentEvalCase do
      define :list_agent_eval_cases, action: :read
      define :list_active_agent_eval_cases, action: :active

      define :list_agent_eval_cases_by_workflow_key,
        action: :by_workflow_key,
        args: [:workflow_key]

      define :get_agent_eval_case, action: :read, get_by: [:id]
      define :get_agent_eval_case_by_key, action: :by_key, args: [:key]
      define :create_agent_eval_case, action: :create
      define :update_agent_eval_case, action: :update
      define :archive_agent_eval_case, action: :archive
      define :delete_agent_eval_case, action: :destroy
    end

    resource GnomeGarden.Agents.AgentEvalRun do
      define :list_agent_eval_runs, action: :read
      define :list_recent_agent_eval_runs, action: :recent, args: [:limit]
      define :list_agent_eval_runs_by_case, action: :by_eval_case, args: [:eval_case_id]
      define :get_agent_eval_run, action: :read, get_by: [:id]
      define :create_agent_eval_run, action: :create
      define :start_agent_eval_run, action: :start
      define :pass_agent_eval_run, action: :pass
      define :fail_agent_eval_run, action: :fail
      define :error_agent_eval_run, action: :error
      define :delete_agent_eval_run, action: :destroy
    end

    resource GnomeGarden.Agents.Memory do
      define :remember_memory, action: :remember
      define :recall_memories, action: :recall, args: [:query]
      define :search_memories, action: :search, args: [:namespace]
      define :get_memory_by_key, action: :by_key, args: [:key]
      define :list_memories_by_type, action: :by_type, args: [:type]
    end
  end
end
