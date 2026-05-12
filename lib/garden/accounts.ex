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
      define :create_user_with_password, action: :create_with_password
      define :set_user_password, action: :set_password
      define :sign_in_user, action: :sign_in_with_password
      define :request_password_reset, action: :request_password_reset_with_password
      define :reset_password, action: :password_reset_with_password
    end
  end
end
