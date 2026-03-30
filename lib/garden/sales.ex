defmodule GnomeGarden.Sales do
  @moduledoc """
  Sales domain for CRM and pipeline management.

  Manages companies, contacts, activities, and notes — the relationship
  management side of the business. Pipeline resources (Opportunity,
  Proposal, Contract) will be added in a future phase.
  """

  use Ash.Domain,
    otp_app: :gnome_garden,
    extensions: [AshAdmin.Domain]

  admin do
    show? true
  end

  resources do
    resource GnomeGarden.Sales.Industry

    resource GnomeGarden.Sales.Company do
      define :list_companies, action: :read
      define :get_company, action: :read, get_by: [:id]
    end

    resource GnomeGarden.Sales.Contact do
      define :list_contacts, action: :read
      define :get_contact, action: :read, get_by: [:id]
    end

    resource GnomeGarden.Sales.Activity
    resource GnomeGarden.Sales.Note
    resource GnomeGarden.Sales.Address
    resource GnomeGarden.Sales.CompanyRelationship

    resource GnomeGarden.Sales.Task do
      define :list_tasks, action: :read
      define :get_task, action: :read, get_by: [:id]
    end

    resource GnomeGarden.Sales.Opportunity do
      define :list_opportunities, action: :read
      define :get_opportunity, action: :read, get_by: [:id]
    end

    resource GnomeGarden.Sales.Lead do
      define :list_leads, action: :read
      define :get_lead, action: :read, get_by: [:id]
    end

    resource GnomeGarden.Sales.ResearchRequest
    resource GnomeGarden.Sales.Employment
  end
end
