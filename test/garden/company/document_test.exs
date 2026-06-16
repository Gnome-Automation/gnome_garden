defmodule GnomeGarden.Company.DocumentTest do
  use GnomeGarden.DataCase

  alias GnomeGarden.Company

  setup do
    AshStorage.Service.Test.reset!()

    {:ok, profile} =
      Company.create_company_profile(%{
        key: "docs-test-#{System.unique_integer([:positive])}",
        name: "Gnome Automation",
        legal_name: "Gnome Automation LLC"
      })

    %{profile: profile}
  end

  test "creates a company-owned document with an attached file", %{profile: profile} do
    file = sample_file()

    assert {:ok, document} =
             Company.create_company_document(%{
               company_profile_id: profile.id,
               key: "w9",
               title: "Gnome Automation W-9",
               kind: :w9,
               signed_on: ~D[2026-06-11],
               file: file
             })

    document = Ash.load!(document, [file: :blob], authorize?: false)

    assert document.company_profile_id == profile.id
    assert document.kind == :w9
    assert document.file.name == "file"
    assert String.ends_with?(document.file.blob.filename, ".pdf")
  end

  test "lists active documents by kind and company profile", %{profile: profile} do
    file = sample_file()

    assert {:ok, document} =
             Company.create_company_document(%{
               company_profile_id: profile.id,
               key: "w9",
               title: "Gnome Automation W-9",
               kind: :w9,
               file: file
             })

    assert {:ok, [by_kind]} = Company.list_company_documents_by_kind(:w9)
    assert by_kind.id == document.id

    assert {:ok, [for_profile]} = Company.list_company_documents_for_profile(profile.id)
    assert for_profile.id == document.id
    assert for_profile.file_url
    assert String.ends_with?(for_profile.file.blob.filename, ".pdf")
  end

  test "retired documents leave the active list", %{profile: profile} do
    file = sample_file()

    assert {:ok, document} =
             Company.create_company_document(%{
               company_profile_id: profile.id,
               key: "w9",
               title: "Gnome Automation W-9",
               kind: :w9,
               file: file
             })

    assert {:ok, retired} = Company.retire_company_document(document)
    assert retired.status == :retired

    assert {:ok, []} = Company.list_active_company_documents()
  end

  test "updates document metadata and replaces the attached file", %{profile: profile} do
    assert {:ok, document} =
             Company.create_company_document(%{
               company_profile_id: profile.id,
               key: "banking-letter",
               title: "Banking letter",
               kind: :banking_letter,
               file: sample_file("original-bank-letter.pdf")
             })

    assert {:ok, updated} =
             Company.update_company_document(document, %{
               title: "Mercury banking letter",
               kind: :banking_letter,
               file: sample_file("replacement-bank-letter.pdf")
             })

    updated = Ash.load!(updated, [file: :blob], authorize?: false)

    assert updated.title == "Mercury banking letter"
    assert updated.file.blob.filename == "replacement-bank-letter.pdf"
  end

  test "supports business license document category", %{profile: profile} do
    assert {:ok, document} =
             Company.create_company_document(%{
               company_profile_id: profile.id,
               key: "business-license",
               title: "Business license",
               kind: :business_license,
               file: sample_file("business-license.pdf")
             })

    assert document.kind == :business_license
  end

  test "stores lightweight document tags in metadata", %{profile: profile} do
    assert {:ok, document} =
             Company.create_company_document(%{
               company_profile_id: profile.id,
               key: "tagged-w9",
               title: "Tagged W-9",
               kind: :w9,
               metadata: %{"tags" => ["vendor setup", "tax"]},
               file: sample_file("tagged-w9.pdf")
             })

    assert document.metadata["tags"] == ["vendor setup", "tax"]

    assert {:ok, updated} =
             Company.update_company_document(document, %{
               metadata: %{"tags" => ["customer portal"], "source" => "manual"}
             })

    assert updated.metadata == %{"tags" => ["customer portal"], "source" => "manual"}
  end

  defp sample_file(filename \\ nil) do
    filename =
      filename || "gnome-garden-company-document-#{System.unique_integer([:positive])}.pdf"

    path =
      Path.join(
        System.tmp_dir!(),
        filename
      )

    File.write!(path, "%PDF-1.4\n% company document test\n")
    Ash.Type.File.from_path(path)
  end
end
