defmodule GnomeGarden.Accounts do
  use Ash.Domain, otp_app: :gnome_garden, extensions: [AshAdmin.Domain]

  admin do
    show? true
  end

  resources do
    resource GnomeGarden.Accounts.Token
    resource GnomeGarden.Accounts.User
  end
end
