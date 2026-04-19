defmodule GnomeGarden.Accounts do
  use Ash.Domain, otp_app: :gnome_garden, extensions: [AshAdmin.Domain]

  admin do
    show? true
  end

  resources do
    resource GnomeGarden.Accounts.Token

    resource GnomeGarden.Accounts.User do
      define :list_users, action: :read
      define :get_user, action: :read, get_by: [:id]
      define :get_user_by_email, action: :get_by_email, args: [:email]
    end
  end
end
