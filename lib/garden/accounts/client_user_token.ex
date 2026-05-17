defmodule GnomeGarden.Accounts.ClientUserToken do
  @moduledoc """
  Token store for ClientUser magic links.
  Required by AshAuthentication — must be separate from the staff Token.
  """

  use Ash.Resource,
    otp_app: :gnome_garden,
    domain: GnomeGarden.Accounts,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshAuthentication.TokenResource]

  postgres do
    table "client_user_tokens"
    repo GnomeGarden.Repo
  end

  actions do
    defaults [:read]

    read :expired do
      description "Look up all expired tokens."
      filter expr(expires_at < now())
    end

    read :get_token do
      description "Look up a token by JTI or token, and an optional purpose."
      get? true
      argument :token, :string, sensitive?: true
      argument :jti, :string, sensitive?: true
      argument :purpose, :string, sensitive?: false
      prepare AshAuthentication.TokenResource.GetTokenPreparation
    end

    action :revoked?, :boolean do
      description "Returns true if a revocation token is found for the provided token"
      argument :token, :string, sensitive?: true
      argument :jti, :string, sensitive?: true
      run AshAuthentication.TokenResource.IsRevoked
    end

    create :revoke_token do
      accept [:extra_data]
      argument :token, :string, allow_nil?: false, sensitive?: true
      change AshAuthentication.TokenResource.RevokeTokenChange
    end

    create :revoke_jti do
      accept [:extra_data]
      argument :subject, :string, allow_nil?: false, sensitive?: true
      argument :jti, :string, allow_nil?: false, sensitive?: true
      change AshAuthentication.TokenResource.RevokeJtiChange
    end

    create :store_token do
      accept [:extra_data, :purpose]
      argument :token, :string, allow_nil?: false, sensitive?: true
      change AshAuthentication.TokenResource.StoreTokenChange
    end

    destroy :expunge_expired do
      change filter expr(expires_at < now())
    end

    update :revoke_all_stored_for_subject do
      accept [:extra_data]
      argument :subject, :string, allow_nil?: false, sensitive?: true
      change AshAuthentication.TokenResource.RevokeAllStoredForSubjectChange
    end
  end

  policies do
    bypass AshAuthentication.Checks.AshAuthenticationInteraction do
      authorize_if always()
    end
  end

  attributes do
    attribute :jti, :string do
      primary_key? true
      public? true
      allow_nil? false
      sensitive? true
    end

    attribute :subject, :string do
      allow_nil? false
      public? true
    end

    attribute :expires_at, :utc_datetime do
      allow_nil? false
      public? true
    end

    attribute :purpose, :string do
      allow_nil? false
      public? true
    end

    attribute :extra_data, :map do
      public? true
    end

    create_timestamp :created_at
    update_timestamp :updated_at
  end
end
