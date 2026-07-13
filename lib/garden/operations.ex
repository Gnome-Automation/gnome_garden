defmodule GnomeGarden.Operations do
  @moduledoc """
  Foundational operating model domain.

  Owns the durable business entities that commercial work, delivery, service,
  and finance hang off: organizations, people, sites, and managed systems.
  """

  use Ash.Domain,
    otp_app: :gnome_garden,
    extensions: [AshAdmin.Domain, AshAi]

  admin do
    show? true
  end

  tools do
    tool :operations_active_memory_blocks,
         GnomeGarden.Operations.MemoryBlock,
         :active_for_scope do
      action_parameters [:input]
      description "List active memory blocks for a governed operating scope."
    end

    tool :operations_recall_memory_entries,
         GnomeGarden.Operations.MemoryEntry,
         :recall_for_scope do
      action_parameters [:input]
      description "Recall active archival memory entries for a governed operating scope."
    end

    tool :operations_create_agent_followup_task,
         GnomeGarden.Operations.Task,
         :create_from_agent_run do
      description "Create an operator follow-up task for an agent run."
    end
  end

  resources do
    resource GnomeGarden.Operations.TeamMember do
      define :list_team_members, action: :read
      define :list_active_team_members, action: :active
      define :list_admin_team_members, action: :admin_index
      define :get_team_member, action: :read, get_by: [:id]
      define :get_team_member_by_user, action: :by_user, args: [:user_id]
      define :create_team_member, action: :create
      define :update_team_member, action: :update
      define :delete_team_member, action: :destroy

      define :ensure_operator_team_member,
        action: :ensure_operator,
        args: [:email, :display_name]
    end

    resource GnomeGarden.Operations.Organization do
      define :list_organizations, action: :read
      define :list_active_organizations, action: :active
      define :list_prospect_organizations, action: :prospects
      define :get_organization, action: :read, get_by: [:id]
      define :get_organization_by_name, action: :read, get_by: [:name]

      define :get_organization_by_website_domain,
        action: :by_website_domain,
        args: [:website_domain]

      define :list_organizations_by_name_key, action: :by_name_key, args: [:name_key]
      define :search_organizations, action: :search, args: [:query]

      define :create_organization, action: :create
      define :update_organization, action: :update
      define :merge_organization, action: :merge_into
    end

    resource GnomeGarden.Operations.Person do
      define :list_people, action: :read
      define :get_person, action: :read, get_by: [:id]
      define :get_person_by_email, action: :by_email, args: [:email]
      define :create_person, action: :create
      define :update_person, action: :update
      define :merge_person, action: :merge_into
      define :list_active_people, action: :active
      define :list_people_for_organization, action: :for_organization, args: [:organization_id]

      define :list_people_for_organization_by_name_key,
        action: :for_organization_and_name_key,
        args: [:organization_id, :name_key]

      define :list_people_by_name_key_and_email_domain,
        action: :by_name_key_and_email_domain,
        args: [:name_key, :email_domain]
    end

    resource GnomeGarden.Operations.OrganizationAffiliation do
      define :list_organization_affiliations, action: :read
      define :get_organization_affiliation, action: :read, get_by: [:id]
      define :create_organization_affiliation, action: :create
      define :update_organization_affiliation, action: :update
      define :end_organization_affiliation, action: :end_affiliation
      define :list_active_organization_affiliations, action: :active

      define :list_affiliations_for_organization,
        action: :for_organization,
        args: [:organization_id]

      define :list_affiliations_for_person, action: :for_person, args: [:person_id]
    end

    resource GnomeGarden.Operations.Site do
      define :list_sites, action: :read
      define :get_site, action: :read, get_by: [:id]
      define :create_site, action: :create
      define :update_site, action: :update
      define :list_sites_for_organization, action: :for_organization, args: [:organization_id]
    end

    resource GnomeGarden.Operations.ManagedSystem do
      define :list_managed_systems, action: :read
      define :get_managed_system, action: :read, get_by: [:id]
      define :create_managed_system, action: :create
      define :update_managed_system, action: :update

      define :list_managed_systems_for_organization,
        action: :for_organization,
        args: [:organization_id]

      define :list_managed_systems_for_site, action: :for_site, args: [:site_id]
    end

    resource GnomeGarden.Operations.Asset do
      define :list_assets, action: :read
      define :get_asset, action: :read, get_by: [:id]
      define :create_asset, action: :create
      define :update_asset, action: :update

      define :list_assets_for_managed_system,
        action: :for_managed_system,
        args: [:managed_system_id]

      define :list_root_assets, action: :root_assets
    end

    resource GnomeGarden.Operations.InventoryItem do
      define :list_inventory_items, action: :read
      define :get_inventory_item, action: :read, get_by: [:id]
      define :create_inventory_item, action: :create
      define :update_inventory_item, action: :update
      define :list_active_inventory_items, action: :active
      define :list_low_stock_inventory_items, action: :low_stock
    end

    resource GnomeGarden.Operations.Task do
      define :list_tasks, action: :read
      define :list_task_inbox, action: :inbox
      define :get_task, action: :read, get_by: [:id]
      define :create_task, action: :create
      define :create_task_from_finding, action: :create_from_finding
      define :create_task_from_agent_run, action: :create_from_agent_run
      define :create_task_from_pursuit, action: :create_from_pursuit
      define :update_task, action: :update
      define :delete_task, action: :destroy
      define :assign_task, action: :assign
      define :start_task, action: :start
      define :block_task, action: :block
      define :complete_task, action: :complete
      define :cancel_task, action: :cancel
      define :reopen_task, action: :reopen
      define :list_tasks_by_organization, action: :by_organization, args: [:organization_id]
      define :list_tasks_by_person, action: :by_person, args: [:person_id]
      define :list_tasks_by_pursuit, action: :by_pursuit, args: [:pursuit_id]
      define :list_tasks_by_finding, action: :by_finding, args: [:finding_id]
      define :list_tasks_by_signal, action: :by_signal, args: [:signal_id]
      define :list_tasks_by_agent_run, action: :by_agent_run, args: [:agent_run_id]

      define :list_tasks_by_project, action: :by_project, args: [:project_id]
      define :list_tasks_by_work_item, action: :by_work_item, args: [:work_item_id]
      define :list_tasks_by_work_order, action: :by_work_order, args: [:work_order_id]
      define :list_tasks_by_bid, action: :by_bid, args: [:bid_id]

      define :list_tasks_by_procurement_source,
        action: :by_procurement_source,
        args: [:procurement_source_id]

      define :get_my_tasks_workspace,
        action: :my_tasks_workspace,
        args: [:owner_team_member_id]

      define :list_my_tasks_workspace_items,
        action: :workspace_items,
        args: [:owner_team_member_id]

      define :list_tasks_by_origin,
        action: :by_origin,
        args: [:origin_domain, :origin_resource, :origin_id]

      define :list_overdue_tasks, action: :overdue
      define :list_due_today_tasks, action: :due_today
      define :list_blocked_tasks, action: :blocked

      define :create_task_from_playbook_step, action: :create_from_playbook_step
    end

    resource GnomeGarden.Operations.Playbook do
      define :list_playbooks, action: :read
      define :list_active_playbooks, action: :active
      define :get_playbook, action: :read, get_by: [:id]
      define :get_playbook_by_name, action: :by_name, args: [:name]
      define :create_playbook, action: :create
      define :update_playbook, action: :update
      define :archive_playbook, action: :archive
      define :reactivate_playbook, action: :reactivate
      define :ensure_starter_playbooks, action: :ensure_starters
    end

    resource GnomeGarden.Operations.PlaybookStep do
      define :get_playbook_step, action: :read, get_by: [:id]
      define :create_playbook_step, action: :create
      define :update_playbook_step, action: :update
      define :delete_playbook_step, action: :destroy

      define :list_playbook_steps_for_playbook,
        action: :for_playbook,
        args: [:playbook_id]
    end

    resource GnomeGarden.Operations.PlaybookRun do
      define :list_playbook_runs, action: :read
      define :get_playbook_run, action: :read, get_by: [:id]
      define :apply_playbook, action: :apply
      define :list_playbook_runs_for_pursuit, action: :for_pursuit, args: [:pursuit_id]
      define :list_playbook_runs_for_project, action: :for_project, args: [:project_id]
      define :list_playbook_runs_for_bid, action: :for_bid, args: [:bid_id]

      define :list_playbook_runs_for_procurement_source,
        action: :for_procurement_source,
        args: [:procurement_source_id]

      define :list_playbook_runs_for_organization,
        action: :for_organization,
        args: [:organization_id]

      define :list_playbook_runs_for_signal, action: :for_signal, args: [:signal_id]
    end

    resource GnomeGarden.Operations.MemoryBlock do
      define :list_memory_blocks, action: :read
      define :get_memory_block, action: :read, get_by: [:id]
      define :list_pending_memory_blocks, action: :pending_review
      define :list_active_memory_blocks, action: :active

      define :list_active_memory_blocks_for_scope,
        action: :active_for_scope,
        args: [:scope, :scope_key]

      define :get_memory_block_by_key, action: :by_key, args: [:key, :scope, :scope_key]
      define :create_memory_block, action: :create
      define :propose_memory_block, action: :propose
      define :update_memory_block_content, action: :update_content
      define :activate_memory_block, action: :activate
      define :reject_memory_block, action: :reject
      define :archive_memory_block, action: :archive
      define :delete_memory_block, action: :destroy
    end

    resource GnomeGarden.Operations.MemoryEntry do
      define :list_memory_entries, action: :read
      define :get_memory_entry, action: :read, get_by: [:id]
      define :list_pending_memory_entries, action: :pending_review
      define :propose_memory_entry, action: :propose
      define :approve_memory_entry, action: :approve
      define :reject_memory_entry, action: :reject
      define :expire_memory_entry, action: :expire
      define :archive_memory_entry, action: :archive
      define :mark_memory_entry_used, action: :mark_used

      define :recall_memory_entries_for_scope,
        action: :recall_for_scope,
        args: [:scope, :scope_key]

      define :search_memory_entries_by_tag, action: :search_by_tag, args: [:tag]
      define :list_memory_entries_by_namespace, action: :by_namespace, args: [:namespace]
      define :delete_memory_entry, action: :destroy
    end

    resource GnomeGarden.Operations.LearningRecommendation do
      define :list_learning_recommendations, action: :read
      define :get_learning_recommendation, action: :read, get_by: [:id]
      define :list_pending_learning_recommendations, action: :pending_review

      define :list_learning_recommendations_by_target,
        action: :by_target,
        args: [:target_domain, :target_resource, :target_id]

      define :list_learning_recommendations_by_source_agent_run,
        action: :by_source_agent_run,
        args: [:source_agent_run_id]

      define :propose_learning_recommendation, action: :propose
      define :approve_learning_recommendation, action: :approve
      define :reject_learning_recommendation, action: :reject
      define :apply_learning_recommendation, action: :apply
      define :expire_learning_recommendation, action: :expire
      define :delete_learning_recommendation, action: :destroy
    end
  end

  def current_team_member_id(nil), do: nil

  def current_team_member_id(%{id: user_id} = actor) do
    case get_team_member_by_user(user_id, actor: actor) do
      {:ok, team_member} -> team_member.id
      {:error, _error} -> nil
    end
  end

  def operations_workspace(opts \\ []) do
    GnomeGarden.Operations.Workspace.build(opts)
  end
end
