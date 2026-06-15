defmodule GnomeGarden.Commercial.CustomerVendorRequirementDelivery do
  @moduledoc """
  Audit trail for customer vendor requirement fulfillment events.
  """

  use Ash.Resource,
    otp_app: :gnome_garden,
    domain: GnomeGarden.Commercial,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshAdmin.Resource],
    notifiers: [Ash.Notifier.PubSub]

  admin do
    table_columns [:customer_vendor_requirement_id, :event_type, :recipient_email, :occurred_at]
  end

  postgres do
    table "commercial_vendor_requirement_deliveries"
    repo GnomeGarden.Repo

    custom_indexes do
      index [:customer_vendor_requirement_id, :occurred_at],
        name: "vendor_req_deliveries_requirement_idx"

      index [:event_type, :occurred_at], name: "vendor_req_deliveries_event_idx"
    end

    references do
      reference :customer_vendor_requirement,
        on_delete: :delete,
        name: "vendor_req_deliveries_requirement_fkey"
    end
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true

      accept [
        :customer_vendor_requirement_id,
        :event_type,
        :recipient_email,
        :notes,
        :rejection_reason,
        :occurred_at,
        :metadata
      ]

      change set_new_attribute(:occurred_at, &DateTime.utc_now/0)
    end

    read :for_requirement do
      argument :customer_vendor_requirement_id, :uuid, allow_nil?: false
      filter expr(customer_vendor_requirement_id == ^arg(:customer_vendor_requirement_id))
      prepare build(sort: [occurred_at: :desc])
    end
  end

  pub_sub do
    module GnomeGardenWeb.Endpoint
    prefix "customer_vendor_requirement_delivery"

    publish :create, "created"
    publish :destroy, "destroyed"
  end

  attributes do
    uuid_primary_key :id

    attribute :event_type, :atom do
      allow_nil? false
      public? true
      constraints one_of: [:sent, :accepted, :rejected, :waived, :note]
    end

    attribute :recipient_email, :string do
      public? true
    end

    attribute :notes, :string do
      public? true
    end

    attribute :rejection_reason, :string do
      public? true
    end

    attribute :occurred_at, :utc_datetime do
      allow_nil? false
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
    belongs_to :customer_vendor_requirement,
               GnomeGarden.Commercial.CustomerVendorRequirement do
      allow_nil? false
      public? true
    end
  end
end
