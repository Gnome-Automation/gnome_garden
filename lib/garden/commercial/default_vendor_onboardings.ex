defmodule GnomeGarden.Commercial.DefaultVendorOnboardings do
  @moduledoc """
  Idempotent bootstrap for known customer vendor onboarding cases.
  """

  alias GnomeGarden.Commercial
  alias GnomeGarden.Company
  alias GnomeGarden.Company.DefaultProfiles
  alias GnomeGarden.Operations

  @polypeptide_key "polypeptide"
  @polypeptide_name "PolyPeptide Laboratories Group"

  @polypeptide_requirements [
    %{
      key: "return_signed_pdf",
      title: "Return signed vendor packet PDF",
      requirement_type: :signature,
      status: :ready,
      required: true,
      sort_order: 10,
      instructions:
        "Send the completed and signed vendor packet back to Omar.Trejo@polypeptide.com as a signed PDF file."
    },
    %{
      key: "w9",
      title: "Send current W-9",
      requirement_type: :tax_document,
      document_kind: :w9,
      required: true,
      sort_order: 20,
      instructions: "Use Gnome's current signed W-9 when requested for US tax information."
    },
    %{
      key: "banking_information",
      title: "Provide vendor banking information",
      requirement_type: :banking_document,
      document_kind: :banking_letter,
      required: true,
      sort_order: 30,
      instructions:
        "Provide legal entity name, bank name, bank address, account number, SWIFT/BIC, routing number, and N/A values for India-only fields."
    },
    %{
      key: "standard_terms",
      title: "Confirm standard commercial terms",
      requirement_type: :terms,
      status: :ready,
      required: true,
      sort_order: 40,
      instructions: "Use DDP delivery terms, Net 60 payment terms, and USD currency."
    },
    %{
      key: "invoice_requirements",
      title: "Apply PolyPeptide invoice instructions",
      requirement_type: :invoice_instruction,
      status: :ready,
      required: true,
      sort_order: 50,
      instructions:
        "Invoices must be emailed as PDF files to Accountspayable.torrance@polypeptide.com and include location/address, invoice number/date, due date, totals, VAT/GST amount, currency code, references, delivery note when applicable, and PO number when applicable."
    },
    %{
      key: "supplier_code_confirmation",
      title: "Supplier Code of Conduct confirmation letter",
      requirement_type: :supplier_code,
      document_kind: :supplier_code_confirmation,
      required: true,
      sort_order: 60,
      instructions:
        "Review PolyPeptide terms and supplier code of conduct from their Downloads page, execute the supplier confirmation letter, and return it."
    }
  ]

  @spec ensure_polypeptide(keyword()) :: %{
          profile: GnomeGarden.Company.Profile.t(),
          organization: GnomeGarden.Operations.Organization.t(),
          onboarding: GnomeGarden.Commercial.CustomerVendorOnboarding.t()
        }
  def ensure_polypeptide(opts \\ []) do
    actor = Keyword.get(opts, :actor)
    profile = DefaultProfiles.ensure_default().profile
    organization = ensure_polypeptide_organization!(actor)
    onboarding = ensure_onboarding!(profile, organization, actor)

    documents =
      profile.id
      |> Company.list_company_documents_for_profile(actor: actor, authorize?: false)
      |> case do
        {:ok, documents} -> documents
        {:error, _error} -> []
      end

    Enum.each(@polypeptide_requirements, &ensure_requirement!(&1, onboarding, documents, actor))

    {:ok, onboarding} =
      Commercial.get_customer_vendor_onboarding_by_key(profile.id, @polypeptide_key,
        actor: actor,
        authorize?: false
      )

    %{profile: profile, organization: organization, onboarding: onboarding}
  end

  defp ensure_polypeptide_organization!(actor) do
    {:ok, organization} =
      Operations.create_organization(
        %{
          name: @polypeptide_name,
          legal_name: @polypeptide_name,
          organization_kind: :business,
          status: :active,
          relationship_roles: ["customer"],
          primary_region: "Torrance, CA",
          notes: "Customer vendor onboarding profile for PolyPeptide supplier setup."
        },
        actor: actor,
        authorize?: false
      )

    organization
  end

  defp ensure_onboarding!(profile, organization, actor) do
    attrs = %{
      company_profile_id: profile.id,
      customer_organization_id: organization.id,
      key: @polypeptide_key,
      customer_name: @polypeptide_name,
      status: :active,
      return_email: "Omar.Trejo@polypeptide.com",
      invoice_email: "Accountspayable.torrance@polypeptide.com",
      payment_terms: "Net 60",
      delivery_terms: "DDP",
      currency: "USD",
      instructions: [
        "Return completed vendor packet as a signed PDF.",
        "Use the PolyPeptide invoice information on all vendor invoices.",
        "Execute and return the Supplier Code of Conduct confirmation letter."
      ],
      terms_url: "Downloads-PolyPeptide",
      supplier_code_url: "Downloads-PolyPeptide",
      metadata: %{
        "source" => "Prospective Vendor Information-Signed.docx",
        "source_date" => "2026-06-11"
      }
    }

    case Commercial.get_customer_vendor_onboarding_by_key(profile.id, @polypeptide_key,
           actor: actor,
           authorize?: false
         ) do
      {:ok, onboarding} ->
        update_attrs =
          Map.drop(attrs, [:company_profile_id, :key])

        {:ok, onboarding} =
          Commercial.update_customer_vendor_onboarding(onboarding, update_attrs,
            actor: actor,
            authorize?: false
          )

        onboarding

      {:error, _error} ->
        {:ok, onboarding} =
          Commercial.create_customer_vendor_onboarding(attrs, actor: actor, authorize?: false)

        onboarding
    end
  end

  defp ensure_requirement!(template, onboarding, documents, actor) do
    company_document = find_document(documents, Map.get(template, :document_kind))
    status = Map.get(template, :status) || if company_document, do: :ready, else: :missing

    attrs =
      template
      |> Map.drop([:document_kind])
      |> Map.put(:customer_vendor_onboarding_id, onboarding.id)
      |> Map.put(:company_document_id, company_document && company_document.id)
      |> Map.put(:status, status)

    case Commercial.get_customer_vendor_requirement_by_key(onboarding.id, template.key,
           actor: actor,
           authorize?: false
         ) do
      {:ok, requirement} ->
        update_attrs =
          Map.drop(attrs, [
            :customer_vendor_onboarding_id,
            :key,
            :status,
            :sent_to_email,
            :sent_at,
            :accepted_at,
            :rejected_at,
            :rejection_reason,
            :waived_at
          ])
          |> maybe_mark_ready(requirement, status)

        {:ok, _requirement} =
          Commercial.update_customer_vendor_requirement(requirement, update_attrs,
            actor: actor,
            authorize?: false
          )

      {:error, _error} ->
        {:ok, _requirement} =
          Commercial.create_customer_vendor_requirement(attrs, actor: actor, authorize?: false)
    end
  end

  defp find_document(_documents, nil), do: nil

  defp find_document(documents, kind) do
    Enum.find(documents, &(&1.kind == kind and &1.status == :active))
  end

  defp maybe_mark_ready(attrs, %{status: :missing}, :ready), do: Map.put(attrs, :status, :ready)
  defp maybe_mark_ready(attrs, _requirement, _status), do: attrs
end
