defmodule GnomeGarden.Documents.CompanyDocumentTest do
  use GnomeGarden.DataCase, async: false

  alias GnomeGarden.Documents

  test "creates a company document" do
    {:ok, doc} =
      Documents.create_document(%{
        name: "W9 Form",
        category: :tax,
        version: "2024",
        file_path: "documents/w9-gnome-automation-signed.pdf",
        status: :active
      })

    assert doc.name == "W9 Form"
    assert doc.category == :tax
    assert doc.version == "2024"
    assert doc.status == :active
  end

  test "lists only active documents" do
    {:ok, _} =
      Documents.create_document(%{
        name: "Active Doc",
        category: :tax,
        version: "1.0",
        file_path: "documents/test.pdf",
        status: :active
      })

    {:ok, _} =
      Documents.create_document(%{
        name: "Old Doc",
        category: :tax,
        version: "0.9",
        file_path: "documents/test.pdf",
        status: :superseded
      })

    {:ok, docs} = Documents.list_active_documents()
    names = Enum.map(docs, & &1.name)
    assert "Active Doc" in names
    refute "Old Doc" in names
  end

  test "lists all documents including superseded" do
    {:ok, _} =
      Documents.create_document(%{
        name: "Superseded Doc",
        category: :legal,
        version: "0.1",
        file_path: "documents/test.pdf",
        status: :superseded
      })

    {:ok, docs} = Documents.list_all_documents()
    names = Enum.map(docs, & &1.name)
    assert "Superseded Doc" in names
  end

  test "updates document status" do
    {:ok, doc} =
      Documents.create_document(%{
        name: "To Update",
        category: :compliance,
        version: "1.0",
        file_path: "documents/test.pdf",
        status: :active
      })

    {:ok, updated} = Documents.update_document(doc, %{status: :superseded})
    assert updated.status == :superseded
  end
end
