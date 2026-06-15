defmodule GnomeGardenWeb.CommercialVendorPacketLiveTest do
  use GnomeGardenWeb.ConnCase

  setup :register_and_log_in_user

  import Phoenix.LiveViewTest

  alias GnomeGarden.Company
  alias GnomeGarden.Company.DefaultRegistration

  setup do
    AshStorage.Service.Test.reset!()
    :ok
  end

  test "renders vendor packet with sensitive values masked until revealed", %{conn: conn} do
    assert {:ok, _result} =
             Company.import_vendor_onboarding(vendor_payload(), authorize?: false)

    profile = DefaultRegistration.ensure_default().profile

    assert {:ok, _document} =
             Company.create_company_document(%{
               company_profile_id: profile.id,
               key: "live-w9",
               title: "Live W-9",
               kind: :w9,
               file: sample_file("live-w9.pdf")
             })

    {:ok, view, html} = live(conn, ~p"/commercial/vendor-onboarding")

    assert html =~ "Customer Onboarding"
    assert html =~ "PolyPeptide Laboratories Group"
    assert html =~ "Return signed vendor packet PDF"
    assert html =~ "Supplier Code of Conduct confirmation letter"
    assert html =~ "Legal entity name"
    assert html =~ "Gnome Automation LLC"
    assert html =~ "Account number"
    assert html =~ "**** 0001"
    assert html =~ "Linked company document"
    assert html =~ "Live W-9"
    assert html =~ "Open File"
    refute html =~ "TEST-CHECKING-0001"

    html =
      view
      |> element("button", "Reveal Sensitive")
      |> render_click()

    assert html =~ "TEST-CHECKING-0001"
    assert html =~ "Hide Sensitive"
  end

  test "opens rejection modal and records requirement rejection", %{conn: conn} do
    {:ok, view, html} = live(conn, ~p"/commercial/vendor-onboarding")

    assert html =~ "Return signed vendor packet PDF"

    html =
      view
      |> element(
        "#vendor-requirement-return_signed_pdf button[phx-click='open_reject_requirement']"
      )
      |> render_click()

    assert html =~ "Reject requirement"
    assert html =~ "What needs to be corrected?"

    html =
      view
      |> form("#reject-requirement-form", %{
        "rejection_reason" => "Missing signed title."
      })
      |> render_submit()

    assert html =~ "Missing signed title."
    assert html =~ "Rejected"
  end

  test "uploads a customer-specific source form artifact from a requirement", %{conn: conn} do
    {:ok, view, html} = live(conn, ~p"/commercial/vendor-onboarding")

    assert html =~ "Return signed vendor packet PDF"

    html =
      view
      |> element("#vendor-requirement-return_signed_pdf button[phx-click='open_artifact_upload']")
      |> render_click()

    assert html =~ "Upload requirement artifact"
    assert html =~ "Drop the customer form"

    contents = sample_docx_binary()

    upload =
      file_input(view, "#requirement-artifact-form", :artifact_file, [
        %{
          name: "prospective-vendor-information.docx",
          content: contents,
          size: byte_size(contents),
          type: "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
        }
      ])

    assert render_upload(upload, "prospective-vendor-information.docx") =~ "100%"

    html =
      view
      |> form("#requirement-artifact-form", %{
        "artifact" => %{
          "title" => "Prospective Vendor Information source form",
          "kind" => "source_form",
          "notes" => "Customer-provided form to extract and fill."
        }
      })
      |> render_submit()

    assert html =~ "Requirement artifact uploaded."
    assert html =~ "Prospective Vendor Information source form"
    assert html =~ "Source Form"
    assert html =~ "Populate"
    assert html =~ "Open File"

    html =
      view
      |> element("#vendor-requirement-return_signed_pdf button[phx-click='populate_artifact']")
      |> render_click()

    assert html =~ "Filled draft created."
    assert html =~ "Prospective Vendor Information source form filled draft"
    assert html =~ "Filled Docx"
    assert html =~ "Drafted"
  end

  defp vendor_payload do
    %{
      "company" => %{
        "legal_entity_name" => "Gnome Automation LLC",
        "entity_type" => "LLC (California)"
      },
      "tax_identifiers" => %{
        "fein_us" => %{"value" => "99-0000001"}
      },
      "banking" => %{
        "provider" => "Mercury",
        "bank_of_record" => "Column N.A.",
        "account" => %{
          "kind" => "checking",
          "number" => "TEST-CHECKING-0001",
          "routing_number" => "121145433"
        }
      }
    }
  end

  defp sample_file(filename) do
    path = Path.join(System.tmp_dir!(), filename)
    File.write!(path, "%PDF-1.4\n% commercial vendor packet live test\n")
    Ash.Type.File.from_path(path)
  end

  defp sample_docx_binary do
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
           <w:p><w:r><w:t>Legal Entity name:</w:t></w:r></w:p>
           <w:p><w:r><w:t>FEIN (US):</w:t></w:r></w:p>
           <w:p><w:r><w:t>Bank account / Bank Giro:</w:t></w:r></w:p>
         </w:body>
       </w:document>
       """}
    ]

    {:ok, {_name, zip}} = :zip.create(~c"prospective-vendor-information.docx", files, [:memory])
    zip
  end

  test "legacy commercial vendor packet route still renders", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/commercial/vendor-packet")

    assert html =~ "Customer Onboarding"
  end

  test "legacy company vendor packet route still renders", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/company/vendor-packet")

    assert html =~ "Customer Onboarding"
  end
end
