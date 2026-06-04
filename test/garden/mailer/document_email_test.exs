defmodule GnomeGarden.Mailer.DocumentEmailTest do
  use ExUnit.Case, async: true

  alias GnomeGarden.Mailer.DocumentEmail

  defp w9_doc do
    %{
      name: "W9 Form",
      category: :tax,
      version: "2024",
      file_path: "documents/w9-gnome-automation-signed.pdf",
      status: :active,
      description: "IRS Form W-9"
    }
  end

  test "builds email with correct to, subject, and attachment" do
    email = DocumentEmail.build(w9_doc(), "client@example.com")

    assert email.to == [{"", "client@example.com"}]
    assert email.subject == "Gnome Automation — W9 Form"
    assert email.html_body =~ "W9 Form"

    attachment = List.first(email.attachments)
    assert attachment != nil
    assert attachment.content_type == "application/pdf"
    assert attachment.filename == "Gnome-Automation-W9-Form-2024.pdf"
  end

  test "includes optional message in body" do
    email = DocumentEmail.build(w9_doc(), "client@example.com", message: "Please review and keep for your records.")
    assert email.html_body =~ "Please review"
  end

  test "includes org name in greeting when provided" do
    email = DocumentEmail.build(w9_doc(), "client@example.com", org_name: "Acme Corp")
    assert email.html_body =~ "Acme Corp"
  end
end
