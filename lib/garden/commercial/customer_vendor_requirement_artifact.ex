defmodule GnomeGarden.Commercial.CustomerVendorRequirementArtifact do
  @moduledoc """
  Customer-specific file artifact for a vendor onboarding requirement.

  Reusable Gnome documents stay in the Company domain. This resource owns the
  customer-specific source forms, generated drafts, signed copies, approved PDFs,
  and sent copies that belong to one onboarding requirement.
  """

  use Ash.Resource,
    otp_app: :gnome_garden,
    domain: GnomeGarden.Commercial,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshAdmin.Resource, AshStorage],
    notifiers: [Ash.Notifier.PubSub]

  admin do
    table_columns [:title, :kind, :status, :uploaded_at, :updated_at]
  end

  postgres do
    table "commercial_vendor_requirement_artifacts"
    repo GnomeGarden.Repo

    custom_indexes do
      index [:customer_vendor_requirement_id, :kind],
        name: "vendor_requirement_artifacts_requirement_kind_idx"

      index [:status, :updated_at], name: "vendor_requirement_artifacts_status_idx"
    end

    references do
      reference :customer_vendor_requirement,
        on_delete: :delete,
        name: "vendor_requirement_artifacts_requirement_fkey"
    end
  end

  storage do
    service({AshStorage.Service.Disk, root: "priv/storage", base_url: "/storage"})
    blob_resource(GnomeGarden.Commercial.CustomerVendorRequirementArtifactBlob)
    attachment_resource(GnomeGarden.Commercial.CustomerVendorRequirementArtifactAttachment)

    has_one_attached :file do
      analyzer(GnomeGarden.Acquisition.Analyzers.DocumentCLI)
    end
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true

      accept [
        :customer_vendor_requirement_id,
        :title,
        :kind,
        :status,
        :notes,
        :metadata
      ]

      argument :file, Ash.Type.File, allow_nil?: false

      change set_new_attribute(:uploaded_at, &DateTime.utc_now/0)
      change {AshStorage.Changes.HandleFileArgument, argument: :file, attachment: :file}
      change after_action(&create_source_form_review_task/3)
    end

    update :update do
      require_atomic? false

      accept [
        :title,
        :kind,
        :status,
        :notes,
        :metadata
      ]

      argument :file, Ash.Type.File, allow_nil?: true

      change {AshStorage.Changes.HandleFileArgument, argument: :file, attachment: :file}
    end

    update :mark_extracted do
      accept [:metadata]
      change set_attribute(:status, :extracted)
    end

    update :mark_drafted do
      accept [:metadata]
      change set_attribute(:status, :drafted)
    end

    update :mark_signed do
      accept [:metadata]
      change set_attribute(:status, :signed)
    end

    update :approve do
      accept [:metadata]
      change set_attribute(:status, :approved)
      change set_attribute(:approved_at, &DateTime.utc_now/0)
    end

    update :reject do
      accept [:notes, :metadata]
      change set_attribute(:status, :rejected)
    end

    update :mark_sent do
      accept [:metadata]
      change set_attribute(:status, :sent)
      change set_attribute(:sent_at, &DateTime.utc_now/0)
    end

    action :populate_source_form, :map do
      argument :artifact_id, :uuid, allow_nil?: false
      run GnomeGarden.Commercial.Actions.PopulateVendorRequirementArtifact
    end

    read :for_requirement do
      argument :customer_vendor_requirement_id, :uuid, allow_nil?: false
      filter expr(customer_vendor_requirement_id == ^arg(:customer_vendor_requirement_id))

      prepare build(
                sort: [uploaded_at: :desc, inserted_at: :desc],
                load: [:file_url, file: :blob]
              )
    end
  end

  pub_sub do
    module GnomeGardenWeb.Endpoint
    prefix "customer_vendor_requirement_artifact"

    publish :create, "created"
    publish :update, "updated"
    publish :mark_extracted, "updated"
    publish :mark_drafted, "updated"
    publish :mark_signed, "updated"
    publish :approve, "updated"
    publish :reject, "updated"
    publish :mark_sent, "updated"
    publish :destroy, "destroyed"
  end

  attributes do
    uuid_primary_key :id

    attribute :title, :string do
      allow_nil? false
      public? true
    end

    attribute :kind, :atom do
      allow_nil? false
      default :source_form
      public? true

      constraints one_of: [
                    :source_form,
                    :extracted_text,
                    :filled_docx,
                    :signed_docx,
                    :approved_pdf,
                    :sent_copy,
                    :supporting
                  ]
    end

    attribute :status, :atom do
      allow_nil? false
      default :uploaded
      public? true

      constraints one_of: [
                    :uploaded,
                    :analyzing,
                    :extracted,
                    :drafted,
                    :signed,
                    :approved,
                    :sent,
                    :rejected
                  ]
    end

    attribute :notes, :string do
      public? true
    end

    attribute :uploaded_at, :utc_datetime do
      public? true
    end

    attribute :approved_at, :utc_datetime do
      public? true
    end

    attribute :sent_at, :utc_datetime do
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

  defp create_source_form_review_task(_changeset, %{kind: :source_form} = artifact, context) do
    requirement =
      artifact.customer_vendor_requirement_id
      |> GnomeGarden.Commercial.get_customer_vendor_requirement!(
        actor: context.actor,
        authorize?: false,
        load: [customer_vendor_onboarding: []]
      )

    onboarding = requirement.customer_vendor_onboarding

    {:ok, _task} =
      GnomeGarden.Operations.create_task(
        %{
          title: "Review vendor form: #{requirement.title}",
          description:
            "Extract, map, fill, sign, and approve the uploaded customer vendor form artifact.",
          priority: :high,
          task_type: :review,
          origin_domain: :commercial,
          origin_resource: "customer_vendor_requirement_artifact",
          origin_id: artifact.id,
          origin_label: artifact.title,
          origin_url: "/commercial/vendor-onboarding",
          organization_id: onboarding.customer_organization_id,
          metadata: %{
            "customer_vendor_onboarding_id" => onboarding.id,
            "customer_vendor_requirement_id" => requirement.id,
            "artifact_kind" => Atom.to_string(artifact.kind),
            "workflow" => "vendor_form_intake"
          }
        },
        actor: context.actor,
        authorize?: false
      )

    {:ok, artifact}
  end

  defp create_source_form_review_task(_changeset, artifact, _context), do: {:ok, artifact}
end
