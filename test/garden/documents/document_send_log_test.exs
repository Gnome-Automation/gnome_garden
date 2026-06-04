defmodule GnomeGarden.Documents.DocumentSendLogTest do
  use GnomeGarden.DataCase, async: false

  alias GnomeGarden.Documents

  defp create_doc do
    {:ok, doc} =
      Documents.create_document(%{
        name: "Test Doc #{System.unique_integer([:positive])}",
        category: :tax,
        version: "1.0",
        file_path: "documents/test.pdf",
        status: :active
      })
    doc
  end

  test "logs a document send" do
    doc = create_doc()
    user_id = Ecto.UUID.generate()

    {:ok, log} =
      Documents.log_send(%{
        company_document_id: doc.id,
        sent_to_email: "client@example.com",
        sent_by_user_id: user_id
      })

    assert log.sent_to_email == "client@example.com"
    assert log.company_document_id == doc.id
    assert log.sent_at != nil
  end

  test "lists send logs for a document" do
    doc = create_doc()
    user_id = Ecto.UUID.generate()

    {:ok, _} =
      Documents.log_send(%{
        company_document_id: doc.id,
        sent_to_email: "a@example.com",
        sent_by_user_id: user_id
      })

    {:ok, _} =
      Documents.log_send(%{
        company_document_id: doc.id,
        sent_to_email: "b@example.com",
        sent_by_user_id: user_id
      })

    {:ok, logs} = Documents.list_send_logs_for_document(doc.id)
    assert length(logs) == 2
    emails = Enum.map(logs, & &1.sent_to_email)
    assert "a@example.com" in emails
    assert "b@example.com" in emails
  end
end
