defmodule GnomeHub.Accounts do
  use Ash.Domain, otp_app: :gnome_hub, extensions: [AshAdmin.Domain]

  admin do
    show? true
  end

  resources do
    resource GnomeHub.Accounts.Token
    resource GnomeHub.Accounts.User
  end
end
