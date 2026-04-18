defmodule GnomeGarden.Sales do
  @moduledoc """
  Sales domain for CRM and pipeline management.

  Manages companies, contacts, activities, and notes — the relationship
  management side of the business. Pipeline resources (Opportunity,
  Proposal, Contract) will be added in a future phase.
  """

  use Ash.Domain,
    otp_app: :gnome_garden,
    extensions: [AshAdmin.Domain, AshPhoenix]

  admin do
    show? true
  end

  resources do
    resource GnomeGarden.Sales.Industry

    resource GnomeGarden.Sales.Company do
      define :list_companies, action: :read
      define :get_company, action: :read, get_by: [:id]
      define :create_company, action: :create
      define :update_company, action: :update
    end

    resource GnomeGarden.Sales.Contact do
      define :list_contacts, action: :read
      define :get_contact, action: :read, get_by: [:id]
      define :create_contact, action: :create
      define :update_contact, action: :update
    end

    resource GnomeGarden.Sales.Activity
    resource GnomeGarden.Sales.Note

    resource GnomeGarden.Sales.Event do
      define :log_event, action: :log
    end

    resource GnomeGarden.Sales.Address
    resource GnomeGarden.Sales.CompanyRelationship

    resource GnomeGarden.Sales.Task do
      define :list_tasks, action: :read
      define :get_task, action: :read, get_by: [:id]
      define :create_task, action: :create
      define :update_task, action: :update
    end

    resource GnomeGarden.Sales.Opportunity do
      define :list_opportunities, action: :read
      define :get_opportunity, action: :read, get_by: [:id]
      define :create_opportunity, action: :create
      define :update_opportunity, action: :update
      define :advance_to_review, action: :advance_to_review
      define :advance_to_qualification, action: :advance_to_qualification
      define :advance_to_drafting, action: :advance_to_drafting
      define :advance_to_submitted, action: :advance_to_submitted
      define :advance_to_research, action: :advance_to_research
      define :advance_to_outreach, action: :advance_to_outreach
      define :advance_to_meeting, action: :advance_to_meeting
      define :advance_to_proposal, action: :advance_to_proposal
      define :advance_to_negotiation, action: :advance_to_negotiation
      define :close_opportunity_won, action: :close_won
      define :close_opportunity_lost, action: :close_lost
    end

    resource GnomeGarden.Sales.Lead do
      define :list_leads, action: :read
      define :get_lead, action: :read, get_by: [:id]
      define :create_lead, action: :create
      define :update_lead, action: :update
      define :quick_add_lead, action: :quick_add
    end

    resource GnomeGarden.Sales.ResearchRequest
    resource GnomeGarden.Sales.ResearchLink
    resource GnomeGarden.Sales.Employment
  end
end
