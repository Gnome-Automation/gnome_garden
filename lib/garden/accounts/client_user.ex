defmodule GnomeGarden.Accounts.ClientUser do
  @moduledoc """
  Portal authentication resource for client contacts.

  Completely separate from the staff User resource — different token store,
  different session key, different magic link route. One ClientUser row per
  (email, organization_id) pair: a contact at two orgs gets two rows.
  """

  use Ash.Resource,
    otp_app: :gnome_garden,
    domain: GnomeGarden.Accounts,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshAuthentication]

  authentication do
    tokens do
      enabled? true
      token_resource GnomeGarden.Accounts.ClientUserToken
      signing_secret GnomeGarden.Secrets
      store_all_tokens? true
      require_token_presence_for_authentication? true
    end

    strategies do
      magic_link do
        identity_field :email
        registration_enabled? true
        require_interaction? true
        sender GnomeGarden.Accounts.ClientUser.Senders.SendMagicLinkEmail
      end
    end
  end

  postgres do
    table "client_users"
    repo GnomeGarden.Repo

    references do
      reference :organization, on_delete: :delete
    end
  end

  actions do
    defaults [:read]

    read :get_by_subject do
      description "Get a client user by the subject claim in a JWT"
      argument :subject, :string, allow_nil?: false
      get? true
      prepare AshAuthentication.Preparations.FilterBySubject
    end

    create :sign_in_with_magic_link do
      description "Sign in a client user with a magic link token."
      argument :token, :string, allow_nil?: false

      upsert? true
      upsert_identity :unique_email_per_org
      upsert_fields [:email]

      change AshAuthentication.Strategy.MagicLink.SignInChange

      metadata :token, :string do
        allow_nil? false
      end
    end

    action :request_magic_link do
      argument :email, :ci_string, allow_nil?: false
      run AshAuthentication.Strategy.MagicLink.Request
    end

    create :invite do
      description "Upsert a ClientUser for the given email + org."
      accept [:email, :organization_id]
      upsert? true
      upsert_identity :unique_email_per_org
      upsert_fields []
    end
  end

  policies do
    bypass AshAuthentication.Checks.AshAuthenticationInteraction do
      authorize_if always()
    end

    policy action(:invite) do
      authorize_if always()
    end

    policy action_type(:read) do
      authorize_if actor_present()
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :email, :ci_string do
      allow_nil? false
      public? true
    end

    timestamps()
  end

  relationships do
    belongs_to :organization, GnomeGarden.Operations.Organization do
      source_attribute :organization_id
      allow_nil? false
      public? true
    end
  end

  identities do
    identity :unique_email_per_org, [:email, :organization_id]
  end
end
