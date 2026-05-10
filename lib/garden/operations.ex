defmodule GnomeGarden.Operations do
  @moduledoc """
  Foundational operating model domain.

  Owns the durable business entities that commercial work, delivery, service,
  and finance hang off: organizations, people, sites, and managed systems.
  """

  use Ash.Domain,
    otp_app: :gnome_garden,
    extensions: [AshAdmin.Domain]

  admin do
    show? true
  end

  resources do
    resource GnomeGarden.Operations.TeamMember do
      define :list_team_members, action: :read
      define :list_active_team_members, action: :active
      define :get_team_member, action: :read, get_by: [:id]
      define :get_team_member_by_user, action: :by_user, args: [:user_id]
      define :create_team_member, action: :create
      define :update_team_member, action: :update
      define :delete_team_member, action: :destroy
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
  end
end
