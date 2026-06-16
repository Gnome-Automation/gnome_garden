defmodule GnomeGarden.Commercial.CustomerVendorRequirement do
  @moduledoc """
  One customer-specific vendor onboarding requirement.

  Requirements can be fulfilled by a reusable `CompanyDocument` or by a
  non-file instruction such as invoice content rules. Status and rejection
  reasons belong here, not on the reusable company document.
  """

  use Ash.Resource,
    otp_app: :gnome_garden,
    domain: GnomeGarden.Commercial,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshAdmin.Resource],
    notifiers: [Ash.Notifier.PubSub]

  admin do
    table_columns [:title, :requirement_type, :status, :required, :updated_at]
  end

  postgres do
    table "commercial_vendor_requirements"
    repo GnomeGarden.Repo

    custom_indexes do
      index [:customer_vendor_onboarding_id, :sort_order],
        name: "vendor_requirements_onboarding_sort_idx"

      index [:status, :updated_at], name: "vendor_requirements_status_idx"
    end

    identity_index_names unique_onboarding_requirement:
                           "customer_vendor_requirements_onboarding_key_idx"

    references do
      reference :customer_vendor_onboarding,
        on_delete: :delete,
        name: "vendor_requirements_onboarding_fkey"

      reference :company_document,
        on_delete: :nilify,
        name: "vendor_requirements_company_doc_fkey"
    end
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true

      accept [
        :customer_vendor_onboarding_id,
        :company_document_id,
        :key,
        :title,
        :requirement_type,
        :status,
        :required,
        :instructions,
        :sort_order,
        :sent_to_email,
        :sent_at,
        :accepted_at,
        :rejected_at,
        :rejection_reason,
        :waived_at,
        :notes,
        :metadata
      ]
    end

    update :update do
      accept [
        :company_document_id,
        :title,
        :requirement_type,
        :status,
        :required,
        :instructions,
        :sort_order,
        :sent_to_email,
        :sent_at,
        :accepted_at,
        :rejected_at,
        :rejection_reason,
        :waived_at,
        :notes,
        :metadata
      ]
    end

    update :mark_ready do
      accept []
      change set_attribute(:status, :ready)
    end

    update :mark_sent do
      require_atomic? false

      argument :sent_to_email, :string, allow_nil?: false
      argument :notes, :string

      change set_attribute(:status, :sent)
      change set_attribute(:sent_at, &DateTime.utc_now/0)
      change set_attribute(:sent_to_email, arg(:sent_to_email))
      change after_action(&log_delivery(&1, &2, &3, :sent))
    end

    update :accept do
      require_atomic? false

      argument :notes, :string

      change set_attribute(:status, :accepted)
      change set_attribute(:accepted_at, &DateTime.utc_now/0)
      change after_action(&log_delivery(&1, &2, &3, :accepted))
    end

    update :reject do
      require_atomic? false

      argument :rejection_reason, :string, allow_nil?: false

      change set_attribute(:status, :rejected)
      change set_attribute(:rejected_at, &DateTime.utc_now/0)
      change set_attribute(:rejection_reason, arg(:rejection_reason))
      change after_action(&log_delivery(&1, &2, &3, :rejected))
    end

    update :waive do
      require_atomic? false

      argument :notes, :string

      change set_attribute(:status, :waived)
      change set_attribute(:waived_at, &DateTime.utc_now/0)
      change after_action(&log_delivery(&1, &2, &3, :waived))
    end

    read :for_onboarding do
      argument :customer_vendor_onboarding_id, :uuid, allow_nil?: false
      filter expr(customer_vendor_onboarding_id == ^arg(:customer_vendor_onboarding_id))

      prepare build(
                sort: [sort_order: :asc, title: :asc],
                load: [company_document: [:file_url], artifacts: [:file_url], deliveries: []]
              )
    end

    read :by_key do
      argument :customer_vendor_onboarding_id, :uuid, allow_nil?: false
      argument :key, :string, allow_nil?: false
      get? true

      filter expr(
               customer_vendor_onboarding_id == ^arg(:customer_vendor_onboarding_id) and
                 key == ^arg(:key)
             )

      prepare build(load: [company_document: [:file_url], artifacts: [:file_url], deliveries: []])
    end
  end

  pub_sub do
    module GnomeGardenWeb.Endpoint
    prefix "customer_vendor_requirement"

    publish :create, "created"
    publish :update, "updated"
    publish :mark_ready, "updated"
    publish :mark_sent, "updated"
    publish :accept, "updated"
    publish :reject, "updated"
    publish :waive, "updated"
    publish :destroy, "destroyed"
  end

  attributes do
    uuid_primary_key :id

    attribute :key, :string do
      allow_nil? false
      public? true
    end

    attribute :title, :string do
      allow_nil? false
      public? true
    end

    attribute :requirement_type, :atom do
      allow_nil? false
      default :other
      public? true

      constraints one_of: [
                    :company_fact,
                    :tax_document,
                    :banking_document,
                    :terms,
                    :invoice_instruction,
                    :supplier_code,
                    :signature,
                    :other
                  ]
    end

    attribute :status, :atom do
      allow_nil? false
      default :missing
      public? true

      constraints one_of: [:missing, :ready, :sent, :accepted, :rejected, :waived]
    end

    attribute :required, :boolean do
      allow_nil? false
      default true
      public? true
    end

    attribute :instructions, :string do
      public? true
    end

    attribute :sort_order, :integer do
      allow_nil? false
      default 0
      public? true
    end

    attribute :sent_to_email, :string do
      public? true
    end

    attribute :sent_at, :utc_datetime do
      public? true
    end

    attribute :accepted_at, :utc_datetime do
      public? true
    end

    attribute :rejected_at, :utc_datetime do
      public? true
    end

    attribute :rejection_reason, :string do
      public? true
    end

    attribute :waived_at, :utc_datetime do
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
    belongs_to :customer_vendor_onboarding,
               GnomeGarden.Commercial.CustomerVendorOnboarding do
      allow_nil? false
      public? true
    end

    belongs_to :company_document, GnomeGarden.Company.Document do
      public? true
    end

    has_many :deliveries, GnomeGarden.Commercial.CustomerVendorRequirementDelivery do
      public? true
    end

    has_many :artifacts, GnomeGarden.Commercial.CustomerVendorRequirementArtifact do
      public? true
    end
  end

  identities do
    identity :unique_onboarding_requirement, [:customer_vendor_onboarding_id, :key]
  end

  defp log_delivery(changeset, record, context, event_type) do
    attrs =
      %{
        customer_vendor_requirement_id: record.id,
        event_type: event_type,
        recipient_email: Ash.Changeset.get_argument(changeset, :sent_to_email),
        notes: Ash.Changeset.get_argument(changeset, :notes),
        rejection_reason: Ash.Changeset.get_argument(changeset, :rejection_reason)
      }
      |> Enum.reject(fn {_key, value} -> is_nil(value) end)
      |> Map.new()

    case GnomeGarden.Commercial.create_customer_vendor_requirement_delivery(attrs,
           actor: context.actor,
           authorize?: false
         ) do
      {:ok, _delivery} -> {:ok, record}
      {:error, error} -> {:error, error}
    end
  end
end
