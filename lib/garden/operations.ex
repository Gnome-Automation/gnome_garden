defmodule GnomeGarden.Operations do
  @moduledoc """
  Foundational operating model domain.

  Owns the durable business entities that CRM, delivery, service, and finance
  hang off: organizations, sites, and managed systems.
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
  end
end
