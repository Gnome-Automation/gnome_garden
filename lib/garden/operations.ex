defmodule GnomeGarden.Operations do
  @moduledoc """
  Foundational operating model domain.

  Owns the durable business entities that CRM, delivery, service, and finance
  hang off: organizations, people, sites, and managed systems.
  """

  use Ash.Domain,
    otp_app: :gnome_garden,
    extensions: [AshAdmin.Domain]

  admin do
    show? true
  end

  resources do
    resource GnomeGarden.Operations.Organization do
      define :list_organizations, action: :read
      define :get_organization, action: :read, get_by: [:id]
      define :create_organization, action: :create
      define :update_organization, action: :update
    end

    resource GnomeGarden.Operations.Person do
      define :list_people, action: :read
      define :get_person, action: :read, get_by: [:id]
      define :create_person, action: :create
      define :update_person, action: :update
      define :list_active_people, action: :active
      define :list_people_for_organization, action: :for_organization
    end

    resource GnomeGarden.Operations.OrganizationAffiliation do
      define :list_organization_affiliations, action: :read
      define :get_organization_affiliation, action: :read, get_by: [:id]
      define :create_organization_affiliation, action: :create
      define :update_organization_affiliation, action: :update
      define :end_organization_affiliation, action: :end_affiliation
      define :list_active_organization_affiliations, action: :active
      define :list_affiliations_for_organization, action: :for_organization
      define :list_affiliations_for_person, action: :for_person
    end

    resource GnomeGarden.Operations.Site do
      define :list_sites, action: :read
      define :get_site, action: :read, get_by: [:id]
      define :create_site, action: :create
      define :update_site, action: :update
      define :list_sites_for_organization, action: :for_organization
    end

    resource GnomeGarden.Operations.ManagedSystem do
      define :list_managed_systems, action: :read
      define :get_managed_system, action: :read, get_by: [:id]
      define :create_managed_system, action: :create
      define :update_managed_system, action: :update
      define :list_managed_systems_for_organization, action: :for_organization
      define :list_managed_systems_for_site, action: :for_site
    end

    resource GnomeGarden.Operations.Asset do
      define :list_assets, action: :read
      define :get_asset, action: :read, get_by: [:id]
      define :create_asset, action: :create
      define :update_asset, action: :update
      define :list_assets_for_managed_system, action: :for_managed_system
      define :list_root_assets, action: :root_assets
    end
  end
end
