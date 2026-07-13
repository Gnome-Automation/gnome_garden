defmodule GnomeGarden.Procurement.SourceCredential do
  @moduledoc """
  Stored credentials used by procurement source scanners.

  Secrets are accepted as action arguments, encrypted by a resource change, and
  persisted only as encrypted payloads.
  """

  use Ash.Resource,
    otp_app: :gnome_garden,
    domain: GnomeGarden.Procurement,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshAdmin.Resource, AshLua.Resource],
    notifiers: [Ash.Notifier.PubSub]

  admin do
    table_columns [
      :credential_family,
      :provider,
      :scope,
      :label,
      :username,
      :status,
      :last_verified_at,
      :last_used_at
    ]
  end

  postgres do
    table "procurement_source_credentials"
    repo GnomeGarden.Repo

    custom_indexes do
      index [:credential_family, :status]
      index [:procurement_source_id, :status]
    end

    references do
      reference :procurement_source, on_delete: :delete
    end
  end

  actions do
    defaults [:read]

    create :create do
      primary? true

      accept [
        :provider,
        :credential_family,
        :scope,
        :label,
        :username,
        :procurement_source_id,
        :credential_storage,
        :bitwarden_server_url,
        :bitwarden_organization,
        :bitwarden_collection,
        :bitwarden_item_id,
        :bitwarden_item_name,
        :bitwarden_notes,
        :notes,
        :metadata
      ]

      argument :password, :string, sensitive?: true
      argument :api_key, :string, sensitive?: true

      change GnomeGarden.Procurement.Changes.EncryptSourceCredentialSecret
    end

    update :rotate_secret do
      require_atomic? false
      accept []

      argument :password, :string, sensitive?: true
      argument :api_key, :string, sensitive?: true

      change GnomeGarden.Procurement.Changes.EncryptSourceCredentialSecret
      change set_attribute(:status, :active)
      change set_attribute(:test_status, :untested)
      change set_attribute(:last_failure_reason, nil)
      change GnomeGarden.Procurement.Changes.InvalidateCredentialBrowserSessions
    end

    update :store_in_bitwarden do
      require_atomic? false

      accept [
        :username,
        :bitwarden_server_url,
        :bitwarden_organization,
        :bitwarden_collection,
        :bitwarden_item_id,
        :bitwarden_item_name,
        :bitwarden_notes,
        :notes,
        :metadata
      ]

      change set_attribute(:credential_storage, :bitwarden)
      change set_attribute(:encrypted_password, nil)
      change set_attribute(:password_fingerprint, nil)
      change set_attribute(:password_present, false)
      change set_attribute(:encrypted_api_key, nil)
      change set_attribute(:api_key_fingerprint, nil)
      change set_attribute(:api_key_present, false)
      change set_attribute(:test_status, :untested)
      change set_attribute(:last_failure_reason, nil)
      change GnomeGarden.Procurement.Changes.InvalidateCredentialBrowserSessions
    end

    update :queue_test do
      require_atomic? false
      accept [:last_test_procurement_source_id]

      change set_attribute(:test_status, :queued)
      change set_attribute(:last_test_queued_at, &DateTime.utc_now/0)
      change set_attribute(:last_failure_reason, nil)

      change after_action(fn _changeset, credential, _context ->
               %{
                 "source_credential_id" => credential.id,
                 "procurement_source_id" => credential.last_test_procurement_source_id
               }
               |> GnomeGarden.Procurement.Workers.TestSourceCredential.new()
               |> Oban.insert()
               |> case do
                 {:ok, _job} -> {:ok, credential}
                 {:error, reason} -> {:error, reason}
               end
             end)
    end

    update :mark_test_running do
      accept []

      change set_attribute(:test_status, :testing)
      change set_attribute(:last_test_started_at, &DateTime.utc_now/0)
    end

    update :mark_used do
      accept []

      change set_attribute(:last_used_at, &DateTime.utc_now/0)
    end

    update :mark_verified do
      accept []

      change set_attribute(:status, :active)
      change set_attribute(:test_status, :verified)
      change set_attribute(:last_verified_at, &DateTime.utc_now/0)
      change set_attribute(:last_test_completed_at, &DateTime.utc_now/0)
      change set_attribute(:last_failure_reason, nil)
    end

    update :mark_failed do
      accept [:last_failure_reason]

      change set_attribute(:status, :invalid)
      change set_attribute(:test_status, :invalid)
      change set_attribute(:last_test_completed_at, &DateTime.utc_now/0)
    end

    update :mark_manual_verification_required do
      accept [:last_failure_reason]

      change set_attribute(:status, :active)
      change set_attribute(:test_status, :manual_required)
      change set_attribute(:last_test_completed_at, &DateTime.utc_now/0)
    end

    update :disable do
      require_atomic? false
      accept []

      change set_attribute(:status, :disabled)
      change GnomeGarden.Procurement.Changes.InvalidateCredentialBrowserSessions
    end

    update :compromise do
      require_atomic? false
      accept [:last_failure_reason]
      change set_attribute(:status, :invalid)
      change set_attribute(:test_status, :invalid)

      change {GnomeGarden.Procurement.Changes.InvalidateCredentialBrowserSessions,
              mode: :compromise}
    end

    action :resolve_username_password, :map do
      argument :credential_family, :string, allow_nil?: false
      argument :procurement_source_id, :uuid

      run GnomeGarden.Procurement.Actions.ResolveSourceUsernamePassword
    end

    action :resolve_api_key, :string do
      argument :credential_family, :string, allow_nil?: false

      run GnomeGarden.Procurement.Actions.ResolveSourceApiKey
    end

    action :credential_status, :atom do
      constraints one_of: [:verified, :pending, :invalid, :missing]

      argument :credential_family, :string, allow_nil?: false
      argument :procurement_source_id, :uuid

      run GnomeGarden.Procurement.Actions.SourceCredentialStatus
    end

    read :active_for_source do
      argument :procurement_source_id, :uuid, allow_nil?: false

      filter expr(procurement_source_id == ^arg(:procurement_source_id) and status == :active)
      prepare build(sort: [inserted_at: :desc])
    end

    read :for_source do
      argument :procurement_source_id, :uuid, allow_nil?: false

      filter expr(procurement_source_id == ^arg(:procurement_source_id) and status != :disabled)
      prepare build(sort: [inserted_at: :desc])
    end

    read :active_for_family do
      argument :credential_family, :string, allow_nil?: false

      filter expr(
               credential_family == ^arg(:credential_family) and
                 is_nil(procurement_source_id) and status == :active
             )

      prepare build(sort: [inserted_at: :desc])
    end

    read :for_family do
      argument :credential_family, :string, allow_nil?: false

      filter expr(
               credential_family == ^arg(:credential_family) and
                 is_nil(procurement_source_id) and status != :disabled
             )

      prepare build(sort: [inserted_at: :desc])
    end
  end

  pub_sub do
    module GnomeGardenWeb.Endpoint
    prefix "procurement_source_credential"

    publish :create, "created"
    publish :rotate_secret, "updated"
    publish :store_in_bitwarden, "updated"
    publish :queue_test, "updated"
    publish :mark_test_running, "updated"
    publish :mark_used, "updated"
    publish :mark_verified, "updated"
    publish :mark_failed, "updated"
    publish :mark_manual_verification_required, "updated"
    publish :disable, "updated"
    publish :compromise, "updated"
  end

  attributes do
    uuid_primary_key :id

    attribute :provider, :atom do
      allow_nil? false
      default :custom
      public? true
      constraints one_of: [:planetbids, :publicpurchase, :sam_gov, :bidnet, :opengov, :custom]
    end

    attribute :credential_family, :string do
      allow_nil? false
      public? true
    end

    attribute :scope, :atom do
      allow_nil? false
      default :family
      public? true
      constraints one_of: [:family, :source]
    end

    attribute :label, :string do
      allow_nil? false
      default "Default"
      public? true
    end

    attribute :username, :string do
      public? true
      sensitive? true
    end

    attribute :credential_storage, :atom do
      allow_nil? false
      default :local_encrypted
      public? true
      constraints one_of: [:local_encrypted, :bitwarden]
    end

    attribute :bitwarden_server_url, :string do
      public? true
    end

    attribute :bitwarden_organization, :string do
      public? true
    end

    attribute :bitwarden_collection, :string do
      public? true
    end

    attribute :bitwarden_item_id, :string do
      public? true
      sensitive? true
    end

    attribute :bitwarden_item_name, :string do
      public? true
    end

    attribute :bitwarden_notes, :string do
      public? true
    end

    attribute :encrypted_password, :map do
      sensitive? true
    end

    attribute :password_fingerprint, :string do
      sensitive? true
    end

    attribute :password_present, :boolean do
      allow_nil? false
      default false
      public? true
    end

    attribute :encrypted_api_key, :map do
      sensitive? true
    end

    attribute :api_key_fingerprint, :string do
      sensitive? true
    end

    attribute :api_key_present, :boolean do
      allow_nil? false
      default false
      public? true
    end

    attribute :status, :atom do
      allow_nil? false
      default :active
      public? true
      constraints one_of: [:active, :invalid, :disabled]
    end

    attribute :test_status, :atom do
      allow_nil? false
      default :untested
      public? true
      constraints one_of: [:untested, :queued, :testing, :verified, :invalid, :manual_required]
    end

    attribute :last_verified_at, :utc_datetime do
      public? true
    end

    attribute :last_test_queued_at, :utc_datetime do
      public? true
    end

    attribute :last_test_started_at, :utc_datetime do
      public? true
    end

    attribute :last_test_completed_at, :utc_datetime do
      public? true
    end

    attribute :last_test_procurement_source_id, :uuid do
      public? true
    end

    attribute :last_used_at, :utc_datetime do
      public? true
    end

    attribute :last_failure_reason, :string do
      public? true
    end

    attribute :last_rotated_at, :utc_datetime do
      public? true
    end

    attribute :notes, :string do
      public? true
    end

    attribute :metadata, :map do
      allow_nil? false
      default %{}
      public? true
    end

    timestamps()
  end

  relationships do
    belongs_to :procurement_source, GnomeGarden.Procurement.ProcurementSource do
      public? true
    end

    has_many :browser_sessions, GnomeGarden.Procurement.SourceBrowserSession do
      destination_attribute :source_credential_id
      public? true
    end
  end
end
