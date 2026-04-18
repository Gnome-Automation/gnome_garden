defmodule GnomeGarden.Execution do
  @moduledoc """
  Execution operating model domain.

  Owns project delivery and service execution records that fulfill commercial
  agreements against organizations, sites, and managed systems.
  """

  use Ash.Domain,
    otp_app: :gnome_garden,
    extensions: [AshAdmin.Domain]

  admin do
    show? true
  end

  resources do
    resource GnomeGarden.Execution.Project do
      define :list_projects, action: :read
      define :get_project, action: :read, get_by: [:id]
      define :create_project, action: :create
      define :update_project, action: :update
      define :approve_project, action: :approve
      define :start_project, action: :start
      define :hold_project, action: :hold
      define :complete_project, action: :complete
      define :cancel_project, action: :cancel
      define :reopen_project, action: :reopen
      define :list_active_projects, action: :active
      define :list_projects_for_organization, action: :for_organization
    end

    resource GnomeGarden.Execution.WorkItem do
      define :list_work_items, action: :read
      define :get_work_item, action: :read, get_by: [:id]
      define :create_work_item, action: :create
      define :update_work_item, action: :update
      define :ready_work_item, action: :ready
      define :start_work_item, action: :start
      define :block_work_item, action: :block
      define :review_work_item, action: :review
      define :complete_work_item, action: :complete
      define :cancel_work_item, action: :cancel
      define :reopen_work_item, action: :reopen
      define :list_open_work_items, action: :open
      define :list_work_items_for_project, action: :for_project
    end

    resource GnomeGarden.Execution.WorkOrder do
      define :list_work_orders, action: :read
      define :get_work_order, action: :read, get_by: [:id]
      define :create_work_order, action: :create
      define :update_work_order, action: :update
      define :schedule_work_order, action: :schedule
      define :dispatch_work_order, action: :dispatch
      define :start_work_order, action: :start
      define :complete_work_order, action: :complete
      define :cancel_work_order, action: :cancel
      define :reopen_work_order, action: :reopen
      define :list_open_work_orders, action: :open
      define :list_work_orders_for_organization, action: :for_organization
    end

    resource GnomeGarden.Execution.MaintenancePlan do
      define :list_maintenance_plans, action: :read
      define :get_maintenance_plan, action: :read, get_by: [:id]
      define :create_maintenance_plan, action: :create
      define :update_maintenance_plan, action: :update
      define :suspend_maintenance_plan, action: :suspend
      define :activate_maintenance_plan, action: :activate
      define :retire_maintenance_plan, action: :retire
      define :reopen_maintenance_plan, action: :reopen
      define :record_maintenance_completion, action: :record_completion
      define :list_active_maintenance_plans, action: :active
      define :list_due_soon_maintenance_plans, action: :due_soon
      define :list_maintenance_plans_for_asset, action: :for_asset
    end
  end
end
