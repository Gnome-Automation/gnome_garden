defmodule GnomeGarden.Accounts.User do
  use Ash.Resource,
    otp_app: :gnome_garden,
    domain: GnomeGarden.Accounts,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshAuthentication]

  authentication do
    add_ons do
      log_out_everywhere do
        apply_on_password_change? true
      end
    end

    tokens do
      enabled? true
      token_resource GnomeGarden.Accounts.Token
      signing_secret GnomeGarden.Secrets
      store_all_tokens? true
      require_token_presence_for_authentication? true
    end

    strategies do
      password :password do
        identity_field :email
        hashed_password_field :hashed_password
        registration_enabled? false

        resettable do
          sender GnomeGarden.Accounts.User.Senders.SendPasswordResetEmail
        end
      end

      remember_me :remember_me
    end
  end

  postgres do
    table "users"
    repo GnomeGarden.Repo
  end

  actions do
    defaults [:read]

    read :get_by_subject do
      description "Get a user by the subject claim in a JWT"
      argument :subject, :string, allow_nil?: false
      get? true
      prepare AshAuthentication.Preparations.FilterBySubject
    end

    read :get_by_email do
      description "Looks up a user by their email"
      get_by :email
    end

    create :create_with_password do
      description "Create an operator sign-in account with a password."
      accept [:email]

      argument :password, :string do
        allow_nil? false
        constraints min_length: 8
        sensitive? true
      end

      argument :password_confirmation, :string do
        allow_nil? false
        constraints min_length: 8
        sensitive? true
      end

      change set_context(%{strategy_name: :password})
      validate AshAuthentication.Strategy.Password.PasswordConfirmationValidation
      change AshAuthentication.Strategy.Password.HashPasswordChange
    end

    update :set_password do
      description "Set or rotate a user's password."
      accept []

      argument :password, :string do
        allow_nil? false
        constraints min_length: 8
        sensitive? true
      end

      argument :password_confirmation, :string do
        allow_nil? false
        constraints min_length: 8
        sensitive? true
      end

      change set_context(%{strategy_name: :password})
      validate AshAuthentication.Strategy.Password.PasswordConfirmationValidation
      change AshAuthentication.Strategy.Password.HashPasswordChange
    end
  end

  policies do
    bypass AshAuthentication.Checks.AshAuthenticationInteraction do
      authorize_if always()
    end

    policy action [
             :create_with_password,
             :set_password,
             :sign_in_with_password,
             :sign_in_with_token,
             :request_password_reset_with_password,
             :password_reset_with_password
           ] do
      authorize_if always()
    end

    policy action [:read, :get_by_subject, :get_by_email] do
      authorize_if actor_present()
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :email, :ci_string do
      allow_nil? false
      public? true
    end

    attribute :hashed_password, :string do
      allow_nil? false
      sensitive? true
    end
  end

  identities do
    identity :unique_email, [:email]
  end
end
