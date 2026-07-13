defmodule GnomeGarden.Procurement.SourceBrowserSession do
  @moduledoc """
  Durable metadata for authenticated browser sessions used by procurement portals.

  Playwright `storageState` contains cookies and tokens. It is encrypted with
  authenticated source/credential identity and is never persisted as a path.
  """

  use Ash.Resource,
    otp_app: :gnome_garden,
    domain: GnomeGarden.Procurement,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshAdmin.Resource, AshLua.Resource],
    notifiers: [Ash.Notifier.PubSub]

  admin do
    table_columns [
      :provider,
      :session_family,
      :status,
      :procurement_source_id,
      :source_credential_id,
      :verified_at,
      :expires_at
    ]
  end

  postgres do
    table "procurement_source_browser_sessions"
    repo GnomeGarden.Repo

    custom_indexes do
      index [:procurement_source_id, :provider, :status]
      index [:source_credential_id, :status]
      index [:session_family, :status]
    end

    references do
      reference :procurement_source, on_delete: :delete
      reference :source_credential, on_delete: :restrict
    end
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true

      accept [
        :procurement_source_id,
        :source_credential_id,
        :provider,
        :session_family,
        :browser_name,
        :verified_at,
        :expires_at,
        :last_refresh_started_at,
        :last_refresh_completed_at,
        :last_failure_reason,
        :metadata
      ]
    end

    update :mark_refreshing do
      accept [:source_credential_id]

      change set_attribute(:status, :refreshing)
      change set_attribute(:last_refresh_started_at, &DateTime.utc_now/0)
      change set_attribute(:last_failure_reason, nil)
    end

    update :mark_valid do
      require_atomic? false

      accept [
        :expires_at,
        :metadata
      ]

      argument :storage_state, :string, allow_nil?: false, sensitive?: true

      change GnomeGarden.Procurement.Changes.EncryptBrowserSessionState
      change set_attribute(:status, :valid)
      change set_attribute(:verified_at, &DateTime.utc_now/0)
      change set_attribute(:last_refresh_completed_at, &DateTime.utc_now/0)
      change set_attribute(:last_failure_reason, nil)
    end

    update :mark_failed do
      accept [:last_failure_reason, :metadata]

      change set_attribute(:status, :invalid)
      change set_attribute(:encrypted_storage_state, nil)
      change set_attribute(:credential_fingerprint, nil)
      change set_attribute(:last_refresh_completed_at, &DateTime.utc_now/0)
    end

    update :expire do
      accept [:last_failure_reason]

      change set_attribute(:status, :expired)
      change set_attribute(:encrypted_storage_state, nil)
      change set_attribute(:credential_fingerprint, nil)
    end

    update :disable do
      accept [:last_failure_reason]

      change set_attribute(:status, :disabled)
      change set_attribute(:encrypted_storage_state, nil)
      change set_attribute(:credential_fingerprint, nil)
    end

    update :compromise do
      accept [:last_failure_reason]
      change set_attribute(:status, :compromised)
      change set_attribute(:encrypted_storage_state, nil)
      change set_attribute(:credential_fingerprint, nil)
    end

    action :resolve_storage_state, :string do
      argument :session_id, :uuid, allow_nil?: false
      argument :procurement_source_id, :uuid, allow_nil?: false
      argument :source_credential_id, :uuid, allow_nil?: false
      run GnomeGarden.Procurement.Actions.ResolveBrowserSessionState
    end

    read :for_source do
      argument :procurement_source_id, :uuid, allow_nil?: false

      filter expr(procurement_source_id == ^arg(:procurement_source_id))
      prepare build(sort: [updated_at: :desc])
    end

    read :valid_for_source do
      argument :procurement_source_id, :uuid, allow_nil?: false

      filter expr(
               procurement_source_id == ^arg(:procurement_source_id) and status == :valid and
                 expires_at > now() and not is_nil(encrypted_storage_state)
             )

      prepare build(sort: [verified_at: :desc])
    end

    read :latest_for_source do
      argument :procurement_source_id, :uuid, allow_nil?: false

      filter expr(procurement_source_id == ^arg(:procurement_source_id))
      prepare build(sort: [updated_at: :desc], limit: 1)
    end

    read :for_credential do
      argument :source_credential_id, :uuid, allow_nil?: false
      filter expr(source_credential_id == ^arg(:source_credential_id))
      prepare build(sort: [updated_at: :desc])
    end
  end

  pub_sub do
    module GnomeGardenWeb.Endpoint
    prefix "procurement_source_browser_session"

    publish :create, "created"
    publish :mark_refreshing, "updated"
    publish :mark_valid, "updated"
    publish :mark_failed, "updated"
    publish :expire, "updated"
    publish :disable, "updated"
    publish :compromise, "updated"
    publish :destroy, "destroyed"
  end

  attributes do
    uuid_primary_key :id

    attribute :provider, :atom do
      allow_nil? false
      public? true
      constraints one_of: [:planetbids, :publicpurchase, :bidnet, :opengov, :custom]
    end

    attribute :session_family, :string do
      allow_nil? false
      public? true
    end

    attribute :status, :atom do
      allow_nil? false
      default :pending
      public? true

      constraints one_of: [
                    :pending,
                    :refreshing,
                    :valid,
                    :invalid,
                    :expired,
                    :compromised,
                    :disabled
                  ]
    end

    attribute :browser_name, :string do
      allow_nil? false
      default "chromium"
      public? true
    end

    attribute :encrypted_storage_state, :map, sensitive?: true

    attribute :storage_state_fingerprint, :string do
      sensitive? true
    end

    attribute :credential_fingerprint, :string, sensitive?: true

    attribute :verified_at, :utc_datetime do
      public? true
    end

    attribute :expires_at, :utc_datetime do
      public? true
    end

    attribute :last_refresh_started_at, :utc_datetime do
      public? true
    end

    attribute :last_refresh_completed_at, :utc_datetime do
      public? true
    end

    attribute :last_failure_reason, :string do
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
      allow_nil? false
      public? true
    end

    belongs_to :source_credential, GnomeGarden.Procurement.SourceCredential do
      public? true
    end
  end
end
