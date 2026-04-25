defmodule GnomeGarden.Mercury do
  @moduledoc """
  Mercury Bank domain.

  Stores Mercury bank account and transaction data synced from the Mercury API
  and webhooks. The PaymentMatch resource bridges Mercury transactions to
  Finance.Payment records once the payment matcher runs.
  """

  use Ash.Domain,
    otp_app: :gnome_garden,
    extensions: [AshAdmin.Domain]

  admin do
    show? true
  end

  resources do
    resource GnomeGarden.Mercury.Account do
      define :list_mercury_accounts, action: :read
      define :get_mercury_account, action: :read, get_by: [:id]
      define :get_mercury_account_by_mercury_id, action: :read, get_by: [:mercury_id]
      define :create_mercury_account, action: :create
      define :update_mercury_account, action: :update
    end
  end
end
