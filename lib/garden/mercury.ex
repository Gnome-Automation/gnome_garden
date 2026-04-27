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

    resource GnomeGarden.Mercury.Transaction do
      define :list_mercury_transactions, action: :read
      define :get_mercury_transaction, action: :read, get_by: [:id]
      define :get_mercury_transaction_by_mercury_id, action: :read, get_by: [:mercury_id]
      define :create_mercury_transaction, action: :create
      define :update_mercury_transaction, action: :update
    end

    resource GnomeGarden.Mercury.PaymentMatch do
      define :list_payment_matches, action: :read
      define :get_payment_match, action: :read, get_by: [:id]
      define :create_payment_match, action: :create
      define :delete_payment_match, action: :destroy, default_options: [return_destroyed?: true]
    end
  end
end
