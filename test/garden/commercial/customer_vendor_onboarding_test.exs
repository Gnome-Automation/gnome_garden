defmodule GnomeGarden.Commercial.CustomerVendorOnboardingTest do
  use GnomeGarden.DataCase

  alias GnomeGarden.Commercial
  alias GnomeGarden.Commercial.DefaultVendorOnboardings
  alias GnomeGarden.Company
  alias GnomeGarden.Company.DefaultRegistration
  alias GnomeGarden.Operations

  setup do
    AshStorage.Service.Test.reset!()
    :ok
  end

  test "ensures the PolyPeptide onboarding case and requirements" do
    %{onboarding: onboarding} = DefaultVendorOnboardings.ensure_polypeptide()

    assert onboarding.customer_name == "PolyPeptide Laboratories Group"
    assert onboarding.return_email == "Omar.Trejo@polypeptide.com"

    assert {:ok, requirements} =
             Commercial.list_customer_vendor_requirements_for_onboarding(onboarding.id)

    assert length(requirements) == 6

    requirements_by_key = Map.new(requirements, &{&1.key, &1})
    assert requirements_by_key["return_signed_pdf"].status == :ready
    assert requirements_by_key["supplier_code_confirmation"].status == :missing
  end

  test "requirement workflow records delivery history" do
    %{onboarding: onboarding} = DefaultVendorOnboardings.ensure_polypeptide()

    assert {:ok, requirement} =
             Commercial.get_customer_vendor_requirement_by_key(onboarding.id, "return_signed_pdf")

    assert {:ok, sent} =
             Commercial.send_customer_vendor_requirement(requirement, %{
               sent_to_email: onboarding.return_email,
               notes: "Sent signed packet."
             })

    assert sent.status == :sent
    assert sent.sent_to_email == onboarding.return_email

    assert {:ok, [delivery]} =
             Commercial.list_customer_vendor_requirement_deliveries_for_requirement(
               requirement.id
             )

    assert delivery.event_type == :sent
    assert delivery.recipient_email == onboarding.return_email

    assert {:ok, rejected} =
             Commercial.reject_customer_vendor_requirement(sent, %{
               rejection_reason: "Signature title missing."
             })

    assert rejected.status == :rejected
    assert rejected.rejection_reason == "Signature title missing."

    assert {:ok, deliveries} =
             Commercial.list_customer_vendor_requirement_deliveries_for_requirement(
               requirement.id
             )

    assert MapSet.new(Enum.map(deliveries, & &1.event_type)) == MapSet.new([:rejected, :sent])
  end

  test "links reusable company documents to matching PolyPeptide requirements" do
    profile = DefaultRegistration.ensure_default().profile

    assert {:ok, banking_document} =
             Company.create_company_document(%{
               company_profile_id: profile.id,
               key: "mercury-banking-letter",
               title: "Mercury banking letter",
               kind: :banking_letter,
               file: sample_file("mercury-banking-letter.pdf")
             })

    assert {:ok, supplier_code_document} =
             Company.create_company_document(%{
               company_profile_id: profile.id,
               key: "polypeptide-supplier-code-confirmation",
               title: "PolyPeptide supplier code confirmation",
               kind: :supplier_code_confirmation,
               file: sample_file("supplier-code-confirmation.pdf")
             })

    %{onboarding: onboarding} = DefaultVendorOnboardings.ensure_polypeptide()

    assert {:ok, requirements} =
             Commercial.list_customer_vendor_requirements_for_onboarding(onboarding.id)

    requirements_by_key = Map.new(requirements, &{&1.key, &1})

    assert requirements_by_key["banking_information"].company_document_id == banking_document.id
    assert requirements_by_key["banking_information"].status == :ready

    assert requirements_by_key["supplier_code_confirmation"].company_document_id ==
             supplier_code_document.id

    assert requirements_by_key["supplier_code_confirmation"].status == :ready
  end

  test "uploads customer-specific requirement artifact and creates a review task" do
    %{onboarding: onboarding} = DefaultVendorOnboardings.ensure_polypeptide()

    assert {:ok, requirement} =
             Commercial.get_customer_vendor_requirement_by_key(onboarding.id, "return_signed_pdf")

    assert {:ok, artifact} =
             Commercial.create_customer_vendor_requirement_artifact(%{
               customer_vendor_requirement_id: requirement.id,
               title: "PolyPeptide source vendor form",
               kind: :source_form,
               file: sample_docx_file("polypeptide-source-form.docx")
             })

    assert artifact.customer_vendor_requirement_id == requirement.id
    assert artifact.kind == :source_form

    assert {:ok, [loaded_artifact]} =
             Commercial.list_customer_vendor_requirement_artifacts_for_requirement(requirement.id)

    assert loaded_artifact.file_url

    assert {:ok, [task]} =
             Operations.list_tasks_by_origin(
               :commercial,
               "customer_vendor_requirement_artifact",
               artifact.id
             )

    assert task.title == "Review vendor form: Return signed vendor packet PDF"
    assert task.organization_id == onboarding.customer_organization_id
    assert task.metadata["workflow"] == "vendor_form_intake"
  end

  test "populates a customer-specific source form into a filled draft artifact" do
    assert {:ok, _result} =
             Company.import_vendor_onboarding(vendor_payload(), authorize?: false)

    %{onboarding: onboarding} = DefaultVendorOnboardings.ensure_polypeptide()

    assert {:ok, requirement} =
             Commercial.get_customer_vendor_requirement_by_key(onboarding.id, "return_signed_pdf")

    assert {:ok, source_artifact} =
             Commercial.create_customer_vendor_requirement_artifact(%{
               customer_vendor_requirement_id: requirement.id,
               title: "PolyPeptide source vendor form",
               kind: :source_form,
               file: sample_docx_file("polypeptide-source-form.docx")
             })

    assert {:ok, result} =
             Commercial.populate_customer_vendor_requirement_artifact(source_artifact.id,
               authorize?: false
             )

    assert result["missing_fields"] == []

    assert {:ok, [filled_artifact]} =
             Commercial.list_customer_vendor_requirement_artifacts_for_requirement(requirement.id)
             |> then(fn {:ok, artifacts} ->
               {:ok, Enum.filter(artifacts, &(&1.kind == :filled_docx))}
             end)

    assert filled_artifact.status == :drafted
    assert filled_artifact.metadata["source_artifact_id"] == source_artifact.id

    filled_artifact = Ash.load!(filled_artifact, [file: :blob], authorize?: false)
    blob = filled_artifact.file.blob
    assert {:ok, data} = AshStorage.Service.Test.download(blob.key, [])
    assert {:ok, files} = :zip.unzip(data, [:memory])

    assert {_path, xml} =
             Enum.find(files, fn {path, _contents} -> to_string(path) == "word/document.xml" end)

    xml = IO.iodata_to_binary(xml)

    assert xml =~ "Legal Entity name: Gnome Automation LLC"
    assert xml =~ "FEIN (US): 99-0000001"
    assert xml =~ "Bank account / Bank Giro: TEST-CHECKING-0001"
  end

  defp sample_file(filename) do
    path = Path.join(System.tmp_dir!(), filename)
    File.write!(path, "%PDF-1.4\n% customer vendor onboarding test\n")
    Ash.Type.File.from_path(path)
  end

  defp sample_docx_file(filename) do
    path = Path.join(System.tmp_dir!(), filename)

    files = [
      {~c"[Content_Types].xml",
       """
       <?xml version="1.0" encoding="UTF-8"?>
       <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
         <Default Extension="xml" ContentType="application/xml"/>
         <Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
       </Types>
       """},
      {~c"word/document.xml",
       """
       <?xml version="1.0" encoding="UTF-8"?>
       <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
         <w:body>
           <w:p><w:r><w:t>Prospective Vendor Information</w:t></w:r></w:p>
           <w:p><w:r><w:t>Legal Entity name:</w:t></w:r></w:p>
           <w:p><w:r><w:t>Registered Address of Company:</w:t></w:r></w:p>
           <w:p><w:r><w:t>Postcode:</w:t></w:r></w:p>
           <w:p><w:r><w:t>Country:</w:t></w:r></w:p>
           <w:p><w:r><w:t>Telephone number:</w:t></w:r></w:p>
           <w:p><w:r><w:t>E-mail for orders:</w:t></w:r></w:p>
           <w:p><w:r><w:t>FEIN (US):</w:t></w:r></w:p>
           <w:p><w:r><w:t>Delivery terms (standard DDP or DAP):</w:t></w:r></w:p>
           <w:p><w:r><w:t>Payment terms (standard min 60 days net):</w:t></w:r></w:p>
           <w:p><w:r><w:t>Currency:</w:t></w:r></w:p>
           <w:p><w:r><w:t>Vendor contact (name):</w:t></w:r></w:p>
           <w:p><w:r><w:t>Direct phone number:</w:t></w:r></w:p>
           <w:p><w:r><w:t>E-mail for Purchasing:</w:t></w:r></w:p>
           <w:p><w:r><w:t>E-mail for Finance:</w:t></w:r></w:p>
           <w:p><w:r><w:t>Bank name:</w:t></w:r></w:p>
           <w:p><w:r><w:t>Bank address:</w:t></w:r></w:p>
           <w:p><w:r><w:t>Bank account / Bank Giro:</w:t></w:r></w:p>
           <w:p><w:r><w:t>Swift address:</w:t></w:r></w:p>
           <w:p><w:r><w:t>IBAN:</w:t></w:r></w:p>
           <w:p><w:r><w:t>Bank Routing Number (ACH):</w:t></w:r></w:p>
           <w:p><w:r><w:t>Bank Routing Number (Wire):</w:t></w:r></w:p>
           <w:p><w:r><w:t>Name:</w:t></w:r></w:p>
           <w:p><w:r><w:t>Title:</w:t></w:r></w:p>
         </w:body>
       </w:document>
       """}
    ]

    {:ok, {_name, zip}} = :zip.create(String.to_charlist(filename), files, [:memory])
    File.write!(path, zip)
    Ash.Type.File.from_path(path)
  end

  defp vendor_payload do
    %{
      "company" => %{
        "legal_entity_name" => "Gnome Automation LLC",
        "legal_address" => %{
          "street" => "2108 N St, STE N",
          "city" => "Sacramento",
          "state" => "CA",
          "zip" => "95816",
          "country" => "US"
        },
        "telephone_number" => "(657) 866-4636",
        "signing_authority" => %{"name" => "Patrick Curran", "title" => "Member"}
      },
      "contacts" => %{
        "orders_email" => "sales@gnomeautomation.com",
        "purchasing_email" => "sales@gnomeautomation.com",
        "finance_email" => "sales@gnomeautomation.com",
        "vendor_contact" => %{
          "name" => "Patrick Curran",
          "phone" => "970-556-4676"
        }
      },
      "tax_identifiers" => %{
        "fein_us" => %{"value" => "99-0000001"}
      },
      "banking" => %{
        "provider" => "Mercury",
        "bank_of_record" => "Column N.A.",
        "bank_address" =>
          "1 Letterman Drive, Building A, Suite A4-700, San Francisco, CA 94129 US",
        "account" => %{
          "kind" => "checking",
          "number" => "TEST-CHECKING-0001",
          "routing_number" => "121145433"
        },
        "international_wire" => %{
          "swift_bic" => "CLNOUS66MER",
          "iban_or_account_number" => "N/A"
        }
      },
      "standard_terms" => %{
        "delivery_terms" => %{"default_answer" => "DDP"},
        "payment_terms" => %{"default_answer" => "Net 60"},
        "currency" => "USD"
      }
    }
  end
end
