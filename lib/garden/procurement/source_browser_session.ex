defmodule GnomeGarden.Procurement.SourceBrowserSession do
  @moduledoc """
  Durable metadata for authenticated browser sessions used by procurement portals.

  Playwright `storageState` files contain cookies and tokens, so this resource
  stores only the path and audit metadata. The file content is managed by the
  browser automation boundary and must be treated as secret runtime state.
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
      reference :source_credential, on_delete: :nilify
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
        :status,
        :browser_name,
        :storage_state_path,
        :storage_state_fingerprint,
        :verified_at,
        :expires_at,
        :last_refresh_started_at,
        :last_refresh_completed_at,
        :last_failure_reason,
        :trace_path,
        :screenshot_path,
        :metadata
      ]
    end

    update :update do
      accept [
        :source_credential_id,
        :provider,
        :session_family,
        :status,
        :browser_name,
        :storage_state_path,
        :storage_state_fingerprint,
        :verified_at,
        :expires_at,
        :last_refresh_started_at,
        :last_refresh_completed_at,
        :last_failure_reason,
        :trace_path,
        :screenshot_path,
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
      accept [
        :storage_state_path,
        :storage_state_fingerprint,
        :verified_at,
        :expires_at,
        :trace_path,
        :screenshot_path,
        :metadata
      ]

      change set_attribute(:status, :valid)
      change set_attribute(:verified_at, &DateTime.utc_now/0)
      change set_attribute(:last_refresh_completed_at, &DateTime.utc_now/0)
      change set_attribute(:last_failure_reason, nil)
    end

    update :mark_failed do
      accept [:last_failure_reason, :trace_path, :screenshot_path, :metadata]

      change set_attribute(:status, :invalid)
      change set_attribute(:last_refresh_completed_at, &DateTime.utc_now/0)
    end

    update :expire do
      accept [:last_failure_reason]

      change set_attribute(:status, :expired)
    end

    update :disable do
      accept [:last_failure_reason]

      change set_attribute(:status, :disabled)
    end

    read :for_source do
      argument :procurement_source_id, :uuid, allow_nil?: false

      filter expr(procurement_source_id == ^arg(:procurement_source_id))
      prepare build(sort: [updated_at: :desc])
    end

    read :valid_for_source do
      argument :procurement_source_id, :uuid, allow_nil?: false

      filter expr(procurement_source_id == ^arg(:procurement_source_id) and status == :valid)
      prepare build(sort: [verified_at: :desc])
    end
  end

  pub_sub do
    module GnomeGardenWeb.Endpoint
    prefix "procurement_source_browser_session"

    publish :create, "created"
    publish :update, "updated"
    publish :mark_refreshing, "updated"
    publish :mark_valid, "updated"
    publish :mark_failed, "updated"
    publish :expire, "updated"
    publish :disable, "updated"
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
      constraints one_of: [:pending, :refreshing, :valid, :invalid, :expired, :disabled]
    end

    attribute :browser_name, :string do
      allow_nil? false
      default "chromium"
      public? true
    end

    attribute :storage_state_path, :string do
      sensitive? true
      public? true
    end

    attribute :storage_state_fingerprint, :string do
      sensitive? true
    end

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

    attribute :trace_path, :string do
      public? true
    end

    attribute :screenshot_path, :string do
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
